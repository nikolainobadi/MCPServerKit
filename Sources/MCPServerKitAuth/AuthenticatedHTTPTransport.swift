//
//  AuthenticatedHTTPTransport.swift
//  MCPServerKitAuth
//
//  Created by Nikolai Nobadi on 2/10/26.
//

import MCP
import Logging
import Hummingbird
import HTTPTypes
import Foundation
import JWTKit
import MCPServerKit

/// HTTP transport with OAuth 2.1 JWT validation baked in.
///
/// Uses a pull-based `AsyncThrowingStream(unfolding:)` for `receive()` so that
/// the auth context is set on the `AuthContextHolder` **before** the MCP Server
/// processes each message. This guarantees the correct per-request auth context
/// even under concurrent HTTP requests.
public actor AuthenticatedHTTPTransport: Transport {
    public nonisolated let logger: Logger

    private let host: String
    private let port: Int
    private let path: String
    private let maxPayloadSize: Int
    private let config: OAuthConfiguration
    private let jwksClient: JWKSClient
    private let authContextHolder: AuthContextHolder
    private let messageChannel: AuthenticatedMessageChannel

    // Request-response correlation
    private var pendingRequests: [String: CheckedContinuation<Data, any Error>] = [:]
    private var batchIdToPrimary: [String: String] = [:]

    // Lifecycle
    private var isConnected = false
    private var applicationTask: Task<Void, any Error>?

    // Session management
    private var sessionId: String?
    private var isTerminated = false

    // SSE streaming
    private var sseContinuation: AsyncStream<Data>.Continuation?

    public init(
        config: OAuthConfiguration,
        jwksClient: JWKSClient,
        authContextHolder: AuthContextHolder,
        host: String = "0.0.0.0",
        port: Int = 8000,
        path: String = "/mcp",
        maxPayloadSize: Int = 1_048_576,
        logger: Logger? = nil
    ) {
        self.config = config
        self.jwksClient = jwksClient
        self.authContextHolder = authContextHolder
        self.messageChannel = AuthenticatedMessageChannel()
        self.host = host
        self.port = port
        self.path = path
        self.maxPayloadSize = maxPayloadSize
        self.logger = logger ?? Logger(
            label: "mcp.transport.http.authenticated",
            factory: { _ in SwiftLogNoOpLogHandler() }
        )
    }
}

// MARK: - Transport Protocol
extension AuthenticatedHTTPTransport {
    public func connect() async throws {
        guard !isConnected else { return }
        isConnected = true

        let router = buildRouter()
        let app = Application(
            router: router,
            configuration: .init(address: .hostname(host, port: port)),
            logger: logger
        )

        logger.info("Authenticated HTTP transport starting", metadata: [
            "host": "\(host)", "port": "\(port)", "path": "\(path)"
        ])

        applicationTask = Task {
            try await app.runService()
        }
    }

    public func disconnect() async {
        guard isConnected else { return }
        isConnected = false
        isTerminated = true

        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: TransportError.transportDisconnected)
        }
        pendingRequests.removeAll()
        batchIdToPrimary.removeAll()

        sseContinuation?.finish()
        sseContinuation = nil

        applicationTask?.cancel()
        applicationTask = nil

        await messageChannel.finish()
        logger.debug("Authenticated HTTP transport disconnected")
    }

    public func send(_ data: Data) async throws {
        if sessionId == nil {
            sessionId = UUID().uuidString
        }

        let classification = classifyOutgoing(data)

        switch classification {
        case .response(let id):
            resumePendingRequest(id: id, data: data)
        case .batchResponse(let ids):
            for id in ids {
                let resolvedId = batchIdToPrimary[id] ?? id
                if pendingRequests[resolvedId] != nil {
                    resumePendingRequest(id: id, data: data)
                    return
                }
            }
            logger.warning("No pending request found for batch response")
        case .notification, .serverRequest:
            sseContinuation?.yield(data)
        }
    }

    /// Pull-based receive stream.
    ///
    /// Each call to the unfolding closure dequeues one `(data, authContext)` pair
    /// from the channel, sets `authContextHolder.current`, then returns the data.
    /// The MCP Server's sequential `for try await` loop guarantees each message
    /// is fully processed before the next auth context is set.
    public func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        let channel = self.messageChannel
        let holder = self.authContextHolder

        return AsyncThrowingStream {
            guard let (data, authContext) = try await channel.next() else {
                return nil
            }
            holder.current = authContext
            return data
        }
    }
}

