# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**MCPServerKit** is a Swift package for building local MCP (Model Context Protocol) servers on top of the official [swift-sdk](https://github.com/modelcontextprotocol/swift-sdk). Clients describe tools, resources, and prompts as `CaseIterable` descriptor enums, implement the domain logic in handler/module conformers, group them into `FeatureCapability` / `FeatureModule` values, and hand those to `LocalMCPServer`, which registers everything and serves over stdio.

## Build & Test Commands

```bash
swift build
swift test
```

`.github/workflows/ci.yml` runs these commands for pull requests targeting `main`, using macOS 15 and Xcode 26.3.

## Architecture

```
LocalMCPServer                  // wiring + stdio transport + ServiceLifecycle shutdown
  └── [FeatureModule]           // one per domain
        └── [FeatureCapability] // one per workflow
              ├── ToolHandler       (MCPToolDescriptor)
              ├── [ResourceModule]  (MCPResourceDescriptor)
              └── [PromptModule]    (MCPPromptDescriptor)
```

- `ToolRegistrar` / `ResourceRegistrar` / `PromptRegistrar` (internal) register one list handler and one call/read/get handler each, routing by name or URI. Duplicate names/URIs are a `preconditionFailure`.
- `MCPLifecycleService` starts the server and waits for completion without sending tool, resource, or prompt list-change notifications on startup; graceful shutdown stops the server.
- Errors escaping a tool should conform to `ToolErrorConvertible`. `CancellationError` and `MCPError` are rethrown to the SDK; anything else is logged and returned as an `isError` result with code `internal.unhandled`. `ToolError` gives domain-prefixed snake_case codes.
- `InitializeSanitizingTransport` (internal) wraps `StdioTransport` and removes client `experimental` capabilities from `initialize`, because swift-sdk 0.12.1 can't decode object values. Delete it once a swift-sdk release includes [PR #276](https://github.com/modelcontextprotocol/swift-sdk/pull/276).
- `Exports.swift` re-exports `MCP`, so consumers only `import MCPServerKit`.

## Development Notes

- Swift 6.0+, macOS 15+ (see Package.swift)
- Depends on `swift-sdk` (MCP) and `swift-service-lifecycle`

## Claude Code Skill

The API reference skill for this package lives here, in `Skills/MCPServerKit/`, and is served by the public `nn-swift-skills` marketplace as `MCPServerKit@nn-swift-skills`. It was moved out of `NobadiScripts` so the API and its documentation change together: **any PR that changes the public API must update `Skills/MCPServerKit/` in the same PR.**

- `Skills/` is not a SwiftPM target; it ships only through the marketplace.
- The skill covers API reference; server structure and scaffolding belong to `nn-mcp-architecture`, which uses `nnscaffold` to create servers, features, and capabilities.
- `Skills/MCPServerKit/.claude-plugin/plugin.json` carries a `version` that the release tooling sets to the release tag. Claude Code keys its plugin cache on that version, so it must match the tag the marketplace `ref` points at; a release that moves the tag without the version can keep serving the previous cached docs.
- Code in `Examples.md` and `ResourceToolPattern.md` is what consumers copy. When the API or the swift-sdk dependency changes, re-check that those snippets still compile.

## Releasing

The `nn-swift-skills` entry for this skill is pinned to a release tag (`ref`), not to a branch. **Skill changes reach users when a release is tagged, not when they merge.** A doc fix merged to `main` is invisible until the next tag.

The marketplace ref bump is manual: this repository has no tag-triggered workflow to update the entry in `nikolainobadi/nn-swift-skills`. Update that entry's `ref` to the release tag so the marketplace serves the matching docs.
