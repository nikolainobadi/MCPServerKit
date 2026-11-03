import Testing
import Logging
import Foundation
@testable import MCPServerKit

struct InitializeSanitizingTransportTests {
    @Test(arguments: [
        Value.object(["codex/auth-change": .object([:])]),
        Value.object(["openai/visibility": .object(["enabled": .bool(true)])]),
        Value.object(["example/flag": .bool(true)]),
        Value.object(["example/name": .string("value")])
    ])
    func `Initialize request loses its experimental capabilities`(experimental: Value) async throws {
        let (sut, base) = makeSUT()
        await base.deliver(initializeMessage(id: .int(1), capabilities: ["experimental": experimental]))

        let message = try await nextMessage(from: sut)

        #expect(try capabilities(of: message)["experimental"] == nil)
    }

    @Test
    func `Initialize request keeps its other capabilities`() async throws {
        let (sut, base) = makeSUT()
        let extensions = Value.object(["io.modelcontextprotocol/ui": .object(["mimeTypes": .array([.string("text/html")])])])
        let roots = Value.object(["listChanged": .bool(true)])
        await base.deliver(initializeMessage(id: .int(1), capabilities: ["experimental": .object(["a": .object([:])]), "extensions": extensions, "roots": roots]))

        let message = try await nextMessage(from: sut)

        #expect(try capabilities(of: message) == ["extensions": extensions, "roots": roots])
    }

    @Test(arguments: [Value.int(7), Value.string("abc/é")])
    func `Initialize request keeps its id`(id: Value) async throws {
        let (sut, base) = makeSUT()
        await base.deliver(initializeMessage(id: id, capabilities: ["experimental": .object(["a": .object([:])])]))

        let message = try await nextMessage(from: sut)

        #expect(try decoded(message)["id"] == id)
    }
}


// MARK: - Unchanged Messages
extension InitializeSanitizingTransportTests {
    @Test(arguments: [
        #"{ "id" : 1, "method" : "initialize", "params" : { "capabilities" : { "roots" : {} } }, "jsonrpc" : "2.0" }"#,
        #"{ "id" : 1, "method" : "initialize", "params" : { "capabilities" : "unexpected" }, "jsonrpc" : "2.0" }"#,
        #"{ "id" : 1, "method" : "tools/call", "params" : { "capabilities" : { "experimental" : { "a" : {} } } }, "jsonrpc" : "2.0" }"#,
        #"[ { "id" : 1, "method" : "initialize", "params" : { "capabilities" : { "experimental" : { "a" : {} } } }, "jsonrpc" : "2.0" } ]"#,
        "{not json"
    ])
    func `Message with nothing to remove keeps its exact bytes`(text: String) async throws {
        let (sut, base) = makeSUT()
        let original = Data(text.utf8)
        await base.deliver(original)

        let message = try await nextMessage(from: sut)

        #expect(message == original)
    }
}


