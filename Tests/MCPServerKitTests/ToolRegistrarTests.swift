import Testing
import Logging
import Foundation
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


// MARK: - Tool Failures
extension ToolRegistrarTests {
    @Test
    func `Unconverted error comes back as an error result`() async throws {
        let sut = makeSUT()

        let result = try await sut.call(MockToolModule(behavior: .throwing(StubPlainError())), with: toolCall(), logger: silentLogger())

        let isError = try #require(result.isError as Bool?)
        #expect(isError)
    }

    @Test
    func `Unconverted error result carries the generic code and the error description`() async throws {
        let sut = makeSUT()

        let result = try await sut.call(MockToolModule(behavior: .throwing(StubPlainError())), with: toolCall(), logger: silentLogger())

        #expect(try text(of: result) == #"{"code":"internal.unhandled","details":{"tool":"stub_tool"},"message":"StubPlainError()"}"#)
    }

    @Test
    func `Converted error keeps the payload it produced`() async throws {
        let sut = makeSUT()

        let result = try await sut.call(MockToolModule(behavior: .throwing(StubConvertibleError())), with: toolCall(), logger: silentLogger())

        #expect(try text(of: result) == #"{"code":"stub.failed","details":{"tool":"stub_tool"},"message":"Stub failed."}"#)
    }

    @Test
    func `Cancellation is left for the SDK to handle`() async {
        let sut = makeSUT()

        await #expect(throws: CancellationError.self) {
            try await sut.call(MockToolModule(behavior: .throwing(CancellationError())), with: toolCall(), logger: silentLogger())
        }
    }

    @Test
    func `MCP error is left for the SDK to handle`() async {
        let sut = makeSUT()

        await #expect(throws: MCPError.self) {
            try await sut.call(MockToolModule(behavior: .throwing(MCPError.invalidParams("bad"))), with: toolCall(), logger: silentLogger())
        }
    }
}


// MARK: - Server Survival
extension ToolRegistrarTests {
    @Test
    func `Server answers a later request after a tool throws an unconverted error`() async throws {
        let connection = try await connect(to: MockToolModule(behavior: .throwing(StubPlainError())))
        try await connection.client.send(toolCallMessage(id: 1))
        _ = try await connection.nextMessage()
        try await connection.client.send(pingMessage(id: 2))

        let response = try await connection.nextMessage()
        await connection.server.stop()

        #expect(response["id"] == .int(2))
    }

    @Test
    func `Client receives an error result when a tool throws an unconverted error`() async throws {
        let connection = try await connect(to: MockToolModule(behavior: .throwing(StubPlainError())))
        try await connection.client.send(toolCallMessage(id: 1))

        let response = try await connection.nextMessage()
        await connection.server.stop()

        let result = try #require(response["result"]?.objectValue)
        #expect(result["isError"] == .bool(true))
    }

    @Test
    func `Client receives a JSON-RPC error when a tool throws an MCP error`() async throws {
        let connection = try await connect(to: MockToolModule(behavior: .throwing(MCPError.invalidParams("bad"))))
        try await connection.client.send(toolCallMessage(id: 1))

        let response = try await connection.nextMessage()
        await connection.server.stop()

        #expect(response["error"] != nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func `Cancelled tool call gets no response and the server keeps answering`() async throws {
        let events = AsyncStream<ToolEvent>.makeStream()
        let connection = try await connect(to: MockToolModule(behavior: .suspendingUntilCancelled(events: events.continuation)))
        var eventIterator = events.stream.makeAsyncIterator()
        try await connection.client.send(toolCallMessage(id: 1))
        _ = await eventIterator.next()
        try await connection.client.send(cancelMessage(requestID: 1))
        _ = await eventIterator.next()
        try await connection.client.send(pingMessage(id: 2))

        let response = try await connection.nextMessage()
        await connection.server.stop()

        #expect(response["id"] == .int(2))
    }
}


// MARK: - Test Doubles
extension ToolRegistrarTests {
    struct StubConvertibleError: ToolErrorConvertible {
        func toErrorPayload(toolName: String) -> ToolManagerErrorPayload {
            return .init(code: "stub.failed", message: "Stub failed.", details: ["tool": toolName])
        }
    }

    struct StubPlainError: Error { }

    enum ToolEvent: Sendable {
        case started
        case finished
    }

    enum StubToolDescriptor: CaseIterable, MCPToolDescriptor {
        case stub

        var name: String { "stub_tool" }
        var description: String? { nil }
        var inputSchema: Value { .object([:]) }
        var annotations: Tool.Annotations { .init() }
    }

    struct MockToolModule: ToolModule {
        typealias ToolDescriptor = StubToolDescriptor

        enum Behavior: Sendable {
            case throwing(any Error)
            case suspendingUntilCancelled(events: AsyncStream<ToolEvent>.Continuation)
        }

        let behavior: Behavior

        func handle(_ params: CallTool.Parameters) async throws -> CallTool.Result {
            switch behavior {
            case .throwing(let error):
                throw error
            case .suspendingUntilCancelled(let events):
                events.yield(.started)
                defer { events.yield(.finished) }
                try await Task.sleep(for: .seconds(3600))
                return .init(content: [], isError: false)
            }
        }
    }

    actor Connection {
        let server: Server
        let client: InMemoryTransport
        private var iterator: AsyncThrowingStream<Data, Error>.Iterator

        init(server: Server, client: InMemoryTransport, iterator: AsyncThrowingStream<Data, Error>.Iterator) {
            self.server = server
            self.client = client
            self.iterator = iterator
        }

        func nextMessage() async throws -> [String: Value] {
            var current = iterator
            let data = try #require(try await current.next(isolation: self))
            iterator = current
            return try JSONDecoder().decode([String: Value].self, from: data)
        }
    }
}


// MARK: - Helpers
private extension ToolRegistrarTests {
    func silentLogger() -> Logger {
        return Logger(label: "test", factory: { _ in SwiftLogNoOpLogHandler() })
    }

    func toolCall() -> CallTool.Parameters {
        return .init(name: "stub_tool", arguments: nil)
    }

    func encoded(_ message: [String: Value]) throws -> Data {
        return try JSONEncoder().encode(message)
    }

    func toolCallMessage(id: Int) throws -> Data {
        return try encoded(["jsonrpc": .string("2.0"), "id": .int(id), "method": .string("tools/call"), "params": .object(["name": .string("stub_tool")])])
    }

    func pingMessage(id: Int) throws -> Data {
        return try encoded(["jsonrpc": .string("2.0"), "id": .int(id), "method": .string("ping")])
    }

    func cancelMessage(requestID: Int) throws -> Data {
        return try encoded(["jsonrpc": .string("2.0"), "method": .string("notifications/cancelled"), "params": .object(["requestId": .int(requestID)])])
    }

    func connect(to module: MockToolModule) async throws -> Connection {
        let server = Server(
            name: "test",
            version: "1.0.0",
            instructions: nil,
            capabilities: .init(logging: nil, prompts: nil, resources: nil, tools: .init(listChanged: false)),
            configuration: .default
        )
        await makeSUT().register(modules: [module], on: server, logger: silentLogger())

        let (client, serverTransport) = await InMemoryTransport.createConnectedPair(logger: silentLogger())
        try await client.connect()
        try await server.start(transport: serverTransport)

        return Connection(server: server, client: client, iterator: await client.receive().makeAsyncIterator())
    }

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
