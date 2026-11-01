import Testing
@testable import MCPServerKit

struct MCPResourceDescriptorTests {
    @Test
    func `Lookup by URI finds the matching case`() {
        let sut = makeSUT()

        #expect(sut.init(uri: "docs://guides/api") == .apiDocs)
    }

    @Test
    func `Lookup by an unknown URI finds nothing`() {
        let sut = makeSUT()

        #expect(sut.init(uri: "docs://missing") == nil)
    }
}


// MARK: - Built Resource
extension MCPResourceDescriptorTests {
    @Test
    func `Built resource carries the descriptor URI`() {
        let descriptor = makeSUT().styleGuide

        #expect(descriptor.resource.uri == descriptor.uri)
    }

    @Test
    func `Built resource carries the descriptor name`() {
        let descriptor = makeSUT().styleGuide

        #expect(descriptor.resource.name == descriptor.name)
    }

    @Test
    func `Built resource carries the descriptor description`() {
        let descriptor = makeSUT().styleGuide

        #expect(descriptor.resource.description == descriptor.description)
    }

    @Test
    func `Built resource carries the descriptor MIME type`() {
        let descriptor = makeSUT().styleGuide

        #expect(descriptor.resource.mimeType == descriptor.mimeType)
    }

    @Test
    func `Tool result content embeds a reference to the resource`() {
        let descriptor = makeSUT().styleGuide

        #expect(descriptor.toolResultContent == .resource(resource: .text("", uri: descriptor.uri, mimeType: descriptor.mimeType)))
    }
}


// MARK: - Test Doubles
extension MCPResourceDescriptorTests {
    enum StubResource: CaseIterable, MCPResourceDescriptor {
        case styleGuide
        case apiDocs

        var uri: String {
            switch self {
            case .styleGuide:
                return "docs://guides/style"
            case .apiDocs:
                return "docs://guides/api"
            }
        }

        var name: String {
            switch self {
            case .styleGuide:
                return "Style Guide"
            case .apiDocs:
                return "API Docs"
            }
        }

        var description: String { "About \(name)" }
        var mimeType: String { "text/markdown" }
    }
}


// MARK: - SUT
private extension MCPResourceDescriptorTests {
    func makeSUT() -> StubResource.Type {
        return StubResource.self
    }
}
