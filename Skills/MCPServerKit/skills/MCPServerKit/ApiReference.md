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

`PayloadFormatting`: `.compact` or `.prettyPrinted`

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

### RequiredSchema

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

Conform to `SchemaDerivable` on argument structs to generate `inputSchema` from a type rather than inline.

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

Default implementations: `resource` property, `toolResultContent` property, `init?(uri:)` lookup.

## ResourceModule

```swift
public protocol ResourceModule: Sendable {
    associatedtype ResourceDescriptor: MCPResourceDescriptor
    var resources: [Resource] { get }  // default: derived from ResourceDescriptor.allCases
    func read(_ resource: ResourceDescriptor) -> [Resource.Content]
    func readContent(for uri: String) -> [Resource.Content]  // default: resolves URI then calls read(_:)
}
```

Only `read(_:)` needs implementation.

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

Only `prompt(_:arguments:)` needs implementation. Prompt arguments arrive as plain strings, matching the MCP SDK's `GetPrompt.Parameters`. Build messages with `.user(.text(text:))` / `.assistant(.text(text:))`.

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

Any error escaping a tool boundary must conform:

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

Thrown automatically by `requireString`, `requireBool`, `decodeArguments`.
