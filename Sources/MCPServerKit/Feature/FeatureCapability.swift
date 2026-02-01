//
//  FeatureCapability.swift
//  MCPServerKit
//
//  Created by Nikolai Nobadi on 1/25/26.
//

/// Groups related tools, resources, and prompts for a single workflow.
/// Capabilities are composition-time constructs that enable safe deletion of related MCP artifacts.
public struct FeatureCapability {
    public let tool: any ToolModule
    public let resources: [any ResourceModule]
    public let prompts: [any PromptModule]
    
    public init<Handler: ToolHandler>(handler: Handler, resources: [any ResourceModule] = [], prompts: [any PromptModule] = []) {
        self.tool = ToolModuleAdapter(handler: handler)
        self.resources = resources
        self.prompts = prompts
    }
}
