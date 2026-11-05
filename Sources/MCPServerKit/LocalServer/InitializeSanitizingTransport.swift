import MCP
import Logging
import Foundation

/// Removes client `experimental` capabilities from `initialize` requests before the SDK decodes them.
///
/// swift-sdk 0.12.1 types these capabilities as `[String: String]`, while the MCP specification allows
/// object values, so a valid `initialize` request can fail to decode. The kit never reads client
/// capabilities, which makes removing them safe.
///
/// Delete this type once a swift-sdk release includes
/// https://github.com/modelcontextprotocol/swift-sdk/pull/276.
actor InitializeSanitizingTransport: Transport {
    private let base: any Transport

    nonisolated let logger: Logger

    init(base: any Transport, logger: Logger) {
        self.base = base
        self.logger = logger
    }
}


// MARK: - Transport
extension InitializeSanitizingTransport {
    func connect() async throws {
        try await base.connect()
    }

    func disconnect() async {
        await base.disconnect()
    }

    func send(_ data: Data) async throws {
        try await base.send(data)
    }

    func receive() -> AsyncThrowingStream<Data, Error> {
        let base = self.base

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await message in await base.receive() {
                        continuation.yield(Self.sanitize(message))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}


// MARK: - Private Methods
private extension InitializeSanitizingTransport {
    /// Returns the original bytes unless an `initialize` request's `experimental` capabilities were removed.
    static func sanitize(_ data: Data) -> Data {
        guard
            var message = try? JSONDecoder().decode([String: Value].self, from: data),
            message["method"]?.stringValue == "initialize",
            case .object(var params)? = message["params"],
            case .object(var capabilities)? = params["capabilities"],
            capabilities.removeValue(forKey: "experimental") != nil
        else {
            return data
        }

        params["capabilities"] = .object(capabilities)
        message["params"] = .object(params)

        return (try? JSONEncoder().encode(message)) ?? data
    }
}
