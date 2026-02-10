//
//  AuthContext.swift
//  MCPServerKit
//
//  Created by Nikolai Nobadi on 2/10/26.
//

/// Authenticated user identity extracted from a validated JWT.
///
/// Lightweight value type with no external dependencies.
/// Passed to `ToolHandler.handle` when the server is configured with OAuth.
/// `nil` for `LocalMCPServer` and unauthenticated `RemoteMCPServer`.
public struct AuthContext: Sendable {
    /// JWT "sub" claim — the authenticated user's unique identifier.
    public let subject: String

    /// JWT "iss" claim — the authorization server that issued the token.
    public let issuer: String

    /// Granted OAuth scopes from the access token.
    public let scopes: Set<String>

    /// Additional claims extracted from the JWT (e.g. email, name).
    public let claims: [String: String]

    /// The original Bearer token, available for downstream API calls.
    public let rawToken: String

    public init(
        subject: String,
        issuer: String,
        scopes: Set<String> = [],
        claims: [String: String] = [:],
        rawToken: String
    ) {
        self.subject = subject
        self.issuer = issuer
        self.scopes = scopes
        self.claims = claims
        self.rawToken = rawToken
    }
}
