import Testing
@testable import MCPServerKit

struct ToolArgumentErrorTests {
    @Test
    func `Missing argument reports the invalid argument code`() {
        let sut = makeSUT(error: .missingOrInvalid("name"))

        let payload = sut.toErrorPayload(toolName: "greet_user")

        #expect(payload.code == "tool.argument_invalid")
    }

    @Test
    func `Missing argument message names the argument`() {
        let sut = makeSUT(error: .missingOrInvalid("name"))

        let payload = sut.toErrorPayload(toolName: "greet_user")

        #expect(payload.message == "Missing or invalid argument: name.")
    }

    @Test
    func `Missing argument details identify the tool and the argument path`() throws {
        let toolName = "greet_user"
        let key = "name"
        let sut = makeSUT(error: .missingOrInvalid(key))

        let payload = sut.toErrorPayload(toolName: toolName)

        let details = try #require(payload.details)
        #expect(details == ["tool": toolName, "path": key])
    }
}


// MARK: - Decoding Failures
extension ToolArgumentErrorTests {
    @Test
    func `Decoding failure reports the invalid argument code`() {
        let sut = makeSUT(error: .decodingError(decodingError(for: .keyNotFound)))

        let payload = sut.toErrorPayload(toolName: "greet_user")

        #expect(payload.code == "tool.argument_invalid")
    }

    @Test
    func `Decoding failure uses a generic message`() {
        let sut = makeSUT(error: .decodingError(decodingError(for: .keyNotFound)))

        let payload = sut.toErrorPayload(toolName: "greet_user")

        #expect(payload.message == "Invalid tool arguments.")
    }

    @Test
    func `Missing key failure reports the missing key as the path`() throws {
        let toolName = "greet_user"
        let sut = makeSUT(error: .decodingError(decodingError(for: .keyNotFound)))

        let payload = sut.toErrorPayload(toolName: toolName)

        let details = try #require(payload.details)
        #expect(details == ["tool": toolName, "path": Self.missingKey.stringValue, "reason": Self.debugDescription])
    }

    @Test(arguments: [DecodingFailure.typeMismatch, .valueNotFound, .dataCorrupted])
    func `Value level failure reports the dotted coding path`(failure: DecodingFailure) throws {
        let toolName = "greet_user"
        let sut = makeSUT(error: .decodingError(decodingError(for: failure)))

        let payload = sut.toErrorPayload(toolName: toolName)

        let details = try #require(payload.details)
        #expect(details == ["tool": toolName, "path": "user.age", "reason": Self.debugDescription])
    }

    @Test
    func `Non decoding failure omits the argument path`() throws {
        let sut = makeSUT(error: .decodingError(StubError()))

        let payload = sut.toErrorPayload(toolName: "greet_user")

        let details = try #require(payload.details)
        #expect(details["path"] == nil)
    }
}


// MARK: - Test Doubles
extension ToolArgumentErrorTests {
    enum DecodingFailure: Sendable {
        case keyNotFound
        case typeMismatch
        case valueNotFound
        case dataCorrupted
    }

    struct StubCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            return nil
        }
    }

    struct StubError: Error { }
}


// MARK: - Helpers
private extension ToolArgumentErrorTests {
    static let missingKey = StubCodingKey(stringValue: "name")
    static let debugDescription = "Decoding failed."

    func decodingError(for failure: DecodingFailure) -> DecodingError {
        let path: [any CodingKey] = [StubCodingKey(stringValue: "user"), StubCodingKey(stringValue: "age")]
        let context = DecodingError.Context(codingPath: path, debugDescription: Self.debugDescription)

        switch failure {
        case .keyNotFound:
            return .keyNotFound(Self.missingKey, .init(codingPath: [], debugDescription: Self.debugDescription))
        case .typeMismatch:
            return .typeMismatch(Int.self, context)
        case .valueNotFound:
            return .valueNotFound(Int.self, context)
        case .dataCorrupted:
            return .dataCorrupted(context)
        }
    }
}


// MARK: - SUT
private extension ToolArgumentErrorTests {
    func makeSUT(error: ToolArgumentError) -> ToolArgumentError {
        return error
    }
}
