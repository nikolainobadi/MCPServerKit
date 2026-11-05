import MCP
import Logging
import ServiceLifecycle

/// Assembles and prepares a local MCP server with tools, resources, and prompts.
/// This type owns MCP wiring only. Execution strategy, transport choice,
/// and lifecycle management are delegated to the client.
public final class LocalMCPServer {
    private let name: String
    private let server: Server
    private let features: [FeatureModule]

    /// Creates a local MCP server configured with the given features.
    ///
    /// - Parameters:
    ///   - name: A human-readable server name, also used as the logger label.
    ///   - version: The server version string advertised to MCP clients.
    ///   - instructions: Optional instructions surfaced to MCP clients.
    ///   - strictConfig: When `true`, uses strict MCP configuration; defaults to permissive.
    ///   - features: The feature modules providing tools, resources, and prompts.
    public init(name: String, version: String, instructions: String? = nil, strictConfig: Bool = false, features: [FeatureModule]) {
        self.name = name
        self.features = features
        self.server = .init(
            name: name,
            version: version,
            instructions: instructions,
            capabilities: .init(
                logging: .init(),
                prompts: .init(listChanged: true),
                resources: .init(listChanged: true),
                tools: .init(listChanged: true)
            ),
            configuration: strictConfig ? .strict : .default
        )
    }
}


// MARK: - Start
public extension LocalMCPServer {
    /// Bootstraps logging, registers all features, and runs the server until termination.
    ///
    /// This method blocks until the server receives `SIGINT` or `SIGTERM`.
    ///
    /// - Throws: Rethrows any error from the underlying service group.
    func start() async throws {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = .info
            return handler
        }
        
        let logger = Logger(label: name)
        let transport = InitializeSanitizingTransport(base: StdioTransport(logger: logger), logger: logger)
        
        await ToolRegistrar.register(modules: features.flatMap(\.tools), on: server, logger: logger)
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
