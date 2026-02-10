//
//  OAuthConfiguration.swift
//  MCPServerKitAuth
//
//  Created by Nikolai Nobadi on 2/10/26.
//

import Foundation

/// Server-side OAuth configuration for the MCP resource server.
///
/// Specifies the external authorization server details needed to validate
/// incoming JWT Bearer tokens and serve Protected Resource Metadata.
public struct OAuthConfiguration: Sendable {
    /// RFC 9728 metadata served at `/.well-known/oauth-protected-resource`.
    public let metadata: ProtectedResourceMetadata

    /// The authorization server's JWKS endpoint for fetching signing keys.
    public let jwksURL: URL

    /// Expected `iss` claim in validated JWTs.
    public let expectedIssuer: String

    /// Expected `aud` claim in validated JWTs.
    public let expectedAudience: String

    /// Minimum scopes required for all MCP requests. `nil` means no global requirement.
    public let requiredScopes: Set<String>?

    /// How long to cache JWKS keys before re-fetching. Default: 1 hour.
    public let jwksCacheTTL: Duration

    public init(
        metadata: ProtectedResourceMetadata,
        jwksURL: URL,
        expectedIssuer: String,
        expectedAudience: String,
        requiredScopes: Set<String>? = nil,
        jwksCacheTTL: Duration = .seconds(3600)
    ) {
        self.metadata = metadata
        self.jwksURL = jwksURL
        self.expectedIssuer = expectedIssuer
        self.expectedAudience = expectedAudience
        self.requiredScopes = requiredScopes
        self.jwksCacheTTL = jwksCacheTTL
    }
}
