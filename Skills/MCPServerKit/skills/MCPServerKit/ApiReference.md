# MCPServerKit API Reference

## LocalMCPServer

```swift
public final class LocalMCPServer {
    public init(name: String, version: String, instructions: String? = nil, strictConfig: Bool = false, features: [FeatureModule])
    public func start() async throws
}
```

`start()` serves over stdio and blocks until the process receives `SIGINT` or `SIGTERM`, then shuts down gracefully.

## FeatureModule

```swift
public struct FeatureModule {
    public let capabilities: [FeatureCapability]
    public init(capabilities: [FeatureCapability])
}
```

## FeatureCapability

```swift
public struct FeatureCapability {
    public init<Handler: ToolHandler>(handler: Handler, resources: [any ResourceModule] = [], prompts: [any PromptModule] = [])
}
```

## MCPToolDescriptor

Enum protocol. Each case represents a tool.

```swift
public protocol MCPToolDescriptor: CaseIterable, Sendable {
    var name: String { get }
    var description: String? { get }
    var inputSchema: Value { get }
    var annotations: Tool.Annotations { get }
}
```

MCPServerKit builds the MCP `Tool` and resolves tool names from these cases internally; conformers implement only the four properties.

## ToolHandler

```swift
public protocol ToolHandler: ToolHandlerHelpers {
    associatedtype Descriptor: MCPToolDescriptor
    func handle(_ descriptor: Descriptor, arguments: [String: Value]?) async throws -> CallTool.Result
}
```

## ToolHandlerHelpers

Available on all `ToolHandler` conformers:

```swift
func requireString(_ arguments: [String: Value]?, key: String) throws -> String
func optionalString(_ arguments: [String: Value]?, key: String) -> String?
func requireBool(_ arguments: [String: Value]?, key: String) throws -> Bool
func intValue(from value: Value?) -> Int?
func decodeArguments<T: Decodable>(_ type: T.Type, from arguments: [String: Value]?) throws -> T
func encodePayload<T: Encodable>(_ payload: T, formatting: PayloadFormatting = .compact) -> String
```

`PayloadFormatting`: `.compact` or `.prettyPrinted`. Both sort JSON keys. Encoding failure returns `{"message":"Failed to encode payload"}` rather than throwing or setting a tool result's `isError` flag.

`decodeArguments` treats `nil` as an empty object and wraps decoding failures in `ToolArgumentError.decodingError`. It uses `Decodable`; it does not validate against `inputSchema`. Enforce constraints such as numeric bounds in your argument type or domain layer.

## Content Constructors (swift-sdk 0.12)

The short forms are deprecated or removed in the MCP SDK; use these:

```swift
Tool.Content.text(text: String, annotations: Resource.Annotations?, _meta: Metadata?)   // tool results
Resource.Content.text(_ content: String, uri: String, mimeType: String?)                // resource reads
Prompt.Message.user(.text(text: String))                                              // prompt messages
```

## Schema API

### Schema.object

Builds a JSON Schema object from properties with required/optional markers:

```swift
Schema.object([
    "name": .required(.string(description: "The user's name")),
    "age": .optional(.int(description: "Age in years", minimum: 0, maximum: 150)),
    "active": .required(.bool(description: "Whether active"))
])
```

### Schema.Field

```swift
public indirect enum Field {
    case object([String: RequiredSchema])
    case bool(description: String? = nil)
    case string(description: String? = nil, nullable: Bool = false)
    case int(description: String? = nil, minimum: Int? = nil, maximum: Int? = nil, nullable: Bool = false)
    case double(description: String? = nil, minimum: Double? = nil, maximum: Double? = nil, nullable: Bool = false)
    case array(of: Field, description: String? = nil)
}
```

### Schema.RequiredSchema

```swift
public enum RequiredSchema {
    case required(Field)
    case optional(Field)
}
```

### SchemaDerivable / SchemaObjectDerivable

```swift
public protocol SchemaDerivable {
    static func schema() -> Value
}

public protocol SchemaObjectDerivable {
    static func objectSchema() -> Schema.Field
}
```

Conform to `SchemaDerivable` on argument structs and implement `static func schema() -> Value` explicitly; conformance does not synthesize a schema from stored properties. Use the result as `inputSchema`. `SchemaObjectDerivable` likewise requires an explicit `objectSchema()` implementation.

For a tool with no arguments, use `Schema.object([:])` to include `type: "object"` and an empty `properties` map. `Schema.RequiredSchema` is nested under `Schema`; `.required` and `.optional` can be inferred in the dictionary passed to `Schema.object`.