// MARK: - Router Setup
private extension AuthenticatedHTTPTransport {
    func buildRouter() -> Router<BasicRequestContext> {
        let router = Router(context: BasicRequestContext.self)
        let transport = self

        // Protected Resource Metadata (unauthenticated)
        let wellKnownPath = RouterPath("/.well-known/oauth-protected-resource\(path)")
        router.get(wellKnownPath) { _, _ -> Response in
            return await transport.handleMetadataRequest()
        }

        // MCP routes (authenticated)
        router.post(RouterPath(path)) { request, context -> Response in
            return try await transport.handlePost(request: request, context: context)
        }

        router.get(RouterPath(path)) { request, context -> Response in
            return try await transport.handleGet(request: request, context: context)
        }

        router.delete(RouterPath(path)) { request, context -> Response in
            return try await transport.handleDelete(request: request, context: context)
        }

        return router
    }
}

// MARK: - Metadata Endpoint
private extension AuthenticatedHTTPTransport {
    func handleMetadataRequest() -> Response {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        guard let data = try? encoder.encode(config.metadata) else {
            return Response(status: .internalServerError)
        }
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok,
            headers: headers,
            body: .init(byteBuffer: ByteBuffer(bytes: data))
        )
    }
}

// MARK: - Auth Validation Result
private enum AuthValidationResult {
    case success(AuthContext)
    case failure(Response)
}

// MARK: - Auth Validation
private extension AuthenticatedHTTPTransport {
    /// Validates the Bearer token from the Authorization header.
    func validateAuth(request: Request) async -> AuthValidationResult {
        guard let authHeader = request.headers[.authorization],
              authHeader.lowercased().hasPrefix("bearer "),
              authHeader.count > 7 else {
            return .failure(unauthorizedResponse())
        }

        let token = String(authHeader.dropFirst(7))

        let authContext: AuthContext
        do {
            authContext = try await validateToken(token)
        } catch {
            logger.debug("JWT validation failed: \(error)")
            return .failure(unauthorizedResponse())
        }

        if let requiredScopes = config.requiredScopes {
            guard requiredScopes.isSubset(of: authContext.scopes) else {
                return .failure(forbiddenResponse(requiredScopes: requiredScopes))
            }
        }

        return .success(authContext)
    }

    func validateToken(_ token: String) async throws -> AuthContext {
        let keys = try await jwksClient.getKeys()
        let keyCollection = JWTKeyCollection()
        try await keyCollection.add(jwks: keys)

        let payload: MCPTokenPayload
        do {
            payload = try await keyCollection.verify(token, as: MCPTokenPayload.self)
        } catch {
            let refreshedKeys = try await jwksClient.refreshKeys()
            let refreshedCollection = JWTKeyCollection()
            try await refreshedCollection.add(jwks: refreshedKeys)
            payload = try await refreshedCollection.verify(token, as: MCPTokenPayload.self)
        }

        guard payload.issuer?.value == config.expectedIssuer else {
            throw OAuthError.invalidIssuer
        }

        guard payload.audience?.value.contains(config.expectedAudience) == true else {
            throw OAuthError.invalidAudience
        }

        if let expiration = payload.expiration {
            guard expiration.value > Date() else {
                throw OAuthError.tokenExpired
            }
        }

        let scopes: Set<String>
        if let scopeString = payload.scope {
            scopes = Set(scopeString.split(separator: " ").map(String.init))
        } else {
            scopes = []
        }

        var claims: [String: String] = [:]
        if let email = payload.email {
            claims["email"] = email
        }
        if let name = payload.name {
            claims["name"] = name
        }

        return AuthContext(
            subject: payload.subject?.value ?? "",
            issuer: payload.issuer?.value ?? "",
            scopes: scopes,
            claims: claims,
            rawToken: token
        )
    }
}

// MARK: - Route Handlers
private extension AuthenticatedHTTPTransport {
    func handlePost(request: Request, context: BasicRequestContext) async throws -> Response {
        guard !isTerminated else {
            return Response(status: .notFound)
        }

        // Validate auth
        let authContext: AuthContext
        switch await validateAuth(request: request) {
        case .success(let ctx):
            authContext = ctx
        case .failure(let response):
            return response
        }

        let contentType = request.headers[.contentType]
        guard contentType?.contains("application/json") == true else {
            return Response(status: .unsupportedMediaType)
        }

        if let existingSessionId = sessionId {
            let mcpSessionId = HTTPField.Name("Mcp-Session-Id")!
            if let requestSessionId = request.headers[mcpSessionId],
               requestSessionId != existingSessionId {
                return Response(status: .badRequest)
            }
        }

        let body: ByteBuffer
        do {
            body = try await request.body.collect(upTo: maxPayloadSize)
        } catch {
            return Response(status: .contentTooLarge)
        }

        guard let data = body.getData(at: body.readerIndex, length: body.readableBytes) else {
            return Response(status: .badRequest)
        }

        let classification = classifyIncoming(data)

        switch classification {
        case .notification:
            await messageChannel.send(data, authContext: authContext)
            return buildResponse(status: .accepted)

        case .request(let id):
            return try await handleRequestMessage(id: id, data: data, authContext: authContext)

        case .batch(let requestIds):
            return try await handleBatchMessage(requestIds: requestIds, data: data, authContext: authContext)

        case .invalid:
            return Response(status: .badRequest)
        }
    }

