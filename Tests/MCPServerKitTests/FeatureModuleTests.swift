import Testing
@testable import MCPServerKit

struct FeatureModuleTests {
    @Test
    func `Feature exposes tools from every capability in order`() {
        let sut = makeSUT(includeExtras: true)

        #expect(sut.tools.flatMap(\.tools).map(\.name) == ["read_item", "write_item"])
    }

    @Test
    func `Feature exposes resources attached to its capabilities`() {
        let sut = makeSUT(includeExtras: true)

        #expect(sut.resources.flatMap(\.resources).map(\.uri) == ["docs://guide"])
    }

    @Test
    func `Feature exposes prompts attached to its capabilities`() {
        let sut = makeSUT(includeExtras: true)

        #expect(sut.prompts.flatMap(\.prompts).map(\.name) == ["review_item"])
    }

    @Test
    func `Feature without attached resources exposes none`() {
        let sut = makeSUT(includeExtras: false)

        #expect(sut.resources.isEmpty)
    }

    @Test
    func `Feature without attached prompts exposes none`() {
        let sut = makeSUT(includeExtras: false)

        #expect(sut.prompts.isEmpty)
    }
}


// MARK: - Test Doubles
extension FeatureModuleTests {
    enum ReadDescriptor: CaseIterable, MCPToolDescriptor {
        case read

        var name: String { "read_item" }
        var description: String? { nil }
        var inputSchema: Value { .object([:]) }
        var annotations: Tool.Annotations { nil }
    }

    enum WriteDescriptor: CaseIterable, MCPToolDescriptor {
        case write

        var name: String { "write_item" }
        var description: String? { nil }
        var inputSchema: Value { .object([:]) }
        var annotations: Tool.Annotations { nil }
    }

    struct StubReadHandler: ToolHandler {
        func handle(_ descriptor: ReadDescriptor, arguments: [String: Value]?) async throws -> CallTool.Result {
            return .init(content: [], isError: false)
        }
    }

    struct StubWriteHandler: ToolHandler {
        func handle(_ descriptor: WriteDescriptor, arguments: [String: Value]?) async throws -> CallTool.Result {
            return .init(content: [], isError: false)
        }
    }

    enum GuideResource: CaseIterable, MCPResourceDescriptor {
        case guide

        var uri: String { "docs://guide" }
        var name: String { "guide" }
        var description: String { "Guide" }
        var mimeType: String { "text/plain" }
    }

    struct StubResourceModule: ResourceModule {
        func read(_ resource: GuideResource) -> [Resource.Content] {
            return []
        }
    }

    enum ReviewPrompt: CaseIterable, MCPPromptDescriptor {
        case review

        var name: String { "review_item" }
        var description: String { "Review" }
        var arguments: [Prompt.Argument] { [] }
    }

    struct StubPromptModule: PromptModule {
        func prompt(_ prompt: ReviewPrompt, arguments: [String: String]?) -> GetPrompt.Result {
            return .init(description: nil, messages: [])
        }
    }
}


// MARK: - SUT
private extension FeatureModuleTests {
    func makeSUT(includeExtras: Bool) -> FeatureModule {
        let resources: [any ResourceModule] = includeExtras ? [StubResourceModule()] : []
        let prompts: [any PromptModule] = includeExtras ? [StubPromptModule()] : []

        return FeatureModule(capabilities: [
            FeatureCapability(handler: StubReadHandler(), resources: resources, prompts: []),
            FeatureCapability(handler: StubWriteHandler(), resources: [], prompts: prompts)
        ])
    }
}
