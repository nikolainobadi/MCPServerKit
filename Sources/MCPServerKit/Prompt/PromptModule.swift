//
//  PromptModule.swift
//  MCPServerKit
//
//  Created by Nikolai Nobadi on 1/25/26.
//

import MCP

/// A protocol representing a logical group of MCP prompts.
///
/// Conforming types declare the prompts they own and handle prompt retrieval.
/// Prompt registration and routing are handled by `PromptRegistrar`.
///
/// The associated `PromptType` enum describes the prompts this module owns.
/// Default implementations derive the `prompts` array and provide a `resolvePrompt` helper.
public protocol PromptModule: Sendable {
    /// The enum type describing the prompts owned by this module.
    associatedtype PromptType: MCPPromptDescriptor

    /// The prompts owned by this module.
    var prompts: [Prompt] { get }

    /// Returns the prompt result for a resolved prompt.
    ///
    /// - Parameters:
    ///   - prompt: The resolved prompt descriptor.
    ///   - arguments: Optional arguments passed to the prompt.
    /// - Returns: The prompt result containing description and messages.
    func prompt(_ prompt: PromptType, arguments: [String: String]?) -> GetPrompt.Result

    /// Returns the prompt result for a given prompt name and arguments.
    ///
    /// This method is only invoked when `PromptRegistrar` has determined that
    /// this module owns the requested prompt based on declared prompt names.
    ///
    /// - Parameters:
    ///   - name: The name of the prompt.
    ///   - arguments: Optional arguments passed to the prompt.
    /// - Returns: The prompt result containing description and messages.
    func getPrompt(name: String, arguments: [String: String]?) -> GetPrompt.Result
}

// MARK: - Default Implementations
public extension PromptModule {
    /// The prompts owned by this module, derived from `PromptType.allCases`.
    var prompts: [Prompt] {
        return PromptType.allCases.map(\.prompt)
    }

    /// Resolves a prompt name to its corresponding `PromptType` case.
    ///
    /// - Parameter name: The prompt name to resolve.
    /// - Returns: The matching `PromptType` case.
    ///
    /// - Precondition: `PromptRegistrar` guarantees that this method is only called
    ///   with names owned by this module. A mismatch indicates a programmer error.
    func resolvePrompt(from name: String) -> PromptType {
        guard let prompt = PromptType(name: name) else {
            fatalError("PromptRegistrar routed unknown name '\(name)' to \(Self.self)")
        }
        
        return prompt
    }

    /// Default implementation that resolves the name and delegates to `prompt(_:arguments:)`.
    func getPrompt(name: String, arguments: [String: String]?) -> GetPrompt.Result {
        let prompt = resolvePrompt(from: name)
        
        return self.prompt(prompt, arguments: arguments)
    }
}
