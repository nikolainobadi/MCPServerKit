//
//  ToolHandler.swift
//  MCPServerKit
//
//  Created by Nikolai Nobadi on 1/28/26.
//

import MCP

/// A protocol representing pure domain execution for MCP tools.
///
/// Conforming types handle tool invocations by switching on their own
/// domain-defined descriptor enum. All MCP routing and resolution is
/// handled externally by `ToolModuleAdapter`.
///
/// The associated `Descriptor` enum describes the tools this handler owns.
/// Handlers receive a pre-resolved descriptor and raw arguments.
public protocol ToolHandler: ToolHandlerHelpers {
    /// The enum type describing the tools handled by this type.
    associatedtype Descriptor: MCPToolDescriptor

    /// Handles execution for a resolved tool descriptor.
    ///
    /// - Parameters:
    ///   - descriptor: The resolved tool descriptor indicating which tool to execute.
    ///   - arguments: The raw arguments from the MCP client, if any.
    /// - Returns: The result of the tool execution.
    /// - Throws: A `ToolErrorConvertible` error if execution fails.
    func handle(_ descriptor: Descriptor, arguments: [String: Value]?) async throws -> CallTool.Result

    /// Handles execution for a resolved tool descriptor with optional auth context.
    ///
    /// Override this method instead of `handle(_:arguments:)` when your handler
    /// needs access to the authenticated user's identity (e.g. for per-user data).
    ///
    /// - Parameters:
    ///   - descriptor: The resolved tool descriptor indicating which tool to execute.
    ///   - arguments: The raw arguments from the MCP client, if any.
    ///   - authContext: The authenticated user context, or `nil` for unauthenticated servers.
    /// - Returns: The result of the tool execution.
    /// - Throws: A `ToolErrorConvertible` error if execution fails.
    func handle(_ descriptor: Descriptor, arguments: [String: Value]?, authContext: AuthContext?) async throws -> CallTool.Result
}

// MARK: - Default Implementation
public extension ToolHandler {
    /// Default: delegates to the non-auth version, ignoring `authContext`.
    /// Existing handlers that don't need auth context remain source-compatible.
    func handle(_ descriptor: Descriptor, arguments: [String: Value]?, authContext: AuthContext?) async throws -> CallTool.Result {
        return try await handle(descriptor, arguments: arguments)
    }
}
