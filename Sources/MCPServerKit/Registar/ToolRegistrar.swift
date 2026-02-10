//
//  ToolRegistrar.swift
//  MCPServerKit
//
//  Created by Nikolai Nobadi on 1/25/26.
//

import MCP
import Foundation

/// Central registrar responsible for MCP tool wiring.
///
/// Registers a single `ListTools` handler and a single `CallTool` handler,
/// routing calls to the appropriate module based on tool name.
public enum ToolRegistrar {
    /// Registers all tool modules on the server.
    ///
    /// - Parameters:
    ///   - modules: The tool modules to register.
    ///   - server: The MCP server to register handlers on.
    ///   - authContextHolder: Optional holder providing per-request auth context.
    ///     When provided, the current auth context is read and forwarded to tool handlers.
    ///
    /// - Precondition: All tool names across modules must be unique.
    public static func register(modules: [any ToolModule], on server: Server, authContextHolder: AuthContextHolder? = nil) async {
        let allTools = aggregateTools(from: modules)
        let router = buildRouter(from: modules)

        await server.withMethodHandler(ListTools.self) { _ in
            return ListTools.Result(tools: allTools)
        }

        await server.withMethodHandler(CallTool.self) { params in
            guard let module = router[params.name] else {
                return unknownToolError(toolName: params.name)
            }

            let authContext = authContextHolder?.current

            do {
                return try await module.handle(params, authContext: authContext)
            } catch let error as ToolErrorConvertible {
                return errorResult(from: error, toolName: params.name)
            } catch {
                // TODO: - maybe return an actual error result?
                fatalError("Unhandled error escaped tool '\(params.name)': \(error)")
            }
        }
    }
}

// MARK: - Internal (Testable)
extension ToolRegistrar {
    static func unknownToolError(toolName: String) -> CallTool.Result {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = ToolManagerErrorPayload(
            code: "tool.unknown",
            message: "Unknown tool: \(toolName)",
            details: ["tool": toolName]
        )
        let text = (try? String(decoding: encoder.encode(payload), as: UTF8.self))
            ?? "{\"code\":\"tool.unknown\",\"message\":\"Unknown tool\"}"
        return .init(content: [.text(text)], isError: true)
    }

    static func errorResult(from error: ToolErrorConvertible, toolName: String) -> CallTool.Result {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = error.toErrorPayload(toolName: toolName)
        let text = (try? String(decoding: encoder.encode(payload), as: UTF8.self))
            ?? "{\"code\":\"internal.serialization\",\"message\":\"Failed to encode error payload\"}"
        return .init(content: [.text(text)], isError: true)
    }
}

// MARK: - Private Methods
private extension ToolRegistrar {
    static func aggregateTools(from modules: [any ToolModule]) -> [Tool] {
        return modules.flatMap({ $0.tools })
    }

    static func buildRouter(from modules: [any ToolModule]) -> [String: any ToolModule] {
        var router: [String: any ToolModule] = [:]

        for module in modules {
            for tool in module.tools {
                if let existing = router[tool.name] {
                    preconditionFailure(
                        "Duplicate tool name '\(tool.name)' registered by \(type(of: existing)) and \(type(of: module))"
                    )
                }
                router[tool.name] = module
            }
        }

        return router
    }
}
