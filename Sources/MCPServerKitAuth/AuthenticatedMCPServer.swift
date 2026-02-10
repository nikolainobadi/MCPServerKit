//
//  AuthenticatedMCPServer.swift
//  MCPServerKitAuth
//
//  Created by Nikolai Nobadi on 2/10/26.
//

import MCP
import Logging
import ServiceLifecycle
import MCPServerKit

/// MCP server with OAuth 2.1 JWT validation.
///
/// Drop-in replacement for `RemoteMCPServer` that adds:
/// - `OAuthMiddleware` on `/mcp` routes (validates Bearer tokens)
/// - `/.well-known/oauth-protected-resource` discovery endpoint
/// - Per-request `AuthContext` threaded to tool handlers
///
/// ```swift
/// let server = AuthenticatedMCPServer(
///     name: "iGetGroceries",
///     version: "1.0.0",
///     features: [groceryFeature],
///     oauthConfig: oauthConfig,
///     port: 8080
/// )
/// try await server.start()
/// ```
public final class AuthenticatedMCPServer {
    private let server: Server
    private let features: [FeatureModule]
    private let oauthConfig: OAuthConfiguration
    private let authContextHolder: AuthContextHolder
    private let jwksClient: JWKSClient
    private let host: String
    private let port: Int
    private let path: String

    public init(
        name: String,
        version: String,
        instructions: String? = nil,
        strictConfig: Bool = false,
        features: [FeatureModule],
        oauthConfig: OAuthConfiguration,
        host: String = "0.0.0.0",
        port: Int = 8000,
        path: String = "/mcp"
    ) {
        self.server = .init(
            name: name,
            version: version,
            instructions: instructions,
            capabilities: .init(
                logging: .init(),
                prompts: .init(listChanged: true),
                resources: .init(listChanged: true),
                sampling: .init(),
                tools: .init(listChanged: true)
            ),
            configuration: strictConfig ? .strict : .default
        )
        self.features = features
        self.oauthConfig = oauthConfig
        self.authContextHolder = AuthContextHolder()
        self.jwksClient = JWKSClient(
            jwksURL: oauthConfig.jwksURL,
            cacheTTL: oauthConfig.jwksCacheTTL
        )
        self.host = host
        self.port = port
        self.path = path
    }
}

// MARK: - Start
public extension AuthenticatedMCPServer {
    func start() async throws {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = .info
            return handler
        }

        let logger = Logger(label: "com.nobadi.MCPServerKit.authenticated")

        let transport = AuthenticatedHTTPTransport(
            config: oauthConfig,
            jwksClient: jwksClient,
            authContextHolder: authContextHolder,
            host: host,
            port: port,
            path: path,
            logger: logger
        )

        // Register features with auth context holder so tool handlers receive AuthContext
        await ToolRegistrar.register(
            modules: features.flatMap(\.tools),
            on: server,
            authContextHolder: authContextHolder
        )
        await ResourceRegistrar.register(modules: features.flatMap(\.resources), on: server)
        await PromptRegistrar.register(modules: features.flatMap(\.prompts), on: server)

        let mcpService = MCPLifecycleService(server: server, transport: transport)
        let serviceConfig = ServiceGroupConfiguration.ServiceConfiguration(
            service: mcpService,
            successTerminationBehavior: .gracefullyShutdownGroup,
            failureTerminationBehavior: .gracefullyShutdownGroup
        )
        let groupConfig = ServiceGroupConfiguration(
            services: [serviceConfig],
            gracefulShutdownSignals: [.sigint, .sigterm],
            cancellationSignals: [],
            logger: logger
        )
        let group = ServiceGroup(configuration: groupConfig)

        try await group.run()
    }
}
