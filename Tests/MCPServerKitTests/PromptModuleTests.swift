import Testing
@testable import MCPServerKit

struct PromptModuleTests {
    @Test
    func `Module declares one prompt per descriptor case`() {
        let sut = makeSUT()

        #expect(sut.prompts.map(\.name) == ["code_review", "summarize"])
    }

    @Test
    func `Requesting a prompt by name answers with the matching prompt`() {
        let descriptor = StubPrompt.summarize
        let sut = makeSUT()

        let result = sut.getPrompt(name: descriptor.name, arguments: nil)

        #expect(result.description == descriptor.name)
    }

    @Test
    func `Requesting a prompt passes its arguments through`() {
        let language = "Swift"
        let sut = makeSUT()

        let result = sut.getPrompt(name: StubPrompt.codeReview.name, arguments: ["language": language])

        #expect(result.messages == [.user(.text(text: language))])
    }
}


// MARK: - Test Doubles
extension PromptModuleTests {
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

        var description: String { name }
        var arguments: [Prompt.Argument] { [] }
    }

    struct StubPromptModule: PromptModule {
        func prompt(_ prompt: StubPrompt, arguments: [String: String]?) -> GetPrompt.Result {
            let messages: [Prompt.Message] = arguments?["language"].map { [.user(.text(text: $0))] } ?? []
            return .init(description: prompt.name, messages: messages)
        }
    }
}


// MARK: - SUT
private extension PromptModuleTests {
    func makeSUT() -> StubPromptModule {
        return StubPromptModule()
    }
}
