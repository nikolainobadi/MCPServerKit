import Testing
@testable import MCPServerKit

struct ToolErrorTests {
    @Test(arguments: [
        (StubToolError.readFailed, "sample.read_failed"),
        (StubToolError.timeout, "sample.timeout"),
        (StubToolError.legacyCode, "sample.legacy_code")
    ])
    func `Error code prefixes the snake cased case name with the domain`(error: StubToolError, expectedCode: String) {
        let sut = makeSUT(error: error)

        let payload = sut.toErrorPayload(toolName: "read_profile")

        #expect(payload.code == expectedCode)
    }

    @Test
    func `Error without an override derives its message from the case name`() {
        let sut = makeSUT(error: .readFailed)

        let payload = sut.toErrorPayload(toolName: "read_profile")

        #expect(payload.message == "Read Failed")
    }

    @Test
    func `Error with an override uses the override as its message`() {
        let sut = makeSUT(error: .notFound)

        let payload = sut.toErrorPayload(toolName: "read_profile")

        #expect(payload.message == StubToolError.notFoundMessage)
    }

    @Test
    func `Error payload details identify the tool that failed`() throws {
        let toolName = "read_profile"
        let sut = makeSUT(error: .readFailed)

        let payload = sut.toErrorPayload(toolName: toolName)

        let details = try #require(payload.details)
        #expect(details == ["tool": toolName])
    }
}


// MARK: - Contextual Details
extension ToolErrorTests {
    @Test
    func `Contextual error keeps the code of the wrapped error`() {
        let sut = makeSUT(error: .readFailed)

        let payload = sut.withDetails(["id": "42"], message: nil).toErrorPayload(toolName: "read_profile")

        #expect(payload.code == "sample.read_failed")
    }

    @Test
    func `Contextual error reports its details alongside the tool name`() throws {
        let toolName = "read_profile"
        let itemID = "42"
        let sut = makeSUT(error: .readFailed)

        let payload = sut.withDetails(["id": itemID], message: nil).toErrorPayload(toolName: toolName)

        let details = try #require(payload.details)
        #expect(details == ["id": itemID, "tool": toolName])
    }

    @Test
    func `Tool name replaces a caller supplied tool detail`() throws {
        let toolName = "read_profile"
        let sut = makeSUT(error: .readFailed)

        let payload = sut.withDetails(["tool": "spoofed"], message: nil).toErrorPayload(toolName: toolName)

        let details = try #require(payload.details)
        #expect(details["tool"] == toolName)
    }

    @Test
    func `Runtime message takes precedence over the case override`() {
        let runtimeMessage = "Item '42' not found."
        let sut = makeSUT(error: .notFound)

        let payload = sut.withDetails(["id": "42"], message: runtimeMessage).toErrorPayload(toolName: "read_profile")

        #expect(payload.message == runtimeMessage)
    }

    @Test
    func `Contextual error without a runtime message falls back to the case override`() {
        let sut = makeSUT(error: .notFound)

        let payload = sut.withDetails(["id": "42"], message: nil).toErrorPayload(toolName: "read_profile")

        #expect(payload.message == StubToolError.notFoundMessage)
    }
}


// MARK: - Test Doubles
extension ToolErrorTests {
    enum StubToolError: String, ToolError {
        static let domain = "sample"
        static let notFoundMessage = "Item not found."

        case readFailed
        case notFound
        case timeout
        case legacyCode = "legacy_code"

        var messageOverride: String? {
            switch self {
            case .notFound:
                return Self.notFoundMessage
            case .readFailed, .timeout, .legacyCode:
                return nil
            }
        }
    }
}


// MARK: - SUT
private extension ToolErrorTests {
    func makeSUT(error: StubToolError) -> StubToolError {
        return error
    }
}
