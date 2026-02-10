//
//  HTTPServerTransport.swift
//  MCPServerKit
//
//  Created by Nikolai Nobadi on 2/10/26.
//

import MCP
import Logging
import Hummingbird
import HTTPTypes
import Foundation

// MARK: - Error Types
enum HTTPServerTransportError: Error, Sendable {
    case transportDisconnected
    case sessionTerminated
    case requestTimeout
    case invalidMessage
    case payloadTooLarge
}

// MARK: - HTTPServerTransport
public actor HTTPServerTransport: Transport {
    public nonisolated let logger: Logger

    private let host: String
    private let port: Int
    private let path: String
    private let maxPayloadSize: Int

    // Stream/continuation pair (same pattern as StdioTransport)
    private let messageStream: AsyncThrowingStream<Data, Swift.Error>
    private let messageContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation

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
        host: String = "0.0.0.0",
        port: Int = 8000,
        path: String = "/mcp",
        maxPayloadSize: Int = 1_048_576,
        logger: Logger? = nil
    ) {
        self.host = host
        self.port = port
        self.path = path
        self.maxPayloadSize = maxPayloadSize
        self.logger = logger ?? Logger(
            label: "mcp.transport.http.server",
            factory: { _ in SwiftLogNoOpLogHandler() }
        )

        var continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation!
        self.messageStream = AsyncThrowingStream { continuation = $0 }
        self.messageContinuation = continuation
    }
}

// MARK: - Transport Protocol
extension HTTPServerTransport {
    public func connect() async throws {
        guard !isConnected else { return }
        isConnected = true

        let router = buildRouter()
        let app = Application(
            router: router,
            configuration: .init(address: .hostname(host, port: port)),
            logger: logger
        )

        logger.info("HTTP server transport starting", metadata: ["host": "\(host)", "port": "\(port)", "path": "\(path)"])

        applicationTask = Task {
            try await app.runService()
        }
    }

    public func disconnect() async {
        guard isConnected else { return }
        isConnected = false
        isTerminated = true

        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: HTTPServerTransportError.transportDisconnected)
        }
        pendingRequests.removeAll()
        batchIdToPrimary.removeAll()

        sseContinuation?.finish()
        sseContinuation = nil

        applicationTask?.cancel()
        applicationTask = nil

        messageContinuation.finish()
        logger.debug("HTTP server transport disconnected")
    }

    public func send(_ data: Data) async throws {
        // Generate session ID on first response
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

    public func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        return messageStream
    }
}

// MARK: - Router Setup
private extension HTTPServerTransport {
    func buildRouter() -> Router<BasicRequestContext> {
        let router = Router(context: BasicRequestContext.self)
        let transport = self

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

// MARK: - Route Handlers
private extension HTTPServerTransport {
    func handlePost(request: Request, context: BasicRequestContext) async throws -> Response {
        guard !isTerminated else {
            return Response(status: .notFound)
        }

        // Validate Content-Type
        let contentType = request.headers[.contentType]
        guard contentType?.contains("application/json") == true else {
            return Response(status: .unsupportedMediaType)
        }

        // Validate session ID on subsequent requests
        if let existingSessionId = sessionId {
            let mcpSessionId = HTTPField.Name("Mcp-Session-Id")!
            if let requestSessionId = request.headers[mcpSessionId],
               requestSessionId != existingSessionId {
                return Response(status: .badRequest)
            }
        }

        // Collect body with size limit
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
            messageContinuation.yield(data)
            return buildResponse(status: .accepted)

        case .request(let id):
            return try await handleRequestMessage(id: id, data: data)

        case .batch(let requestIds):
            return try await handleBatchMessage(requestIds: requestIds, data: data)

        case .invalid:
            return Response(status: .badRequest)
        }
    }

    func handleGet(request: Request, context: BasicRequestContext) async throws -> Response {
        guard !isTerminated else {
            return Response(status: .notFound)
        }

        // Validate Accept header
        let accept = request.headers[.accept]
        guard accept?.contains("text/event-stream") == true else {
            return Response(status: .notAcceptable)
        }

        // Validate session ID
        if let existingSessionId = sessionId {
            let mcpSessionId = HTTPField.Name("Mcp-Session-Id")!
            if let requestSessionId = request.headers[mcpSessionId],
               requestSessionId != existingSessionId {
                return Response(status: .badRequest)
            }
        }

        // Create SSE stream
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
            // Merge data events with keepalive into a single stream
            let merged = AsyncStream<ByteBuffer> { mergedContinuation in
                // Data events task
                let dataTask = Task {
                    for await data in stream {
                        if Task.isCancelled { break }
                        let json = String(decoding: data, as: UTF8.self)
                        // Handle multi-line JSON by splitting on newlines
                        let lines = json.split(separator: "\n", omittingEmptySubsequences: false)
                        var sseMessage = lines.map { "data: \($0)" }.joined(separator: "\n")
                        sseMessage += "\n\n"
                        mergedContinuation.yield(ByteBuffer(string: sseMessage))
                    }
                    mergedContinuation.finish()
                }

                // Keepalive task
                let keepaliveTask = Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(30))
                        if Task.isCancelled { break }
                        mergedContinuation.yield(ByteBuffer(string: ": keepalive\n\n"))
                    }
                }