## MCPResourceDescriptor

Enum protocol. Each case represents a resource.

```swift
public protocol MCPResourceDescriptor: CaseIterable, Sendable {
    var uri: String { get }
    var name: String { get }
    var description: String { get }
    var mimeType: String { get }
}
```

Default implementations: `resource` property, `toolResultContent` property, `init?(uri:)` lookup. `toolResultContent` embeds a resource with empty text, the URI, and MIME type; it does not load the resource's content. Use the registered `ResourceModule` to serve content for that URI.

## ResourceModule

```swift
public protocol ResourceModule: Sendable {
    associatedtype ResourceDescriptor: MCPResourceDescriptor
    var resources: [Resource] { get }  // default: derived from ResourceDescriptor.allCases
    func read(_ resource: ResourceDescriptor) -> [Resource.Content]
    func readContent(for uri: String) -> [Resource.Content]  // default: resolves URI then calls read(_:)
}
```

Only `read(_:)` needs implementation. The default `readContent(for:)` and `resolveResource(from:)` require a URI owned by the module and call `fatalError` for an unknown URI. For untrusted input, first use the failable descriptor `init?(uri:)` and then call `read(_:)`.

## MCPPromptDescriptor

Enum protocol. Each case represents a prompt.

```swift
public protocol MCPPromptDescriptor: CaseIterable, Sendable {
    var name: String { get }
    var description: String { get }
    var arguments: [Prompt.Argument] { get }
}
```

Default implementations: `prompt` property, `init?(name:)` lookup.

## PromptModule

```swift
public protocol PromptModule: Sendable {
    associatedtype PromptType: MCPPromptDescriptor
    var prompts: [Prompt] { get }  // default: derived from PromptType.allCases
    func prompt(_ prompt: PromptType, arguments: [String: String]?) -> GetPrompt.Result
    func getPrompt(name: String, arguments: [String: String]?) -> GetPrompt.Result  // default: resolves name then calls prompt(_:arguments:)
}
```

Only `prompt(_:arguments:)` needs implementation. The default `getPrompt(name:arguments:)` and `resolvePrompt(from:)` require a name owned by the module and call `fatalError` for an unknown name. For untrusted input, first use the failable descriptor `init?(name:)`. Prompt arguments arrive as plain strings, matching the MCP SDK's `GetPrompt.Parameters`. Build messages with `.user(.text(text:))` / `.assistant(.text(text:))`.

## Error Handling

### ToolError

String-backed enum protocol with automatic error code generation:

```swift
public protocol ToolError: Error, ToolErrorConvertible, ToolErrorDomain, RawRepresentable where RawValue == String {
    var messageOverride: String? { get }  // default: nil
}

public protocol ToolErrorDomain {
    static var domain: String { get }
}
```

Enum cases are auto-converted to snake_case error codes prefixed with the domain: `case readFailed` → `"profile.read_failed"`.

### withDetails

Add runtime context to errors:

```swift
func withDetails(_ details: [String: String], message: String? = nil) -> ContextualDomainError<Self>
```

### ToolErrorConvertible

Errors escaping a tool boundary should conform. The registrar converts them to JSON text containing `code`, `message`, and optional `details`, with `isError: true`. Translate errors from dependencies before they escape the handler: any other error is logged and returned the same way with the generic code `internal.unhandled`, and its description as the message. `CancellationError` and `MCPError` are rethrown to the SDK, so a cancelled request gets no response and an `MCPError` becomes a JSON-RPC error.

```swift
public protocol ToolErrorConvertible: Error {
    func toErrorPayload(toolName: String) -> ToolManagerErrorPayload
}
```

### ToolArgumentError

Built-in error for argument validation:

```swift
public enum ToolArgumentError: Error {
    case decodingError(Error)
    case missingOrInvalid(String)
}
```

Thrown automatically by `requireString`, `requireBool`, `decodeArguments`. It conforms to `ToolErrorConvertible` and produces code `tool.argument_invalid` with tool and argument context.

## Registration Constraints

Tool names, resource URIs, and prompt names must each be unique across all registered features and capabilities. Duplicate identifiers trigger a precondition failure during registration. Keep each module's declared identifiers consistent with its descriptor cases.

Through the server registrars, an unknown tool returns `isError: true` with code `tool.unknown`; an unknown resource URI returns empty contents; an unknown prompt name returns no description and an empty message list. These routing results differ from calling the module's default lookup helpers directly.
