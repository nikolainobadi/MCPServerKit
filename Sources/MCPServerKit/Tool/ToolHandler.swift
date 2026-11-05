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
    /// - Throws: A `ToolErrorConvertible` error if execution fails. Other errors reach the client
    ///   with the generic code `internal.unhandled`.
    func handle(_ descriptor: Descriptor, arguments: [String: Value]?) async throws -> CallTool.Result
}
