//
//  SchemaDerivable.swift
//  MCPServerKit
//
//  Created by Nikolai Nobadi on 1/29/26.
//

import MCP

public protocol SchemaDerivable {
    static func schema() -> Value
}

public protocol SchemaObjectDerivable {
    static func objectSchema() -> Schema.Field
}
