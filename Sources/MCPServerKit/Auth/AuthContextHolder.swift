//
//  AuthContextHolder.swift
//  MCPServerKit
//
//  Created by Nikolai Nobadi on 2/10/26.
//

import Foundation

/// Thread-safe mutable holder for the current request's auth context.
///
/// Used by the transport layer to set auth context before message processing,
/// and by the registrar to read it during tool handler invocation.
/// The MCP Server processes messages sequentially, so a single-slot holder
/// is sufficient when paired with the pull-based transport stream.
public final class AuthContextHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var _current: AuthContext?

    public var current: AuthContext? {
        get { lock.withLock { _current } }
        set { lock.withLock { _current = newValue } }
    }

    public init() {}
}
