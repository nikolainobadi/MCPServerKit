//
//  Schema.swift
//  MCPServerKit
//
//  Created by Nikolai Nobadi on 1/29/26.
//

import MCP

public enum Schema {
    public static func object(_ properties: [String: RequiredSchema]) -> Value {
        let unwrappedProperties = properties.mapValues(\.value)
        let requiredKeys = properties
            .filter { $0.value.isRequired }
            .map(\.key)

        return object(unwrappedProperties, required: requiredKeys)
    }
}

// MARK: - Field
extension Schema {
    public indirect enum Field {
        case object([String: RequiredSchema])
        case bool(description: String? = nil)
        case array(of: Field, description: String? = nil)
        case string(description: String? = nil, nullable: Bool = false)
        case int(description: String? = nil, minimum: Int? = nil, maximum: Int? = nil, nullable: Bool = false)
        case double(description: String? = nil, minimum: Double? = nil, maximum: Double? = nil, nullable: Bool = false)

        var value: Value {
            switch self {
            case let .object(properties):
                return Schema.object(properties)
            case let .bool(description):
                return Schema.bool(description)
            case let .string(description, nullable):
                return Schema.string(description, nullable: nullable)
            case let .array(field, description):
                return Schema.array(of: field.value, description: description)
            case let .int(description, minimum, maximum, nullable):
                return Schema.int(description: description, minimum: minimum, maximum: maximum, nullable: nullable)
            case let .double(description, minimum, maximum, nullable):
                return Schema.double(description: description, minimum: minimum, maximum: maximum, nullable: nullable)
            }
        }
    }
}

// MARK: - RequiredSchema
extension Schema {
    public enum RequiredSchema {
        case required(Field)
        case optional(Field)

        var value: Value {
            switch self {
            case .required(let field), .optional(let field):
                return field.value
            }
        }

        var isRequired: Bool {
            switch self {
            case .required:
                return true
            case .optional:
                return false
            }
        }
    }
}

// MARK: - Private Methods
private extension Schema {
    static func object(_ properties: [String: Value], required: [String]? = nil) -> Value {
        var payload: [String: Value] = [
            "type": .string("object"),
            "properties": .object(properties)
        ]

        if let required, !required.isEmpty {
            payload["required"] = .array(required.map { .string($0) })
        }

        #if DEBUG
        assert(payload["type"]?.stringValue == "object", "Schema.object must declare type: object.")
        assert(payload["properties"] != nil, "Schema.object must include properties.")
        #endif

        return .object(payload)
    }
    
    static func string(_ description: String? = nil, nullable: Bool = false) -> Value {
        var payload: [String: Value] = [
            "type": .string("string")
        ]

        if let description {
            payload["description"] = .string(description)
        }

        if nullable {
            payload["nullable"] = .bool(true)
        }

        return .object(payload)
    }

    static func bool(_ description: String? = nil) -> Value {
        var payload: [String: Value] = [
            "type": .string("boolean")
        ]

        if let description {
            payload["description"] = .string(description)
        }

        return .object(payload)
    }

    static func array(of itemSchema: Value, description: String? = nil) -> Value {
        var payload: [String: Value] = [
            "type": .string("array"),
            "items": itemSchema
        ]

        if let description {
            payload["description"] = .string(description)
        }

        return .object(payload)
    }

    static func int(description: String?, minimum: Int?, maximum: Int?, nullable: Bool) -> Value {
        var payload: [String: Value] = [
            "type": .string("integer")
        ]

        if let description {
            payload["description"] = .string(description)
        }

        if let minimum {
            payload["minimum"] = .int(minimum)
        }

        if let maximum {
            payload["maximum"] = .int(maximum)
        }

        if nullable {
            payload["nullable"] = .bool(true)
        }

        return .object(payload)
    }

    static func double(description: String?, minimum: Double?, maximum: Double?, nullable: Bool) -> Value {
        var payload: [String: Value] = [
            "type": .string("number")
        ]

        if let description {
            payload["description"] = .string(description)
        }

        if let minimum {
            payload["minimum"] = .double(minimum)
        }

        if let maximum {
            payload["maximum"] = .double(maximum)
        }

        if nullable {
            payload["nullable"] = .bool(true)
        }

        return .object(payload)
    }
}
