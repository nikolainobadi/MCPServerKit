import MCP

/// Central registrar responsible for MCP resource wiring.
///
/// Registers a single `ListResources` handler and a single `ReadResource` handler,
/// routing reads to the appropriate module based on resource URI.
enum ResourceRegistrar {
    /// Registers all resource modules on the server.
    ///
    /// - Parameters:
    ///   - modules: The resource modules to register.
    ///   - server: The MCP server to register handlers on.
    ///
    /// - Precondition: All resource URIs across modules must be unique.
    static func register(modules: [any ResourceModule], on server: Server) async {
        let allResources = aggregateResources(from: modules)
        let router = buildRouter(from: modules)

        await server.withMethodHandler(ListResources.self) { _ in
            return ListResources.Result(resources: allResources)
        }

        await server.withMethodHandler(ReadResource.self) { params in
            guard let module = router[params.uri] else {
                return ReadResource.Result(contents: [])
            }
            return ReadResource.Result(contents: module.readContent(for: params.uri))
        }
    }
}

// MARK: - Private Methods
private extension ResourceRegistrar {
    static func aggregateResources(from modules: [any ResourceModule]) -> [Resource] {
        return modules.flatMap { $0.resources }
    }

    static func buildRouter(from modules: [any ResourceModule]) -> [String: any ResourceModule] {
        var router: [String: any ResourceModule] = [:]

        for module in modules {
            for resource in module.resources {
                if let existing = router[resource.uri] {
                    preconditionFailure(
                        "Duplicate resource URI '\(resource.uri)' registered by \(type(of: existing)) and \(type(of: module))"
                    )
                }
                router[resource.uri] = module
            }
        }

        return router
    }
}
