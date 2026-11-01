import Testing
@testable import MCPServerKit

struct MCPToolDescriptorTests {
    @Test
    func `Lookup by name finds the matching case`() {
        let sut = makeSUT()

        #expect(sut.init(name: "farewell_user") == .farewell)
    }

    @Test
    func `Lookup by an unknown name finds nothing`() {
        let sut = makeSUT()

        #expect(sut.init(name: "missing_tool") == nil)
    }
}


// MARK: - Built Tool
extension MCPToolDescriptorTests {
    @Test
    func `Built tool carries the descriptor name`() {
        let descriptor = makeSUT().greet

        #expect(descriptor.tool.name == descriptor.name)
    }

    @Test
    func `Built tool carries the descriptor description`() {
        let descriptor = makeSUT().greet

        #expect(descriptor.tool.description == descriptor.description)
    }

    @Test
    func `Built tool carries the descriptor input schema`() {
        let descriptor = makeSUT().greet

        #expect(descriptor.tool.inputSchema == descriptor.inputSchema)
    }

    @Test
    func `Built tool carries the descriptor annotations`() {
        let descriptor = makeSUT().greet

        #expect(descriptor.tool.annotations == descriptor.annotations)
    }
}


// MARK: - Test Doubles
extension MCPToolDescriptorTests {
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

        var description: String? { "Talks to \(name)" }
        var inputSchema: Value { Schema.object(["name": .required(.string(description: nil, nullable: false))]) }
        var annotations: Tool.Annotations { .init(title: name, readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false) }
    }
}


// MARK: - SUT
private extension MCPToolDescriptorTests {
    func makeSUT() -> StubToolDescriptor.Type {
        return StubToolDescriptor.self
    }
}
