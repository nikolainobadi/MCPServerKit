---
name: MCPServerKit
description: MCPServerKit Swift API reference and capability generator for building MCP servers. USE WHEN using MCPServerKit, LocalMCPServer, MCP server implementations, MCP tools, MCP resources, MCP prompts, reviewing existing MCP server code, OR adding new MCP tools, read capabilities, write capabilities, resource-backed capabilities to a Swift MCP server.
user-invocable: true
argument-hint: [feature-name, capability-type]
---

# MCPServerKit

Swift framework for building MCP servers. Built on top of the [swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) MCP package.

## Dependency

```swift
.package(url: "https://github.com/nikolainobadi/MCPServerKit.git", from: "0.1.0")
```

**Requirements:** Swift 6.0+, macOS 15+

`import MCPServerKit` re-exports the MCP SDK (`Value`, `Tool`, `CallTool`, `Resource`, `Prompt`, …) — no separate `import MCP` needed.

## Workflow Routing

| Workflow | Trigger | File |
|----------|---------|------|
| **AddCapability** | "add capability", "add tool", "add read tool", "add write tool", "add resource tool" | `Workflows/AddCapability.md` |

## Architecture

```
LocalMCPServer
  └── [FeatureModule]           // one per domain (e.g., Profile, Projects)
        └── [FeatureCapability]  // one per workflow
              ├── ToolHandler    // required: domain logic via MCPToolDescriptor enum
              ├── [ResourceModule]  // optional: static content via MCPResourceDescriptor enum
              └── [PromptModule]    // optional: prompt templates via MCPPromptDescriptor enum
```

## Composition Pattern

Each layer uses enum-based descriptors for metadata and protocol conformers for logic:

- **MCPToolDescriptor** enum → defines tool name, description, inputSchema, annotations
- **ToolHandler** → receives resolved descriptor, executes domain logic
- **MCPResourceDescriptor** enum → defines resource URI, name, description, mimeType
- **ResourceModule** → reads content for a resolved resource
- **MCPPromptDescriptor** enum → defines prompt name, description, arguments
- **PromptModule** → returns prompt result for a resolved prompt

All descriptor enums must be `CaseIterable` and `Sendable`.

## Key Conventions

- One descriptor enum per handler (don't share descriptors across handlers)
- Use `Schema.object()` with `Schema.RequiredSchema` for tool inputSchema; use `Schema.object([:])` when there are no arguments
- Use `ToolHandlerHelpers` methods for argument extraction (requireString, optionalString, etc.)
- Keep tool names, resource URIs, and prompt names unique across all features; duplicates fail registration
- Errors escaping tool boundaries should conform to `ToolErrorConvertible`; translate dependency errors before they escape, because anything else reaches the client with the generic code `internal.unhandled`
- `ToolError` protocol provides declarative, domain-prefixed error codes

## Context Files

| File | Purpose | Load When |
|------|---------|-----------|
| `ApiReference.md` | Protocol signatures, Schema API, error handling | Implementing any MCP component |
| `Examples.md` | Complete implementation examples | Learning patterns, copy-paste starting points |
| `Reference.md` | Canonical constraints for adding capabilities | Using AddCapability workflow |
| `ReadToolPattern.md` | ReadTool code template | Adding a ReadTool capability |
| `WriteToolPattern.md` | WriteTool code template | Adding a WriteTool capability |
| `ResourceToolPattern.md` | ResourceTool code template | Adding a ResourceTool capability |

## Quick Reference

| Component | Protocol | Descriptor |
|-----------|----------|------------|
| Tools | `ToolHandler` | `MCPToolDescriptor` |
| Resources | `ResourceModule` | `MCPResourceDescriptor` |
| Prompts | `PromptModule` | `MCPPromptDescriptor` |
| Errors | `ToolError` | — |
| Schema | `Schema.object()` | `Schema.Field` |

## Examples

- "How do I create an MCP tool?" → Load `Examples.md` for ToolHandler pattern
- "Define tool input schema" → Load `ApiReference.md` for Schema API
- "Handle errors from tools" → Load `ApiReference.md` for ToolError protocol
- "Add a new capability to my MCP server" → Execute `Workflows/AddCapability.md`
