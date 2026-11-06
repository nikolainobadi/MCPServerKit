# ResourceTool Pattern

Tool paired with static reference content delivered via MCP resource URI. Replace `{Name}` placeholders with the actual capability name.

## Tool Descriptor

```swift
import MCPServerKit

enum {Name}ToolDescriptor {
    case {toolCase}
}

extension {Name}ToolDescriptor: MCPToolDescriptor {
    var name: String {
        switch self {
        case .{toolCase}:
            return "{tool_snake_name}"
        }
    }

    var description: String? {
        switch self {
        case .{toolCase}:
            return "{Description}"
        }
    }

    var inputSchema: Value {
        switch self {
        case .{toolCase}:
            return Schema.object([:])
        }
    }

    var annotations: Tool.Annotations {
        switch self {
        case .{toolCase}:
            return .init(title: "{Title}", readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
        }
    }
}
```

## Tool Handler

```swift
import MCPServerKit

struct {Name}ToolHandler {
    private let provider: any {Name}Provider

    init(provider: any {Name}Provider) {
        self.provider = provider
    }
}

extension {Name}ToolHandler: ToolHandler {
    typealias Descriptor = {Name}ToolDescriptor

    func handle(_ descriptor: Descriptor, arguments: [String: Value]?) async throws -> CallTool.Result {
        switch descriptor {
        case .{toolCase}:
            let result = try provider.provide{Name}()
            return .init(content: [.text(text: result, annotations: nil, _meta: nil)])
        }
    }
}
```

## Resource Descriptor

```swift
import MCPServerKit

enum {Name}ResourceDescriptor {
    case rules
}

extension {Name}ResourceDescriptor: MCPResourceDescriptor {
    var uri: String {
        switch self {
        case .rules:
            return "{scheme}://rules/\(name)"
        }
    }

    var name: String {
        switch self {
        case .rules:
            return "{resource_snake_name}"
        }
    }

    var description: String {
        switch self {
        case .rules:
            return "{Description of the resource content}"
        }
    }

    var mimeType: String {
        switch self {
        case .rules:
            return "text/markdown"
        }
    }
}
```

## Resource Module

```swift
import MCPServerKit

struct {Name}ResourceModule: ResourceModule {
    typealias ResourceDescriptor = {Name}ResourceDescriptor

    func read(_ resource: {Name}ResourceDescriptor) -> [Resource.Content] {
        switch resource {
        case .rules:
            return [.text({Name}Rules.content, uri: resource.uri, mimeType: resource.mimeType)]
        }
    }
}
```

## Static Content

```swift
enum {Name}Rules {
    static let content = """
    # {Title}

    {Markdown rules content here}
    """
}
```

## Protocol

```swift
protocol {Name}Provider: Sendable {
    func provide{Name}() throws -> String
}
```

Errors thrown by the provider should conform to `ToolErrorConvertible`, so the provider's conformer translates dependency errors before they reach the handler; other errors get the generic code `internal.unhandled`, except `CancellationError` and `MCPError`, which propagate to the SDK. Preserve those exceptions when translating dependency errors (see `ApiReference.md`). Registering the resource module makes its content available at the descriptor URI; the text result above does not automatically include a resource reference.

## Wiring

```swift
.init(handler: {Name}ToolHandler(provider: backend), resources: [{Name}ResourceModule()])
```