// MARK: - Stream Behavior
extension InitializeSanitizingTransportTests {
    @Test
    func `Messages arrive in the order the base transport received them`() async throws {
        let (sut, base) = makeSUT()
        let originals = (0..<50).map { Data(#"{"id":\#($0)}"#.utf8) }
        for original in originals {
            await base.deliver(original)
        }
        await base.finish()

        var messages: [Data] = []
        for try await message in await sut.receive() {
            messages.append(message)
        }

        #expect(messages == originals)
    }

    @Test
    func `Error from the base transport reaches the consumer`() async throws {
        let (sut, base) = makeSUT()
        await base.fail(with: MockTransport.StubError())

        let stream = await sut.receive()

        await #expect(throws: MockTransport.StubError.self) {
            for try await _ in stream { }
        }
    }

    @Test
    func `Outgoing data reaches the base transport unchanged`() async throws {
        let (sut, base) = makeSUT()
        let original = Data(#"{"id":1}"#.utf8)

        try await sut.send(original)

        #expect(await base.nextSent() == original)
    }
}


// MARK: - Handshake
extension InitializeSanitizingTransportTests {
    @Test(arguments: [
        [String: Value](),
        ["experimental": Value.object(["codex/auth-change": .object([:])])],
        ["experimental": Value.object(["openai/visibility": .object(["enabled": .bool(true)])]), "extensions": Value.object(["io.modelcontextprotocol/ui": .object(["mimeTypes": .array([.string("text/html")])])])],
        ["experimental": Value.object(["example/name": .string("value")])]
    ])
    func `Server completes the handshake for any client capabilities`(capabilities: [String: Value]) async throws {
        let (sut, base) = makeSUT()
        let server = try await startServer(on: sut)
        await base.deliver(initializeMessage(id: .int(1), capabilities: capabilities))

        let response = try decoded(try #require(await base.nextSent()))
        await server.stop()

        #expect(response["result"] != nil)
    }

    @Test
    func `Server lists tools after a handshake with object-valued experimental capabilities`() async throws {
        let (sut, base) = makeSUT()
        let server = try await startServer(on: sut)
        await base.deliver(initializeMessage(id: .int(1), capabilities: ["experimental": .object(["a": .object([:])])]))
        _ = await base.nextSent()
        await base.deliver(Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#.utf8))

        let response = try decoded(try #require(await base.nextSent()))
        await server.stop()

        #expect(response["result"] != nil)
    }
}


// MARK: - Test Doubles
extension InitializeSanitizingTransportTests {
    actor MockTransport: Transport {
        struct StubError: Error { }

        private let incoming = AsyncThrowingStream<Data, Error>.makeStream()
        private let sent = AsyncStream<Data>.makeStream()
        private var sentIterator: AsyncStream<Data>.Iterator?

        nonisolated let logger = Logger(label: "test", factory: { _ in SwiftLogNoOpLogHandler() })

        func connect() async throws { }

        func disconnect() async { }

        func send(_ data: Data) async throws {
            sent.continuation.yield(data)
        }

        func receive() -> AsyncThrowingStream<Data, Error> {
            return incoming.stream
        }

        func deliver(_ data: Data) {
            incoming.continuation.yield(data)
        }

        func finish() {
            incoming.continuation.finish()
        }

        func fail(with error: Error) {
            incoming.continuation.finish(throwing: error)
        }

        func nextSent() async -> Data? {
            var iterator = sentIterator ?? sent.stream.makeAsyncIterator()
            let data = await iterator.next(isolation: self)
            sentIterator = iterator
            return data
        }
    }
}


// MARK: - Helpers
private extension InitializeSanitizingTransportTests {
    func initializeMessage(id: Value, capabilities: [String: Value]) -> Data {
        let message: [String: Value] = [
            "jsonrpc": .string("2.0"),
            "id": id,
            "method": .string("initialize"),
            "params": .object([
                "protocolVersion": .string("2025-11-25"),
                "capabilities": .object(capabilities),
                "clientInfo": .object(["name": .string("test"), "version": .string("1.0.0")])
            ])
        ]
        return try! JSONEncoder().encode(message)
    }

    func nextMessage(from sut: InitializeSanitizingTransport) async throws -> Data {
        var iterator = await sut.receive().makeAsyncIterator()
        return try #require(try await iterator.next())
    }

    func decoded(_ data: Data) throws -> [String: Value] {
        return try JSONDecoder().decode([String: Value].self, from: data)
    }

    func capabilities(of data: Data) throws -> [String: Value] {
        let params = try #require(try decoded(data)["params"]?.objectValue)
        return try #require(params["capabilities"]?.objectValue)
    }

    func startServer(on transport: any Transport) async throws -> Server {
        let server = Server(
            name: "test",
            version: "1.0.0",
            instructions: nil,
            capabilities: .init(logging: nil, prompts: nil, resources: nil, tools: .init(listChanged: false)),
            configuration: .default
        )
        await server.withMethodHandler(ListTools.self) { _ in
            return ListTools.Result(tools: [])
        }
        try await server.start(transport: transport)
        return server
    }
}


// MARK: - SUT
private extension InitializeSanitizingTransportTests {
    func makeSUT() -> (sut: InitializeSanitizingTransport, base: MockTransport) {
        let base = MockTransport()
        let sut = InitializeSanitizingTransport(base: base, logger: base.logger)
        return (sut, base)
    }
}
