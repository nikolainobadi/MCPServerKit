# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**MCPServerKit** is a Swift package for building local MCP (Model Context Protocol) servers on top of the official [swift-sdk](https://github.com/modelcontextprotocol/swift-sdk). Clients describe tools, resources, and prompts as `CaseIterable` descriptor enums, implement the domain logic in handler/module conformers, group them into `FeatureCapability` / `FeatureModule` values, and hand those to `LocalMCPServer`, which registers everything and serves over stdio.

## Build & Test Commands

```bash
swift build
swift test
```

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
- Errors escaping a tool must conform to `ToolErrorConvertible`; anything else is a `fatalError`. `ToolError` gives domain-prefixed snake_case codes.
- `Exports.swift` re-exports `MCP`, so consumers only `import MCPServerKit`.

## Development Notes

- Swift 6.0+, macOS 15+ (see Package.swift)
- Depends on `swift-sdk` (MCP) and `swift-service-lifecycle`

## Claude Code Skill

The API reference skill for this package lives here, in `Skills/MCPServerKit/`, and is served by the public `nn-swift-skills` marketplace as `MCPServerKit@nn-swift-skills`. It was moved out of `NobadiScripts` so the API and its documentation change together: **any PR that changes the public API must update `Skills/MCPServerKit/` in the same PR.**

- `Skills/` is not a SwiftPM target; it ships only through the marketplace.
- `Skills/MCPServerKit/.claude-plugin/plugin.json` deliberately has **no `version` field**. The marketplace pins the skill to a git tag, and the plugin cache is keyed by commit sha. Do not reintroduce a version; a hand-typed number nothing verifies is the staleness this arrangement removes.
- Code in `Examples.md` and the `*ToolPattern.md` templates is what consumers copy. When the API or the swift-sdk dependency changes, re-check that those snippets still compile.

## Releasing

The `nn-swift-skills` entry for this skill is pinned to a release tag (`ref`), not to a branch. **Skill changes reach users when a release is tagged, not when they merge.** A doc fix merged to `main` is invisible until the next tag.

`.github/workflows/skill-ref-bump.yml` keeps the pin current: on every tag push it rewrites the entry's `ref` in `nikolainobadi/nn-swift-skills` and opens a PR there. If that workflow is ever removed, the bump becomes manual. Forgetting it fails silently — the marketplace keeps serving the previous release's docs forever, with nothing erroring and nothing warning.

The workflow authenticates with the repo secret **`MARKETPLACE_TOKEN`**: a fine-grained PAT named `nn-swift-skills-ref-bump`, scoped to `nn-swift-skills` only (Contents and Pull requests, read and write), **expiring 2027-08-15**. It is shared with every other package repo publishing to that marketplace, so rotating it means re-setting the secret in each of them. When it expires, the workflow fails on tag push; treat that as "rotate the shared token", not "this repo's workflow is broken."
