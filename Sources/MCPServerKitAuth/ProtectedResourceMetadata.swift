//
//  ProtectedResourceMetadata.swift
//  MCPServerKitAuth
//
//  Created by Nikolai Nobadi on 2/10/26.
//

/// RFC 9728 Protected Resource Metadata.
///
/// Served at `GET /.well-known/oauth-protected-resource{/path}` to tell
/// MCP clients (Claude, ChatGPT) where to authenticate.
public struct ProtectedResourceMetadata: Codable, Sendable {
    /// The protected resource's identifier (e.g. "https://mcp.example.com/mcp").
    public let resource: String

    /// Issuer identifiers of compatible authorization servers
    /// (e.g. ["https://tenant.us.auth0.com"]).
    public let authorizationServers: [String]

    /// Scope values the resource server understands.
    public let scopesSupported: [String]?

    /// Token delivery methods supported. Default: ["header"].
    public let bearerMethodsSupported: [String]?

    /// Human-readable name for the resource.
    public let resourceName: String?

    /// URL to developer documentation.
    public let resourceDocumentation: String?

    public init(
        resource: String,
        authorizationServers: [String],
        scopesSupported: [String]? = nil,
        bearerMethodsSupported: [String]? = ["header"],
        resourceName: String? = nil,
        resourceDocumentation: String? = nil
    ) {
        self.resource = resource
        self.authorizationServers = authorizationServers
        self.scopesSupported = scopesSupported
        self.bearerMethodsSupported = bearerMethodsSupported
        self.resourceName = resourceName
        self.resourceDocumentation = resourceDocumentation
    }

    enum CodingKeys: String, CodingKey {
        case resource
        case authorizationServers = "authorization_servers"
        case scopesSupported = "scopes_supported"
        case bearerMethodsSupported = "bearer_methods_supported"
        case resourceName = "resource_name"
        case resourceDocumentation = "resource_documentation"
    }
}
