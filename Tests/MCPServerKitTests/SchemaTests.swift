import Testing
@testable import MCPServerKit

struct SchemaTests {
    @Test
    func `Object schema declares the object type`() throws {
        let sut = makeSUT()

        let schema = try #require(sut.object(["name": .optional(.string(description: nil, nullable: false))]).objectValue)

        #expect(schema["type"] == .string("object"))
    }

    @Test
    func `Object schema lists only required properties as required`() throws {
        let sut = makeSUT()

        let schema = try #require(sut.object([
            "name": .required(.string(description: nil, nullable: false)),
            "nickname": .optional(.string(description: nil, nullable: false))
        ]).objectValue)

        #expect(schema["required"] == .array([.string("name")]))
    }

    @Test
    func `Object schema lists every required property`() throws {
        let sut = makeSUT()

        let schema = try #require(sut.object([
            "name": .required(.string(description: nil, nullable: false)),
            "age": .required(.int(description: nil, minimum: nil, maximum: nil, nullable: false)),
            "nickname": .optional(.string(description: nil, nullable: false))
        ]).objectValue)

        let required = try #require(schema["required"]?.arrayValue)
        #expect(Set(required.compactMap(\.stringValue)) == ["name", "age"])
    }

    @Test
    func `Object schema without required properties omits the required list`() throws {
        let sut = makeSUT()

        let schema = try #require(sut.object(["nickname": .optional(.string(description: nil, nullable: false))]).objectValue)

        #expect(schema["required"] == nil)
    }

    @Test
    func `Object schema includes every declared property`() throws {
        let sut = makeSUT()

        let schema = try #require(sut.object([
            "name": .required(.string(description: nil, nullable: false)),
            "nickname": .optional(.string(description: nil, nullable: false))
        ]).objectValue)

        let properties = try #require(schema["properties"]?.objectValue)
        #expect(Set(properties.keys) == ["name", "nickname"])
    }
}


// MARK: - Field Types
extension SchemaTests {
    @Test
    func `String field without options declares only its type`() throws {
        let sut = makeSUT()

        let property = try property(of: .string(description: nil, nullable: false), in: sut)

        #expect(property == .object(["type": .string("string")]))
    }

    @Test
    func `String field includes its description and nullability`() throws {
        let description = "The user's name"
        let sut = makeSUT()

        let property = try property(of: .string(description: description, nullable: true), in: sut)

        #expect(property == .object(["type": .string("string"), "description": .string(description), "nullable": .bool(true)]))
    }

    @Test
    func `Bool field declares the boolean type with its description`() throws {
        let description = "Use formal greeting"
        let sut = makeSUT()

        let property = try property(of: .bool(description: description), in: sut)

        #expect(property == .object(["type": .string("boolean"), "description": .string(description)]))
    }

    @Test
    func `Int field declares the integer type with its bounds`() throws {
        let sut = makeSUT()

        let property = try property(of: .int(description: nil, minimum: 0, maximum: 150, nullable: true), in: sut)

        #expect(property == .object(["type": .string("integer"), "minimum": .int(0), "maximum": .int(150), "nullable": .bool(true)]))
    }

    @Test
    func `Double field declares the number type with its bounds`() throws {
        let sut = makeSUT()

        let property = try property(of: .double(description: nil, minimum: 0.5, maximum: 9.5, nullable: false), in: sut)

        #expect(property == .object(["type": .string("number"), "minimum": .double(0.5), "maximum": .double(9.5)]))
    }

    @Test
    func `Array field describes its item schema`() throws {
        let description = "Optional tags"
        let sut = makeSUT()

        let property = try property(of: .array(of: .string(description: nil, nullable: false), description: description), in: sut)

        #expect(property == .object([
            "type": .string("array"),
            "items": .object(["type": .string("string")]),
            "description": .string(description)
        ]))
    }

    @Test
    func `Nested object field carries its own required list`() throws {
        let sut = makeSUT()

        let property = try property(of: .object(["street": .required(.string(description: nil, nullable: false))]), in: sut)

        #expect(property == .object([
            "type": .string("object"),
            "properties": .object(["street": .object(["type": .string("string")])]),
            "required": .array([.string("street")])
        ]))
    }
}


// MARK: - Helpers
private extension SchemaTests {
    func property(of field: Schema.Field, in sut: Schema.Type) throws -> Value {
        let schema = try #require(sut.object(["field": .required(field)]).objectValue)
        let properties = try #require(schema["properties"]?.objectValue)
        return try #require(properties["field"])
    }
}


// MARK: - SUT
private extension SchemaTests {
    func makeSUT() -> Schema.Type {
        return Schema.self
    }
}
