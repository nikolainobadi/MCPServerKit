import MCP

public protocol SchemaDerivable {
    static func schema() -> Value
}

public protocol SchemaObjectDerivable {
    static func objectSchema() -> Schema.Field
}
