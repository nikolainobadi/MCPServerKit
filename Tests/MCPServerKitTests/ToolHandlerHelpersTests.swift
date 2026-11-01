import Testing
@testable import MCPServerKit

struct ToolHandlerHelpersTests {
    @Test
    func `Required string returns the provided text`() throws {
        let name = "Ada"
        let sut = makeSUT()

        let value = try sut.requireString(["name": .string(name)], key: "name")

        #expect(value == name)
    }

    @Test(arguments: [nil, ["name": Value.int(7)], ["other": Value.string("Ada")]])
    func `Required string rejects a missing or non text argument`(arguments: [String: Value]?) throws {
        let sut = makeSUT()

        let error = #expect(throws: ToolArgumentError.self) {
            try sut.requireString(arguments, key: "name")
        }

        let thrown = try #require(error)
        guard case .missingOrInvalid(let key) = thrown else {
            Issue.record("Expected missingOrInvalid, got \(thrown)")
            return
        }
        #expect(key == "name")
    }

    @Test
    func `Optional string returns the provided text`() {
        let name = "Ada"
        let sut = makeSUT()

        let value = sut.optionalString(["name": .string(name)], key: "name")

        #expect(value == name)
    }

    @Test
    func `Optional string is absent when the argument is missing`() {
        let sut = makeSUT()

        let value = sut.optionalString(["other": .string("Ada")], key: "name")

        #expect(value == nil)
    }

    @Test(arguments: [true, false])
    func `Required bool returns the provided flag`(flag: Bool) throws {
        let sut = makeSUT()

        let value = try sut.requireBool(["formal": .bool(flag)], key: "formal")

        #expect(value == flag)
    }

    @Test
    func `Required bool rejects a non boolean argument`() {
        let sut = makeSUT()

        #expect(throws: ToolArgumentError.self) {
            try sut.requireBool(["formal": .string("true")], key: "formal")
        }
    }
}


// MARK: - Integer Conversion
extension ToolHandlerHelpersTests {
    @Test(arguments: [Value.int(3), Value.double(3.0)])
    func `Whole numbers convert to integers`(value: Value) {
        let sut = makeSUT()

        #expect(sut.intValue(from: value) == 3)
    }

    @Test(arguments: [Value.double(2.5), Value.string("3"), Value.null])
    func `Fractional and non numeric values do not convert to integers`(value: Value) {
        let sut = makeSUT()

        #expect(sut.intValue(from: value) == nil)
    }

    @Test
    func `Absent values do not convert to integers`() {
        let sut = makeSUT()

        #expect(sut.intValue(from: nil) == nil)
    }
}


// MARK: - Argument Decoding
extension ToolHandlerHelpersTests {
    @Test
    func `Arguments decode into the requested type`() throws {
        let title = "Notebook"
        let count = 2
        let sut = makeSUT()

        let decoded = try sut.decodeArguments(ItemArguments.self, from: ["title": .string(title), "count": .int(count)])

        #expect(decoded == ItemArguments(title: title, count: count))
    }

    @Test
    func `Absent arguments decode as an empty object`() throws {
        let sut = makeSUT()

        let decoded = try sut.decodeArguments(OptionalArguments.self, from: nil)

        #expect(decoded.note == nil)
    }

    @Test
    func `Arguments that do not match the type throw a decoding error`() throws {
        let sut = makeSUT()

        let error = #expect(throws: ToolArgumentError.self) {
            try sut.decodeArguments(ItemArguments.self, from: ["title": .string("Notebook")])
        }

        let thrown = try #require(error)
        guard case .decodingError = thrown else {
            Issue.record("Expected decodingError, got \(thrown)")
            return
        }
    }
}


// MARK: - Payload Encoding
extension ToolHandlerHelpersTests {
    @Test
    func `Compact payload is single line JSON with sorted keys`() {
        let sut = makeSUT()

        let text = sut.encodePayload(ItemArguments(title: "Notebook", count: 2), formatting: .compact)

        #expect(text == #"{"count":2,"title":"Notebook"}"#)
    }

    @Test
    func `Pretty printed payload is indented JSON with sorted keys`() {
        let sut = makeSUT()

        let text = sut.encodePayload(ItemArguments(title: "Notebook", count: 2), formatting: .prettyPrinted)

        #expect(text == "{\n  \"count\" : 2,\n  \"title\" : \"Notebook\"\n}")
    }

    @Test
    func `Unencodable payload produces a fallback error message`() {
        let sut = makeSUT()

        let text = sut.encodePayload(Double.infinity, formatting: .compact)

        #expect(text == #"{"message":"Failed to encode payload"}"#)
    }
}


// MARK: - Test Doubles
extension ToolHandlerHelpersTests {
    struct StubHelpers: ToolHandlerHelpers { }

    struct ItemArguments: Codable, Equatable {
        let title: String
        let count: Int
    }

    struct OptionalArguments: Decodable {
        let note: String?
    }
}


// MARK: - SUT
private extension ToolHandlerHelpersTests {
    func makeSUT() -> StubHelpers {
        return StubHelpers()
    }
}