    func handleGet(request: Request, context: BasicRequestContext) async throws -> Response {
        guard !isTerminated else {
            return Response(status: .notFound)
        }

        // Validate auth for SSE connections
        let authResult = await validateAuth(request: request)
        switch authResult {
        case .success: break
        case .failure(let response): return response
        }

        let accept = request.headers[.accept]
        guard accept?.contains("text/event-stream") == true else {
            return Response(status: .notAcceptable)
        }

        if let existingSessionId = sessionId {
            let mcpSessionId = HTTPField.Name("Mcp-Session-Id")!
            if let requestSessionId = request.headers[mcpSessionId],
               requestSessionId != existingSessionId {
                return Response(status: .badRequest)
            }
        }

        let (stream, continuation) = AsyncStream<Data>.makeStream()
        self.sseContinuation = continuation

        var headers = HTTPFields()
        headers[.contentType] = "text/event-stream"
        let cacheControl = HTTPField.Name("Cache-Control")!
        headers[cacheControl] = "no-cache"
        let connection = HTTPField.Name("Connection")!
        headers[connection] = "keep-alive"
        let mcpSessionIdName = HTTPField.Name("Mcp-Session-Id")!
        if let sessionId {
            headers[mcpSessionIdName] = sessionId
        }

        return Response(status: .ok, headers: headers, body: .init { writer in
            let merged = AsyncStream<ByteBuffer> { mergedContinuation in
                let dataTask = Task {
                    for await data in stream {
                        if Task.isCancelled { break }
                        let json = String(decoding: data, as: UTF8.self)
                        let lines = json.split(separator: "\n", omittingEmptySubsequences: false)
                        var sseMessage = lines.map { "data: \($0)" }.joined(separator: "\n")
                        sseMessage += "\n\n"
                        mergedContinuation.yield(ByteBuffer(string: sseMessage))
                    }
                    mergedContinuation.finish()
                }

                let keepaliveTask = Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(30))
                        if Task.isCancelled { break }
                        mergedContinuation.yield(ByteBuffer(string: ": keepalive\n\n"))
                    }
                }

                mergedContinuation.onTermination = { _ in
                    dataTask.cancel()
                    keepaliveTask.cancel()
                }
            }

            for await buffer in merged {
                try await writer.write(buffer)
            }
            try await writer.finish(nil)
        })
    }

    func handleDelete(request: Request, context: BasicRequestContext) async throws -> Response {
        if let existingSessionId = sessionId {
            let mcpSessionId = HTTPField.Name("Mcp-Session-Id")!
            guard let requestSessionId = request.headers[mcpSessionId],
                  requestSessionId == existingSessionId else {
                return Response(status: .badRequest)
            }
        }

        isTerminated = true
        sseContinuation?.finish()
        sseContinuation = nil

        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: TransportError.sessionTerminated)
        }
        pendingRequests.removeAll()
        batchIdToPrimary.removeAll()

        return Response(status: .ok)
    }
}

// MARK: - Request Handling
private extension AuthenticatedHTTPTransport {
    func handleRequestMessage(id: String, data: Data, authContext: AuthContext) async throws -> Response {
        await messageChannel.send(data, authContext: authContext)

        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(30))
            self.timeoutRequest(id: id)
        }

        let responseData: Data
        do {
            responseData = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, any Error>) in
                pendingRequests[id] = continuation
            }
            timeoutTask.cancel()
        } catch is TransportError {
            timeoutTask.cancel()
            return Response(status: .requestTimeout)
        }

        return buildResponse(status: .ok, data: responseData)
    }

    func handleBatchMessage(requestIds: [String], data: Data, authContext: AuthContext) async throws -> Response {
        let primaryId = requestIds[0]
        for secondaryId in requestIds.dropFirst() {
            batchIdToPrimary[secondaryId] = primaryId
        }

        await messageChannel.send(data, authContext: authContext)

        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(30))
            self.timeoutRequest(id: primaryId)
        }

        let responseData: Data
        do {
            responseData = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, any Error>) in
                pendingRequests[primaryId] = continuation
            }
            timeoutTask.cancel()
        } catch is TransportError {
            timeoutTask.cancel()
            cleanupBatchMappings(primaryId: primaryId)
            return Response(status: .requestTimeout)
        }

        return buildResponse(status: .ok, data: responseData)
    }

    func resumePendingRequest(id: String, data: Data) {
        let resolvedId = batchIdToPrimary[id] ?? id
        if let continuation = pendingRequests.removeValue(forKey: resolvedId) {
            cleanupBatchMappings(primaryId: resolvedId)
            continuation.resume(returning: data)
        } else {
            logger.warning("No pending request for response ID: \(id)")
        }
    }

    func cleanupBatchMappings(primaryId: String) {
        batchIdToPrimary = batchIdToPrimary.filter { $0.value != primaryId }
    }

    func timeoutRequest(id: String) {
        if let continuation = pendingRequests.removeValue(forKey: id) {
            cleanupBatchMappings(primaryId: id)
            continuation.resume(throwing: TransportError.requestTimeout)
        }
    }
}

