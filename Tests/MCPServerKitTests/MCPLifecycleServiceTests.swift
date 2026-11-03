import Testing
import Logging
import Foundation
@testable import MCPServerKit

struct MCPLifecycleServiceTests {
    @Test(.timeLimit(.minutes(1)))
    func `Server sends only the response to the first client message`() async throws {
        let (sut, server, transport) = makeSUT()
        let running = Task { try await sut.run() }
        await transport.deliver(Data(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#.utf8))
        await transport.waitForFirstSend()

        await server.stop()
        try await running.value

        let sent = try await transport.sentMessages.map { try JSONDecoder().decode([String: Value].self, from: $0) }
        #expect(sent.map { $0["id"] } == [.int(1)])
    }
}


// MARK: - Test Doubles
extension MCPLifecycleServiceTests {
    actor MockTransport: Transport {
        private let incoming = AsyncThrowingStream<Data, Error>.makeStream()
        private let firstSend = AsyncStream<Void>.makeStream()

        private(set) var sentMessages: [Data] = []

        nonisolated let logger = Logger(label: "test", factory: { _ in SwiftLogNoOpLogHandler() })

        func connect() async throws { }

        func disconnect() async { }

        func send(_ data: Data) async throws {
            sentMessages.append(data)
            firstSend.continuation.finish()
        }

        func receive() -> AsyncThrowingStream<Data, Error> {
            return incoming.stream
        }

        func deliver(_ data: Data) {
            incoming.continuation.yield(data)
        }

        func waitForFirstSend() async {
            for await _ in firstSend.stream { }
        }
    }
}


// MARK: - SUT
private extension MCPLifecycleServiceTests {
    func makeSUT() -> (sut: MCPLifecycleService, server: Server, transport: MockTransport) {
        let server = Server(
            name: "test",
            version: "1.0.0",
            instructions: nil,
            capabilities: .init(logging: nil, prompts: nil, resources: nil, tools: nil),
            configuration: .default
        )
        let transport = MockTransport()
        let sut = MCPLifecycleService(server: server, transport: transport)
        return (sut, server, transport)
    }
}
