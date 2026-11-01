import MCP

/// A protocol representing enum-based MCP prompt metadata.
///
/// Conforming enums describe the prompts they represent without defining execution logic.
/// Prompt registration and retrieval are handled separately by `PromptModule` and `PromptRegistrar`.
///
/// - Note: Conforming types must be `CaseIterable` to support automatic prompt enumeration
///   and `Sendable` for concurrency safety.
public protocol MCPPromptDescriptor: CaseIterable, Sendable {
    /// The MCP prompt name used for routing.
    var name: String { get }

    /// A human-readable description of the prompt's purpose.
    var description: String { get }

    /// The arguments accepted by this prompt.
    var arguments: [Prompt.Argument] { get }
}

// MARK: - Default Implementations
public extension MCPPromptDescriptor {
    /// Constructs an MCP `Prompt` from this descriptor's metadata.
    var prompt: Prompt {
        return .init(name: name, description: description, arguments: arguments)
    }

    /// Initializes a descriptor by looking up a prompt name among all cases.
    ///
    /// - Parameter name: The prompt name to match.
    /// - Returns: The matching case, or `nil` if no case has that name.
    init?(name: String) {
        guard let match = Self.allCases.first(where: { $0.name == name }) else {
            return nil
        }
        
        self = match
    }
}
