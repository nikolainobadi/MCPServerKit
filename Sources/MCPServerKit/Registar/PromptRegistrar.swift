import MCP

/// Central registrar responsible for MCP prompt wiring.
///
/// Registers a single `ListPrompts` handler and a single `GetPrompt` handler,
/// routing requests to the appropriate module based on prompt name.
enum PromptRegistrar {
    /// Registers all prompt modules on the server.
    ///
    /// - Parameters:
    ///   - modules: The prompt modules to register.
    ///   - server: The MCP server to register handlers on.
    ///
    /// - Precondition: All prompt names across modules must be unique.
    static func register(modules: [any PromptModule], on server: Server) async {
        let allPrompts = aggregatePrompts(from: modules)
        let router = buildRouter(from: modules)

        await server.withMethodHandler(ListPrompts.self) { _ in
            return ListPrompts.Result(prompts: allPrompts)
        }

        await server.withMethodHandler(GetPrompt.self) { params in
            guard let module = router[params.name] else {
                return GetPrompt.Result(description: nil, messages: [])
            }
            
            return module.getPrompt(name: params.name, arguments: params.arguments)
        }
    }
}

// MARK: - Private Methods
private extension PromptRegistrar {
    static func aggregatePrompts(from modules: [any PromptModule]) -> [Prompt] {
        return modules.flatMap { $0.prompts }
    }

    static func buildRouter(from modules: [any PromptModule]) -> [String: any PromptModule] {
        var router: [String: any PromptModule] = [:]

        for module in modules {
            for prompt in module.prompts {
                if let existing = router[prompt.name] {
                    preconditionFailure(
                        "Duplicate prompt name '\(prompt.name)' registered by \(type(of: existing)) and \(type(of: module))"
                    )
                }
                router[prompt.name] = module
            }
        }

        return router
    }
}
