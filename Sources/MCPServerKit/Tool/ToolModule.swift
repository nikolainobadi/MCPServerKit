import MCP

/// A protocol representing a logical group of MCP tools.
///
/// This protocol is an internal infrastructure concern. Client code should
/// conform to `ToolHandler` instead and use `ToolModuleAdapter` for registration.
///
/// Tool registration and cross-tool routing are handled by `ToolRegistrar`.
public protocol ToolModule: Sendable {
    /// The enum type describing the tools owned by this module.
    associatedtype ToolDescriptor: MCPToolDescriptor

    /// The tools owned by this module.
    var tools: [Tool] { get }

    /// Handles execution for a tool call.
    ///
    /// This method is only invoked when `ToolRegistrar` has determined that
    /// this module owns the requested tool based on declared tool names.
    ///
    /// - Parameter params: The tool call parameters from the MCP client.
    /// - Returns: The result of the tool execution.
    /// - Throws: A `ToolErrorConvertible` error if execution fails.
    func handle(_ params: CallTool.Parameters) async throws -> CallTool.Result
}

// MARK: - Default Implementations
public extension ToolModule {
    /// The tools owned by this module, derived from `Descriptor.allCases`.
    var tools: [Tool] {
        return ToolDescriptor.allCases.map(\.tool)
    }
}
