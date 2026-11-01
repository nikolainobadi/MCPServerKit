# MCPServerKit Examples

## Tool Descriptor + Handler

```swift
enum GreetingToolDescriptor {
    case greet
    case farewell
}

extension GreetingToolDescriptor: MCPToolDescriptor {
    var name: String {
        switch self {
        case .greet: return "greet_user"
        case .farewell: return "farewell_user"
        }
    }

    var description: String? {
        switch self {
        case .greet: return "Greet a user by name"
        case .farewell: return "Say goodbye to a user"
        }
    }

    var inputSchema: Value {
        switch self {
        case .greet:
            return Schema.object([
                "name": .required(.string(description: "The user's name")),
                "formal": .optional(.bool(description: "Use formal greeting"))
            ])
        case .farewell:
            return Schema.object([
                "name": .required(.string(description: "The user's name"))
            ])
        }
    }

    var annotations: Tool.Annotations { .init() }
}
```

```swift
struct GreetingToolHandler: ToolHandler {
    typealias Descriptor = GreetingToolDescriptor

    func handle(_ descriptor: GreetingToolDescriptor, arguments: [String: Value]?) async throws -> CallTool.Result {
        switch descriptor {
        case .greet:
            let name = try requireString(arguments, key: "name")
            let formal = (try? requireBool(arguments, key: "formal")) ?? false
            let greeting = formal ? "Good day, \(name)." : "Hey \(name)!"
            return .init(content: [.text(text: greeting, annotations: nil, _meta: nil)])
        case .farewell:
            let name = try requireString(arguments, key: "name")
            return .init(content: [.text(text: "Goodbye, \(name)!", annotations: nil, _meta: nil)])
        }
    }
}
```

## SchemaDerivable Arguments

```swift
struct AddItemArguments: Codable, SchemaDerivable {
    let title: String
    let count: Int
    let tags: [String]?

    static func schema() -> Value {
        Schema.object([
            "title": .required(.string(description: "Item title")),
            "count": .required(.int(description: "Number of items", minimum: 1)),
            "tags": .optional(.array(of: .string(), description: "Optional tags"))
        ])
    }
}

// In descriptor:
var inputSchema: Value {
    switch self {
    case .addItem: return AddItemArguments.schema()
    }
}

// In handler:
case .addItem:
    let args = try decodeArguments(AddItemArguments.self, from: arguments)
```

## Resource

```swift
enum GuideResourceDescriptor {
    case styleguide
    case apiDocs
}

extension GuideResourceDescriptor: MCPResourceDescriptor {
    var uri: String {
        switch self {
        case .styleguide: return "docs://guides/style"
        case .apiDocs: return "docs://guides/api"
        }
    }

    var name: String {
        switch self {
        case .styleguide: return "Style Guide"
        case .apiDocs: return "API Documentation"
        }
    }

    var description: String {
        switch self {
        case .styleguide: return "Code style conventions"
        case .apiDocs: return "API endpoint documentation"
        }
    }

    var mimeType: String { "text/plain" }
}
```

```swift
struct GuideResourceModule: ResourceModule {
    typealias ResourceDescriptor = GuideResourceDescriptor

    func read(_ resource: GuideResourceDescriptor) -> [Resource.Content] {
        switch resource {
        case .styleguide:
            return [.text("Use 4-space indentation...", uri: resource.uri, mimeType: resource.mimeType)]
        case .apiDocs:
            return [.text("GET /api/v1/items...", uri: resource.uri, mimeType: resource.mimeType)]
        }
    }
}
```

## Prompt

```swift
enum ReviewPromptDescriptor {
    case codeReview
}

extension ReviewPromptDescriptor: MCPPromptDescriptor {
    var name: String {
        switch self {
        case .codeReview: return "code_review"
        }
    }

    var description: String {
        switch self {
        case .codeReview: return "Review code for best practices"
        }
    }

    var arguments: [Prompt.Argument] {
        switch self {
        case .codeReview:
            return [.init(name: "language", description: "Programming language", required: true)]
        }
    }
}
```

```swift
struct ReviewPromptModule: PromptModule {
    typealias PromptType = ReviewPromptDescriptor

    func prompt(_ prompt: ReviewPromptDescriptor, arguments: [String: String]?) -> GetPrompt.Result {
        switch prompt {
        case .codeReview:
            let language = arguments?["language"] ?? "Swift"
            return .init(description: "Code review prompt", messages: [
                .user(.text(text: "Review this \(language) code for best practices."))
            ])
        }
    }
}
```

## ToolError

```swift
enum ItemToolError: String, ToolError {
    static let domain = "item"

    case notFound       // → "item.not_found"
    case duplicateTitle // → "item.duplicate_title"

    var messageOverride: String? {
        switch self {
        case .notFound: return "Item not found."
        case .duplicateTitle: return nil  // uses default: "Duplicate Title"
        }
    }
}

// Throwing:
throw ItemToolError.notFound

// With runtime details:
throw ItemToolError.notFound.withDetails(["id": itemId], message: "Item '\(itemId)' not found.")
```

## Feature Assembly

```swift
enum ItemFeature {
    static func module(service: ItemService) -> FeatureModule {
        .init(capabilities: [
            .init(handler: ItemReadToolHandler(reader: service)),
            .init(handler: ItemWriteToolHandler(writer: service), resources: [GuideResourceModule()]),
            .init(handler: ItemSearchToolHandler(searcher: service), prompts: [ReviewPromptModule()])
        ])
    }
}
```

## Entry Point

```swift
@main
struct MyServer {
    static func main() async throws {
        let service = ItemService()
        let server = LocalMCPServer(
            name: "MyServer",
            version: "1.0.0",
            features: [ItemFeature.module(service: service)]
        )
        try await server.start()
    }
}
```
