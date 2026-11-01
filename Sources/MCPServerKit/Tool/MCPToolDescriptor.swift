import MCP

/// A protocol representing enum-based MCP tool metadata.
///
/// Conforming enums describe the tools they represent without defining execution logic.
/// Tool registration and execution are handled separately by `ToolModule` and `ToolRegistrar`.
///
/// - Note: Conforming types must be `CaseIterable` to support automatic tool enumeration
///   and `Sendable` for concurrency safety.
public protocol MCPToolDescriptor: CaseIterable, Sendable {
    /// The MCP tool name used for routing.
    var name: String { get }

    /// A human-readable description of the tool's purpose.
    var description: String? { get }

    /// The JSON schema describing the tool's input parameters.
    var inputSchema: Value { get }

    /// MCP tool annotations (hints about behavior).
    var annotations: Tool.Annotations { get }
}

// MARK: - Default Implementations
extension MCPToolDescriptor {
    /// Constructs an MCP `Tool` from this descriptor's metadata.
    var tool: Tool {
        return .init(name: name, description: description, inputSchema: inputSchema, annotations: annotations)
    }

    /// Initializes a descriptor by looking up a tool name among all cases.
    ///
    /// - Parameter name: The tool name to match.
    /// - Returns: The matching case, or `nil` if no case has that name.
    init?(name: String) {
        guard let match = Self.allCases.first(where: { $0.name == name }) else {
            return nil
        }
        self = match
    }
}
