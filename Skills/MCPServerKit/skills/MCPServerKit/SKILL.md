---
name: MCPServerKit
description: MCPServerKit Swift API reference for building MCP servers. USE WHEN using MCPServerKit, LocalMCPServer, FeatureModule, FeatureCapability, MCPToolDescriptor, ToolHandler, ToolHandlerHelpers, Schema, SchemaDerivable, ToolError, ToolErrorConvertible, MCPResourceDescriptor, ResourceModule, MCPPromptDescriptor, PromptModule, OR looking up a signature, schema, annotation, or error API while writing a Swift MCP server. Not for how a server is structured or for adding a server, feature, or capability: the nn-mcp-architecture skill owns those.
user-invocable: true
---

# MCPServerKit

Swift framework for building MCP servers. Built on top of the [swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) MCP package.

This skill is the API reference. How a server is laid out, where each type lives, and how servers, features, and capabilities are created belong to the **nn-mcp-architecture** skill, which generates them with `nnscaffold`. If that skill is not loaded and the request is to create or extend a server, install it with `claude plugin install nn-mcp-architecture@nn-swift-skills`, then continue there.

## Dependency

```swift
.package(url: "https://github.com/nikolainobadi/MCPServerKit.git", from: "0.1.1")
```

**Requirements:** Swift 6.0+, macOS 15+

`import MCPServerKit` re-exports the MCP SDK (`Value`, `Tool`, `CallTool`, `Resource`, `Prompt`, and so on), so no separate `import MCP` is needed.

## Architecture

```
LocalMCPServer
  └── [FeatureModule]           // one per domain (e.g., Profile, Projects)
        └── [FeatureCapability]  // one per workflow
              ├── ToolHandler    // required: handles the tools of one MCPToolDescriptor enum
              ├── [ResourceModule]  // optional: static content via MCPResourceDescriptor enum
              └── [PromptModule]    // optional: prompt templates via MCPPromptDescriptor enum
```

## Composition Pattern

Each layer uses enum-based descriptors for metadata and protocol conformers for behavior:

- **MCPToolDescriptor** enum: defines tool name, description, inputSchema, annotations
- **ToolHandler**: receives the resolved descriptor, decodes arguments, calls its dependency, and encodes the result
- **MCPResourceDescriptor** enum: defines resource URI, name, description, mimeType
- **ResourceModule**: reads content for a resolved resource
- **MCPPromptDescriptor** enum: defines prompt name, description, arguments
- **PromptModule**: returns prompt result for a resolved prompt

All descriptor enums must be `CaseIterable` and `Sendable`.

## Key Conventions

- One descriptor enum per handler (don't share descriptors across handlers)
- Use `Schema.object()` with `Schema.RequiredSchema` for tool inputSchema; use `Schema.object([:])` when there are no arguments
- Use `ToolHandlerHelpers` methods for argument extraction (requireString, optionalString, etc.)
- Keep tool names, resource URIs, and prompt names unique across all features; duplicates fail registration
- Errors escaping tool boundaries should conform to `ToolErrorConvertible`; translate dependency errors before they escape, so clients receive domain-specific codes instead of `internal.unhandled`. Let `CancellationError` and `MCPError` propagate to the SDK (see `ApiReference.md`)
- `ToolError` protocol provides declarative, domain-prefixed error codes

## Context Files

| File | Purpose | Load When |
|------|---------|-----------|
| `ApiReference.md` | Protocol signatures, Schema API, error handling | Writing any descriptor, handler, schema, module, or error |
| `Examples.md` | Short examples of each API | Seeing how a protocol is conformed to |
| `ResourceToolPattern.md` | Tool paired with a resource module | Writing a capability backed by an MCP resource |

## Quick Reference

| Component | Protocol | Descriptor |
|-----------|----------|------------|
| Tools | `ToolHandler` | `MCPToolDescriptor` |
| Resources | `ResourceModule` | `MCPResourceDescriptor` |
| Prompts | `PromptModule` | `MCPPromptDescriptor` |
| Errors | `ToolError` | none |
| Schema | `Schema.object()` | `Schema.Field` |

## Examples

- "How do I conform to ToolHandler?" → Load `Examples.md`
- "Define tool input schema" → Load `ApiReference.md` for Schema API
- "Handle errors from tools" → Load `ApiReference.md` for ToolError protocol
- "Add a tool that serves a resource" → Load `ResourceToolPattern.md`, after nn-mcp-architecture has settled where it goes
- "Create a server" or "add a read tool" → nn-mcp-architecture
