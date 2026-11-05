# ReadTool Pattern

Fetches data without side effects. Replace `{Name}` placeholders with the actual capability name.

## Descriptor

```swift
import MCPServerKit

enum {Name}ReadToolDescriptor {
    case read{Name}
}

extension {Name}ReadToolDescriptor: MCPToolDescriptor {
    var name: String {
        switch self {
        case .read{Name}:
            return "read_{snake_name}"
        }
    }

    var description: String? {
        switch self {
        case .read{Name}:
            return "{Description of what is read}"
        }
    }

    var inputSchema: Value {
        switch self {
        case .read{Name}:
            return Schema.object([:])
        }
    }

    var annotations: Tool.Annotations {
        switch self {
        case .read{Name}:
            return .init(title: "Read {Name}", readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
        }
    }
}
```

## Handler

```swift
import MCPServerKit

struct {Name}ReadToolHandler {
    private let reader: any {Name}Reader

    init(reader: any {Name}Reader) {
        self.reader = reader
    }
}

extension {Name}ReadToolHandler: ToolHandler {
    typealias Descriptor = {Name}ReadToolDescriptor

    func handle(_ descriptor: Descriptor, arguments: [String: Value]?) async throws -> CallTool.Result {
        switch descriptor {
        case .read{Name}:
            let result = try reader.read{Name}()
            return .init(content: [.text(text: encodePayload(result, formatting: .prettyPrinted), annotations: nil, _meta: nil)])
        }
    }
}
```

## Protocol

```swift
protocol {Name}Reader: Sendable {
    func read{Name}() throws -> {ReturnType}
}
```

`{ReturnType}` must conform to `Encodable` for `encodePayload`. Errors thrown by the reader should conform to `ToolErrorConvertible`, or the handler should translate them before they escape; otherwise the client gets the generic code `internal.unhandled`.

## Wiring

```swift
.init(handler: {Name}ReadToolHandler(reader: manager))
```
