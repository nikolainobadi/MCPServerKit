import Testing
@testable import MCPServerKit

struct ResourceModuleTests {
    @Test
    func `Module declares one resource per descriptor case`() {
        let sut = makeSUT()

        #expect(sut.resources.map(\.uri) == ["docs://guides/style", "docs://guides/api"])
    }

    @Test
    func `Reading by URI returns the content of the matching resource`() {
        let descriptor = StubResource.apiDocs
        let sut = makeSUT()

        let content = sut.readContent(for: descriptor.uri)

        #expect(content == sut.read(descriptor))
    }
}


// MARK: - Test Doubles
extension ResourceModuleTests {
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

        var description: String { name }
        var mimeType: String { "text/plain" }
    }

    struct StubResourceModule: ResourceModule {
        func read(_ resource: StubResource) -> [Resource.Content] {
            return [.text(resource.name, uri: resource.uri, mimeType: resource.mimeType)]
        }
    }
}


// MARK: - SUT
private extension ResourceModuleTests {
    func makeSUT() -> StubResourceModule {
        return StubResourceModule()
    }
}
