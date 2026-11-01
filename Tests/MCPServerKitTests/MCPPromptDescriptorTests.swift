import Testing
@testable import MCPServerKit

struct MCPPromptDescriptorTests {
    @Test
    func `Lookup by name finds the matching case`() {
        let sut = makeSUT()

        #expect(sut.init(name: "summarize") == .summarize)
    }

    @Test
    func `Lookup by an unknown name finds nothing`() {
        let sut = makeSUT()

        #expect(sut.init(name: "missing_prompt") == nil)
    }
}


// MARK: - Built Prompt
extension MCPPromptDescriptorTests {
    @Test
    func `Built prompt carries the descriptor name`() {
        let descriptor = makeSUT().codeReview

        #expect(descriptor.prompt.name == descriptor.name)
    }

    @Test
    func `Built prompt carries the descriptor description`() {
        let descriptor = makeSUT().codeReview

        #expect(descriptor.prompt.description == descriptor.description)
    }

    @Test
    func `Built prompt carries the descriptor arguments`() throws {
        let descriptor = makeSUT().codeReview

        let arguments = try #require(descriptor.prompt.arguments)
        #expect(arguments == descriptor.arguments)
    }
}


// MARK: - Test Doubles
extension MCPPromptDescriptorTests {
    enum StubPrompt: CaseIterable, MCPPromptDescriptor {
        case codeReview
        case summarize

        var name: String {
            switch self {
            case .codeReview:
                return "code_review"
            case .summarize:
                return "summarize"
            }
        }

        var description: String { "Runs \(name)" }
        var arguments: [Prompt.Argument] { [.init(name: "language", description: "Programming language", required: true)] }
    }
}


// MARK: - SUT
private extension MCPPromptDescriptorTests {
    func makeSUT() -> StubPrompt.Type {
        return StubPrompt.self
    }
}
