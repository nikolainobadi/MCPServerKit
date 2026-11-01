import MCP

/// A protocol representing a logical group of MCP resources.
///
/// Conforming types declare the resources they own and provide content for those resources.
/// Resource registration and routing are handled by `ResourceRegistrar`.
///
/// The associated `ResourceDescriptor` enum describes the resources this module owns.
/// Default implementations derive the `resources` array and provide a `resolveResource` helper.
public protocol ResourceModule: Sendable {
    /// The enum type describing the resources owned by this module.
    associatedtype ResourceDescriptor: MCPResourceDescriptor

    /// The resources owned by this module.
    var resources: [Resource] { get }

    /// Returns the content for a resource.
    ///
    /// - Parameter resource: The resolved resource descriptor.
    /// - Returns: The content of the resource.
    func read(_ resource: ResourceDescriptor) -> [Resource.Content]

    /// Returns the content for a resource by URI.
    ///
    /// This method is only invoked when `ResourceRegistrar` has determined that
    /// this module owns the requested resource based on declared resource URIs.
    ///
    /// - Parameter uri: The URI of the resource to read.
    /// - Returns: The content of the resource.
    func readContent(for uri: String) -> [Resource.Content]
}

// MARK: - Default Implementations
public extension ResourceModule {
    /// The resources owned by this module, derived from `ResourceType.allCases`.
    var resources: [Resource] {
        return ResourceDescriptor.allCases.map(\.resource)
    }

    /// Resolves a resource URI to its corresponding `ResourceType` case.
    ///
    /// - Parameter uri: The resource URI to resolve.
    /// - Returns: The matching `ResourceType` case.
    ///
    /// - Precondition: `ResourceRegistrar` guarantees that this method is only called
    ///   with URIs owned by this module. A mismatch indicates a programmer error.
    func resolveResource(from uri: String) -> ResourceDescriptor {
        guard let resource = ResourceDescriptor(uri: uri) else {
            fatalError("ResourceRegistrar routed unknown URI '\(uri)' to \(Self.self)")
        }
        
        return resource
    }

    /// Default implementation that resolves the URI and delegates to `read(_:)`.
    func readContent(for uri: String) -> [Resource.Content] {
        let resource = resolveResource(from: uri)
        
        return read(resource)
    }
}