// MARK: - Response Helpers
private extension AuthenticatedHTTPTransport {
    func unauthorizedResponse() -> Response {
        var headers = HTTPFields()
        let resourceMetadataURL = buildWellKnownURL()
        headers[.wwwAuthenticate] = "Bearer resource_metadata=\"\(resourceMetadataURL)\""
        return Response(status: .unauthorized, headers: headers)
    }

    func forbiddenResponse(requiredScopes: Set<String>) -> Response {
        var headers = HTTPFields()
        let scopeList = requiredScopes.sorted().joined(separator: " ")
        headers[.wwwAuthenticate] = "Bearer error=\"insufficient_scope\", scope=\"\(scopeList)\""
        return Response(status: .forbidden, headers: headers)
    }

    func buildWellKnownURL() -> String {
        // Extract base URL from the resource identifier and append well-known path
        let resource = config.metadata.resource
        guard let url = URL(string: resource),
              let scheme = url.scheme,
              let host = url.host else {
            return resource
        }
        let port = url.port.map { ":\($0)" } ?? ""
        let resourcePath = url.path.isEmpty ? "" : url.path
        return "\(scheme)://\(host)\(port)/.well-known/oauth-protected-resource\(resourcePath)"
    }

    func buildResponse(status: HTTPResponse.Status, data: Data? = nil) -> Response {
        var headers = HTTPFields()
        let mcpSessionIdName = HTTPField.Name("Mcp-Session-Id")!
        if let sessionId {
            headers[mcpSessionIdName] = sessionId
        }

        if let data {
            headers[.contentType] = "application/json"
            return Response(
                status: status,
                headers: headers,
                body: .init(byteBuffer: ByteBuffer(bytes: data))
            )
        }

        return Response(status: status, headers: headers)
    }
}

// MARK: - Message Classification
extension AuthenticatedHTTPTransport {
    enum IncomingMessage: Equatable {
        case request(id: String)
        case notification
        case batch(requestIds: [String])
        case invalid
    }

    enum OutgoingMessage: Equatable {
        case response(id: String)
        case batchResponse(ids: [String])
        case notification
        case serverRequest
    }

    func classifyIncoming(_ data: Data) -> IncomingMessage {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return .invalid
        }

        if let array = json as? [[String: Any]] {
            let requestIds = array.compactMap { item -> String? in
                guard item["method"] != nil, item["id"] != nil else { return nil }
                return stringifyId(item["id"]!)
            }
            if requestIds.isEmpty { return .notification }
            return .batch(requestIds: requestIds)
        }

        guard let dict = json as? [String: Any] else { return .invalid }

        if let id = dict["id"], dict["method"] != nil {
            return .request(id: stringifyId(id))
        }

        if dict["method"] != nil { return .notification }

        return .invalid
    }

    func classifyOutgoing(_ data: Data) -> OutgoingMessage {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return .notification
        }

        if let array = json as? [[String: Any]] {
            let ids = array.compactMap { item -> String? in
                guard let id = item["id"] else { return nil }
                return stringifyId(id)
            }
            return .batchResponse(ids: ids)
        }

        guard let dict = json as? [String: Any] else { return .notification }

        if let id = dict["id"] {
            if dict["result"] != nil || dict["error"] != nil {
                return .response(id: stringifyId(id))
            }
            if dict["method"] != nil { return .serverRequest }
        }

        if dict["method"] != nil { return .notification }

        return .notification
    }

    func stringifyId(_ id: Any) -> String {
        if let intId = id as? Int { return String(intId) }
        if let doubleId = id as? Double { return String(Int(doubleId)) }
        if let strId = id as? String { return strId }
        return String(describing: id)
    }
}

// MARK: - Error Types
enum TransportError: Error, Sendable {
    case transportDisconnected
    case sessionTerminated
    case requestTimeout
}
