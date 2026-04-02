//
//  MCPResourceDescriptor.swift
//  MCPServerKit
//
//  Created by Nikolai Nobadi on 1/27/26.
//

import MCP

/// A protocol representing enum-based MCP resource metadata.
///
/// Conforming enums describe the resources they represent without defining read logic.
/// Resource registration and content reading are handled separately by `ResourceModule` and `ResourceRegistrar`.
///
/// - Note: Conforming types must be `CaseIterable` to support automatic resource enumeration
///   and `Sendable` for concurrency safety.
public protocol MCPResourceDescriptor: CaseIterable, Sendable {
    /// The MCP resource URI used for routing.
    var uri: String { get }

    /// The display name of the resource.
    var name: String { get }

    /// A human-readable description of the resource's purpose.
    var description: String { get }

    /// The MIME type of the resource content.
    var mimeType: String { get }
}

// MARK: - Default Implementations
public extension MCPResourceDescriptor {
    /// Constructs an MCP `Resource` from this descriptor's metadata.
    var resource: Resource {
        return .init(name: name, uri: uri, description: description, mimeType: mimeType)
    }
    
    var toolResultContent: Tool.Content {
        return .resource(resource: .text("", uri: uri, mimeType: mimeType))
    }

    /// Initializes a descriptor by looking up a resource URI among all cases.
    ///
    /// - Parameter uri: The resource URI to match.
    /// - Returns: The matching case, or `nil` if no case has that URI.
    init?(uri: String) {
        guard let match = Self.allCases.first(where: { $0.uri == uri }) else {
            return nil
        }
        
        self = match
    }
}
