//
//  RemoteMCPServer.swift
//  MCPServerKit
//
//  Created by Nikolai Nobadi on 2/10/26.
//

import MCP
import Logging
import ServiceLifecycle

/// Assembles and prepares a remote MCP server with tools, resources, and prompts.
/// Uses HTTP transport (Streamable HTTP) instead of stdio, enabling remote deployment.
/// Drop-in replacement for `LocalMCPServer` — same init signature plus host/port/path.
public final class RemoteMCPServer {
    private let server: Server
    private let features: [FeatureModule]
    private let host: String
    private let port: Int
    private let path: String

    public init(
        name: String,
        version: String,
        instructions: String? = nil,
        strictConfig: Bool = false,
        features: [FeatureModule],
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
        self.host = host
        self.port = port
        self.path = path
    }
}

// MARK: - Start
public extension RemoteMCPServer {
    func start() async throws {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = .info
            return handler
        }

        let logger = Logger(label: "com.nobadi.MCPServerKit.remote")
        let transport = HTTPServerTransport(host: host, port: port, path: path, logger: logger)

        await ToolRegistrar.register(modules: features.flatMap(\.tools), on: server)
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
