import Testing
@testable import MCPServerKit

struct ToolModuleAdapterTests {
    @Test
    func `Adapter exposes one tool per descriptor case`() {
        let sut = makeSUT(shouldThrow: false).sut

        #expect(sut.tools.map(\.name) == ["greet_user", "farewell_user"])
    }

    @Test
    func `Tool call reaches the handler as the matching descriptor`() async throws {
        let (sut, handler) = makeSUT(shouldThrow: false)

        _ = try await sut.handle(.init(name: "farewell_user", arguments: nil))

        #expect(handler.receivedDescriptor == .farewell)
    }

    @Test
    func `Tool call passes its arguments to the handler`() async throws {
        let arguments: [String: Value] = ["name": .string("Ada")]
        let (sut, handler) = makeSUT(shouldThrow: false)

        _ = try await sut.handle(.init(name: "greet_user", arguments: arguments))

        #expect(handler.receivedArguments == arguments)
    }

    @Test
    func `Tool call returns the handler result unchanged`() async throws {
        let sut = makeSUT(shouldThrow: false).sut

        let result = try await sut.handle(.init(name: "greet_user", arguments: nil))

        #expect(result == MockDelegate.result)
    }

    @Test
    func `Handler failures propagate to the caller`() async {
        let sut = makeSUT(shouldThrow: true).sut

        await #expect(throws: MockDelegate.StubError.self) {
            try await sut.handle(.init(name: "greet_user", arguments: nil))
        }
    }
}


// MARK: - Test Doubles
extension ToolModuleAdapterTests {
    enum StubToolDescriptor: CaseIterable, MCPToolDescriptor {
        case greet
        case farewell

        var name: String {
            switch self {
            case .greet:
                return "greet_user"
            case .farewell:
                return "farewell_user"
            }
        }

        var description: String? { nil }
        var inputSchema: Value { .object([:]) }
        var annotations: Tool.Annotations { nil }
    }

    final class MockDelegate: ToolHandler, @unchecked Sendable {
        typealias Descriptor = StubToolDescriptor

        struct StubError: Error { }

        static let result = CallTool.Result(content: [.text(text: "done", annotations: nil, _meta: nil)], isError: false)

        private let shouldThrow: Bool
        private(set) var receivedDescriptor: StubToolDescriptor?
        private(set) var receivedArguments: [String: Value] = [:]

        init(shouldThrow: Bool) {
            self.shouldThrow = shouldThrow
        }

        func handle(_ descriptor: StubToolDescriptor, arguments: [String: Value]?) async throws -> CallTool.Result {
            receivedDescriptor = descriptor
            receivedArguments = arguments ?? [:]

            if shouldThrow {
                throw StubError()
            }

            return Self.result
        }
    }
}


// MARK: - SUT
private extension ToolModuleAdapterTests {
    func makeSUT(shouldThrow: Bool) -> (sut: ToolModuleAdapter<MockDelegate>, handler: MockDelegate) {
        let handler = MockDelegate(shouldThrow: shouldThrow)
        let sut = ToolModuleAdapter(handler: handler)
        return (sut, handler)
    }
}
