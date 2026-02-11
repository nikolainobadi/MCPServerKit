//
//  LocalMCPServer.swift
//  Felix
//
//  Created by Nikolai Nobadi on 1/26/26.
//

import MCP
import Logging
import ServiceLifecycle

/// Assembles and prepares a local MCP server with tools, resources, and prompts.
/// This type owns MCP wiring only. Execution strategy, transport choice,
/// and lifecycle management are delegated to the client.
public final class LocalMCPServer {
    private let server: Server
    private let features: [FeatureModule]

    public init(name: String, version: String, instructions: String? = nil, strictConfig: Bool = false, features: [FeatureModule]) {
        self.features = features
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
    }
}


// MARK: - Start
public extension LocalMCPServer {
    func start() async throws {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = .info
            return handler
        }
        
        let logger = Logger(label: "com.nobadi.Felix")
        let transport = StdioTransport(logger: logger)
        
        await ToolRegistrar.register(modules: features.flatMap(\.tools), on: server)
        await ResourceRegistrar.register(modules: features.flatMap(\.resources), on: server)
        await PromptRegistrar.register(modules: features.flatMap(\.prompts), on: server)
        
        let mcpService = MCPLifecycleService(server: server, transport: transport)
        let serviceConfig = ServiceGroupConfiguration.ServiceConfiguration(
            service: mcpService,
            successTerminationBehavior: .gracefullyShutdownGroup,
            failureTerminationBehavior: .gracefullyShutdownGroup
        )
        
        let groupConfig = ServiceGroupConfiguration(services: [serviceConfig], gracefulShutdownSignals: [.sigint, .sigterm], cancellationSignals: [], logger: logger)
        let group = ServiceGroup(configuration: groupConfig)

        try await group.run()
    }
}
