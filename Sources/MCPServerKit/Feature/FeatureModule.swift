//
//  FeatureModule.swift
//  MCPServerKit
//
//  Created by Nikolai Nobadi on 1/25/26.
//

/// Groups related capabilities for a single domain.
/// Provides flattened access to all tools, resources, and prompts for registration.
public struct FeatureModule {
    public let capabilities: [FeatureCapability]
    
    public init(capabilities: [FeatureCapability]) {
        self.capabilities = capabilities
    }
}


// MARK: - Helpers
extension FeatureModule {
    var tools: [any ToolModule] {
        return capabilities.map(\.tool)
    }

    var resources: [any ResourceModule] {
        return capabilities.flatMap(\.resources)
    }

    var prompts: [any PromptModule] {
        return capabilities.flatMap(\.prompts)
    }
}
