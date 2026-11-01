# Add FeatureCapability Reference

Canonical process and constraints for adding a single `FeatureCapability` to an existing Feature in an MCPServerKit project.

This reference is **tooling-agnostic** and is shared by any automation that adds capabilities.

---

## Core Principle

Adding a FeatureCapability is an **incremental, explicit, non-inferential operation**.

At no point may tooling:
- Guess intent
- Invent behavior
- Refactor unrelated code
- Perform multiple capability additions in one operation

---

## Hard Constraints

### MUST NOT
- Create a new Feature
- Rename existing types
- Reorder existing FeatureCapabilities
- Modify unrelated files
- Infer tools, schemas, arguments, or behavior
- Implement business logic
- Access persistence or concrete services
- Add more than one FeatureCapability per invocation

### MAY
- Create new Swift files
- Append exactly one FeatureCapability to an existing FeatureModule
- Introduce MCP tool descriptors
- Introduce tool handlers
- Introduce protocol dependencies
- Introduce resource descriptors and modules (ResourceTool only)

---

## Preconditions

Before adding a FeatureCapability, the following **must already exist**:

- `{FeatureName}Feature`
- `{ManagerType}` (manager or equivalent coordinator)
- A `FeatureModule` returned from `.module(using:)`

If any precondition fails, the operation must stop.

---

## Canonical Workflow

The process **must** follow these phases in order.

### Phase 1: Feature Identification
Inputs:
- Feature name
- Manager type name

Validation:
- `{FeatureName}Feature` exists
- `{ManagerType}` exists
- `.module(using:) -> FeatureModule` exists

---

### Phase 2: Capability Type Selection
Inputs:
- Capability type: **ReadTool**, **WriteTool**, or **ResourceTool**
- Capability name
- Plain-English intent

The selected type determines:
- Annotation defaults (read-only vs. destructive)
- Schema complexity (empty vs. structured)
- File structure (flat vs. Tool/Resource subdirectories)
- Wiring syntax (with or without resources)

---

### Phase 3: Tool Surface Definition
Inputs per tool:
- Tool name
- Read-only or mutating
- High-level behavior

Rules:
- Tools must be explicitly declared
- Arguments and schemas are not inferred

---

### Phase 4: MCPToolDescriptor Definition
Rules:
- Exactly one descriptor enum per capability
- Schemas reflect declared arguments only
- No partial descriptors
- Annotations must match the capability type:
  - **ReadTool**: `readOnlyHint: true`, `destructiveHint: false`, `idempotentHint: true`
  - **WriteTool**: `readOnlyHint: false`, `destructiveHint: true`, `idempotentHint: false`
  - **ResourceTool**: `readOnlyHint: true`, `destructiveHint: false`, `idempotentHint: true`

---

### Phase 5: Protocol Dependency Definition
Rules:
- ToolHandlers depend on protocols only
- No concrete implementations
- No persistence logic
- Protocol naming convention:
  - **ReadTool**: `{Name}Reader`
  - **WriteTool**: `{Name}Writer`
  - **ResourceTool**: `{Name}Provider`

---

### Phase 6: ToolHandler + Resource Generation
Rules:
- Decode arguments
- Delegate to protocol
- Encode results
- No business logic
- For **ResourceTool**: also generate ResourceDescriptor, ResourceModule, and static content type

---

### Phase 7: FeatureCapability Wiring
Rules:
- Append exactly one FeatureCapability
- Preserve existing ordering
- Do not modify other capabilities
- Wiring syntax:
  - **ReadTool**: `.init(handler: {Name}ReadToolHandler(reader: manager))`
  - **WriteTool**: `.init(handler: {Name}WriteToolHandler(writer: manager))`
  - **ResourceTool**: `.init(handler: {Name}ToolHandler(provider: manager), resources: [{Name}ResourceModule()])`

---

## Determinism

Given identical inputs, the resulting structure must be identical aside from incidental identifiers.

---

## Non-Goals

This process does not:
- Design domain models
- Implement behavior
- Optimize code
- Perform refactors
- Add multiple capabilities
- Create new Features