                // Clean up on termination
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
        // Validate session ID
        if let existingSessionId = sessionId {
            let mcpSessionId = HTTPField.Name("Mcp-Session-Id")!
            guard let requestSessionId = request.headers[mcpSessionId],
                  requestSessionId == existingSessionId else {
                return Response(status: .badRequest)
            }
        }

        isTerminated = true

        // Close SSE
        sseContinuation?.finish()
        sseContinuation = nil

        // Cancel pending requests
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: HTTPServerTransportError.sessionTerminated)
        }
        pendingRequests.removeAll()
        batchIdToPrimary.removeAll()

        return Response(status: .ok)
    }
}

// MARK: - Request Handling
private extension HTTPServerTransport {
    func handleRequestMessage(id: String, data: Data) async throws -> Response {
        messageContinuation.yield(data)

        // Schedule timeout that will resume continuation with error if not already resolved
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
        } catch is HTTPServerTransportError {
            timeoutTask.cancel()
            return Response(status: .requestTimeout)
        }

        return buildResponse(status: .ok, data: responseData)
    }

    func handleBatchMessage(requestIds: [String], data: Data) async throws -> Response {
        let primaryId = requestIds[0]
        for secondaryId in requestIds.dropFirst() {
            batchIdToPrimary[secondaryId] = primaryId
        }

        messageContinuation.yield(data)

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
        } catch is HTTPServerTransportError {
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
            continuation.resume(throwing: HTTPServerTransportError.requestTimeout)
        }
    }
}

// MARK: - Message Classification
extension HTTPServerTransport {
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
            if requestIds.isEmpty {
                return .notification
            }
            return .batch(requestIds: requestIds)
        }

        guard let dict = json as? [String: Any] else {
            return .invalid
        }

        if let id = dict["id"], dict["method"] != nil {
            return .request(id: stringifyId(id))
        }

        if dict["method"] != nil {
            return .notification
        }

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

        guard let dict = json as? [String: Any] else {
            return .notification
        }

        if let id = dict["id"] {
            if dict["result"] != nil || dict["error"] != nil {
                return .response(id: stringifyId(id))
            }
            if dict["method"] != nil {
                return .serverRequest
            }
        }

        if dict["method"] != nil {
            return .notification
        }

        return .notification
    }

    func stringifyId(_ id: Any) -> String {
        if let intId = id as? Int {
            return String(intId)
        }
        if let doubleId = id as? Double {
            return String(Int(doubleId))
        }
        if let strId = id as? String {
            return strId
        }
        return String(describing: id)
    }
}

// MARK: - Response Building
private extension HTTPServerTransport {
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

