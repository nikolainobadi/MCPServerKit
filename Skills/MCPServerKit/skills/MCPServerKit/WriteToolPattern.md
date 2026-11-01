# WriteTool Pattern

Mutates state and persists changes. Replace `{Name}` placeholders with the actual capability name.

## Descriptor

```swift
import MCPServerKit

enum {Name}WriteToolDescriptor {
    case update{Name}
}

extension {Name}WriteToolDescriptor: MCPToolDescriptor {
    var name: String {
        switch self {
        case .update{Name}:
            return "update_{snake_name}"
        }
    }

    var description: String? {
        switch self {
        case .update{Name}:
            return "{Description of what is updated}"
        }
    }

    var inputSchema: Value {
        switch self {
        case .update{Name}:
            return {ArgumentsType}.schema()
        }
    }

    var annotations: Tool.Annotations {
        switch self {
        case .update{Name}:
            return .init(title: "Update {Name}", readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false)
        }
    }
}
```

## Handler

```swift
import MCPServerKit

struct {Name}WriteToolHandler {
    private let writer: any {Name}Writer

    init(writer: any {Name}Writer) {
        self.writer = writer
    }
}

extension {Name}WriteToolHandler: ToolHandler {
    typealias Descriptor = {Name}WriteToolDescriptor

    func handle(_ descriptor: Descriptor, arguments: [String: Value]?) async throws -> CallTool.Result {
        switch descriptor {
        case .update{Name}:
            let args = try decodeArguments({ArgumentsType}.self, from: arguments)
            let result = try writer.update{Name}(args: args)
            return .init(content: [.text(text: encodePayload(result, formatting: .prettyPrinted), annotations: nil, _meta: nil)])
        }
    }
}
```

## Protocol

```swift
protocol {Name}Writer: Sendable {
    func update{Name}(args: {ArgumentsType}) throws -> {ReturnType}
}
```

## Arguments Type (if using SchemaDerivable)

```swift
import MCPServerKit

struct {ArgumentsType}: Decodable, SchemaDerivable {
    // Declare stored properties matching the tool's declared arguments

    static func schema() -> Value {
        // Replace the empty dictionary with .required(...) / .optional(...) fields matching those properties
        Schema.object([:])
    }
}
```

Implement `schema()` explicitly; `SchemaDerivable` does not synthesize it. Replace the property and schema comments with the declared arguments. `{ReturnType}` must conform to `Encodable` for `encodePayload`.

Errors thrown by the writer must conform to `ToolErrorConvertible`, or the handler must translate them before they escape.

## Wiring

```swift
.init(handler: {Name}WriteToolHandler(writer: manager))
```
