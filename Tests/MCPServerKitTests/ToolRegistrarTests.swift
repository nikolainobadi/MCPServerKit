import Testing
@testable import MCPServerKit

struct ToolRegistrarTests {
    @Test
    func `Unknown tool result is flagged as an error`() throws {
        let sut = makeSUT()

        let result = sut.unknownToolError(toolName: "missing_tool")

        let isError = try #require(result.isError as Bool?)
        #expect(isError)
    }

    @Test
    func `Unknown tool result names the missing tool in a sorted JSON payload`() throws {
        let sut = makeSUT()

        let result = sut.unknownToolError(toolName: "missing_tool")

        #expect(try text(of: result) == #"{"code":"tool.unknown","details":{"tool":"missing_tool"},"message":"Unknown tool: missing_tool"}"#)
    }
}


// MARK: - Thrown Errors
extension ToolRegistrarTests {
    @Test
    func `Thrown error result is flagged as an error`() throws {
        let sut = makeSUT()

        let result = sut.errorResult(from: StubConvertibleError(), toolName: "greet_user")

        let isError = try #require(result.isError as Bool?)
        #expect(isError)
    }

    @Test
    func `Thrown error result carries the payload the error produced`() throws {
        let sut = makeSUT()

        let result = sut.errorResult(from: StubConvertibleError(), toolName: "greet_user")

        #expect(try text(of: result) == #"{"code":"stub.failed","details":{"tool":"greet_user"},"message":"Stub failed."}"#)
    }
}


// MARK: - Test Doubles
extension ToolRegistrarTests {
    struct StubConvertibleError: ToolErrorConvertible {
        func toErrorPayload(toolName: String) -> ToolManagerErrorPayload {
            return .init(code: "stub.failed", message: "Stub failed.", details: ["tool": toolName])
        }
    }
}


// MARK: - Helpers
private extension ToolRegistrarTests {
    func text(of result: CallTool.Result) throws -> String {
        let content = try #require(result.content.first)
        guard case .text(let text, _, _) = content else {
            Issue.record("Expected text content, got \(content)")
            return ""
        }
        return text
    }
}


// MARK: - SUT
private extension ToolRegistrarTests {
    func makeSUT() -> ToolRegistrar.Type {
        return ToolRegistrar.self
    }
}
