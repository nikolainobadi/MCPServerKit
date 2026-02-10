//
//  OAuthMiddleware.swift
//  MCPServerKitAuth
//
//  Created by Nikolai Nobadi on 2/10/26.
//

import Foundation
import Hummingbird
import HTTPTypes
import JWTKit
import MCPServerKit

/// Hummingbird middleware that validates OAuth 2.1 Bearer tokens on MCP routes.
///
/// On valid tokens: builds an `AuthContext` and stores it in the `AuthContextHolder`.
/// On missing/invalid tokens: returns 401 with `WWW-Authenticate` header.
/// On insufficient scopes: returns 403 with `insufficient_scope` error.
public struct OAuthMiddleware<Context: RequestContext>: RouterMiddleware {
    private let config: OAuthConfiguration
    private let jwksClient: JWKSClient
    private let authContextHolder: AuthContextHolder

    public init(
        config: OAuthConfiguration,
        jwksClient: JWKSClient,
        authContextHolder: AuthContextHolder
    ) {
        self.config = config
        self.jwksClient = jwksClient
        self.authContextHolder = authContextHolder
    }

    public func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        // 1. Extract Bearer token
        guard let authHeader = request.headers[.authorization],
              authHeader.lowercased().hasPrefix("bearer "),
              authHeader.count > 7 else {
            return unauthorizedResponse()
        }

        let token = String(authHeader.dropFirst(7))

        // 2. Validate JWT
        let authContext: AuthContext
        do {
            authContext = try await validateToken(token)
        } catch {
            return unauthorizedResponse()
        }

        // 3. Check required scopes
        if let requiredScopes = config.requiredScopes {
            guard requiredScopes.isSubset(of: authContext.scopes) else {
                return forbiddenResponse(requiredScopes: requiredScopes)
            }
        }

        // 4. Store auth context for tool handlers to read
        authContextHolder.current = authContext

        // 5. Continue to next handler
        let response = try await next(request, context)

        return response
    }
}

// MARK: - Token Validation
private extension OAuthMiddleware {
    func validateToken(_ token: String) async throws -> AuthContext {
        let keys = try await jwksClient.getKeys()
        let keyCollection = JWTKeyCollection()
        try await keyCollection.add(jwks: keys)

        let payload: MCPTokenPayload
        do {
            payload = try await keyCollection.verify(token, as: MCPTokenPayload.self)
        } catch {
            // Key might have rotated — refresh and retry once
            let refreshedKeys = try await jwksClient.refreshKeys()
            let refreshedCollection = JWTKeyCollection()
            try await refreshedCollection.add(jwks: refreshedKeys)
            payload = try await refreshedCollection.verify(token, as: MCPTokenPayload.self)
        }

        // Validate issuer
        guard payload.issuer?.value == config.expectedIssuer else {
            throw OAuthError.invalidIssuer
        }

        // Validate audience
        guard payload.audience?.value.contains(config.expectedAudience) == true else {
            throw OAuthError.invalidAudience
        }

        // Validate expiration
        guard let expiration = payload.expiration, expiration.value > Date() else {
            throw OAuthError.tokenExpired
        }

        // Extract scopes
        let scopes: Set<String>
        if let scopeString = payload.scope {
            scopes = Set(scopeString.split(separator: " ").map(String.init))
        } else {
            scopes = []
        }

        // Extract additional claims
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

// MARK: - Response Builders
private extension OAuthMiddleware {
    func unauthorizedResponse() -> Response {
        let resourceURL = config.metadata.resource
        var headers = HTTPFields()
        let wwwAuth = "Bearer resource_metadata=\"\(resourceURL)\""
        headers[.wwwAuthenticate] = wwwAuth
        return Response(status: .unauthorized, headers: headers)
    }

    func forbiddenResponse(requiredScopes: Set<String>) -> Response {
        var headers = HTTPFields()
        let scopeList = requiredScopes.sorted().joined(separator: " ")
        headers[.wwwAuthenticate] = "Bearer error=\"insufficient_scope\", scope=\"\(scopeList)\""
        return Response(status: .forbidden, headers: headers)
    }
}

// MARK: - JWT Payload
struct MCPTokenPayload: JWTPayload {
    var issuer: IssuerClaim?
    var subject: SubjectClaim?
    var audience: AudienceClaim?
    var expiration: ExpirationClaim?
    var scope: String?
    var email: String?
    var name: String?

    enum CodingKeys: String, CodingKey {
        case issuer = "iss"
        case subject = "sub"
        case audience = "aud"
        case expiration = "exp"
        case scope
        case email
        case name
    }

    func verify(using algorithm: some JWTAlgorithm) async throws {
        if let expiration {
            try expiration.verifyNotExpired()
        }
    }
}

// MARK: - Errors
public enum OAuthError: Error, Sendable {
    case invalidIssuer
    case invalidAudience
    case tokenExpired
    case invalidToken
}
