//
//  ToolModuleAdapter.swift
//  MCPServerKit
//
//  Created by Nikolai Nobadi on 1/28/26.
//

import MCP

/// A concrete `ToolModule` that wraps a `ToolHandler`.
///
/// This adapter owns all MCP routing concerns:
/// - Resolves `params.name` to the handler's `Descriptor`
/// - Delegates execution to the wrapped handler
/// - Enforces error boundaries at the MCP layer
///
/// Clients implement `ToolHandler` for pure domain logic;
/// `ToolModuleAdapter` handles infrastructure.
struct ToolModuleAdapter<Handler: ToolHandler> {
    private let handler: Handler

    init(handler: Handler) {
        self.handler = handler
    }
}

// MARK: - ToolModule
extension ToolModuleAdapter: ToolModule {
    typealias ToolDescriptor = Handler.Descriptor

    func handle(_ params: CallTool.Parameters, authContext: AuthContext?) async throws -> CallTool.Result {
        let descriptor = resolveDescriptor(from: params)

        return try await handler.handle(descriptor, arguments: params.arguments, authContext: authContext)
    }
}

// MARK: - Private Methods
private extension ToolModuleAdapter {
    /// Resolves a tool call to its corresponding descriptor.
    ///
    /// - Parameter params: The tool call parameters from the MCP client.
    /// - Returns: The matching descriptor case.
    ///
    /// - Precondition: `ToolRegistrar` guarantees that this method is only called
    ///   with tool names owned by this module. A mismatch indicates a programmer error.
    func resolveDescriptor(from params: CallTool.Parameters) -> Handler.Descriptor {
        guard let descriptor = Handler.Descriptor(name: params.name) else {
            fatalError("ToolRegistrar routed unknown tool '\(params.name)' to \(Self.self)")
        }

        return descriptor
    }
}
