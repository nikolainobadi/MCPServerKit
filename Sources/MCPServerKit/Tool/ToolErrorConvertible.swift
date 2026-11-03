/// A protocol for errors that can convert themselves into structured MCP error payloads.
///
/// Errors that escape a tool boundary should conform to this protocol.
/// This enforces explicit error semantics and centralizes error-to-payload mapping
/// at the source rather than at the MCP boundary. Other errors reach the client
/// with the generic code `internal.unhandled`, except `CancellationError` and `MCPError`,
/// which the SDK handles.
public protocol ToolErrorConvertible: Error {
    /// Converts the error into a structured payload for MCP error responses.
    ///
    /// - Parameter toolName: The name of the tool that threw the error.
    /// - Returns: A payload suitable for serialization in an MCP error response.
    func toErrorPayload(toolName: String) -> ToolManagerErrorPayload
}
