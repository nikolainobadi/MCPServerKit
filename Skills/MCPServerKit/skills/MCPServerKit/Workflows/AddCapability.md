# Add FeatureCapability Workflow

Adds exactly one `FeatureCapability` to an existing `FeatureModule` in a project that depends on MCPServerKit.

Before generating any code, load the MCPServerKit skill's `ApiReference.md` for protocol signatures.

## Capability Types

| Type | When to Use |
|------|-------------|
| **ReadTool** | Fetches data without modifying state |
| **WriteTool** | Mutates and persists state |
| **ResourceTool** | Tool paired with static reference content via URI |

## Execution Order (Strict)

Follow these steps in order. Do not skip steps.

---

### Step 1: Identify the Target Feature

Determine which existing Feature the capability will be added to.

**Required:**
- Feature name (e.g. `Profile`, `Experience`)
- Manager type name (e.g. `ProfileManager`)

If either is missing, ask the user. Do not read files or generate code.

---

### Step 1a: Feature Existence Validation (Hard Stop)

Verify in the codebase:
- `{FeatureName}Feature` exists
- `{ManagerType}` exists
- `.module(using:) -> FeatureModule` exists

If any are missing, stop and inform the user the feature must be created first.

---

### Step 2: Select Capability Type

Determine which pattern applies: **ReadTool**, **WriteTool**, or **ResourceTool**.

**Required:**
- Capability type (Read, Write, or Resource)
- Capability name (e.g. `ProfileRead`, `ExperienceWrite`)
- Plain-English intent description

If missing, ask the user. Load the pattern file for the selected type:
- **ReadTool**: `ReadToolPattern.md`
- **WriteTool**: `WriteToolPattern.md`
- **ResourceTool**: `ResourceToolPattern.md`

---

### Step 3: Define the Tool Surface

Determine the MCP tools exposed by this capability.

**Required per tool:**
- Tool name (snake_case)
- Read-only or mutating
- High-level behavior
- Arguments (if any)

Do not infer tools, arguments, or schemas. If missing, ask the user.

---

### Step 4: Generate MCPToolDescriptor

Using the tool surface from Step 3, generate one `MCPToolDescriptor` enum.

- Set annotations based on capability type (see the loaded pattern file)
- Generate schemas only for explicitly declared arguments
- If arguments are unclear, stop and ask one focused question

---

### Step 5: Define Protocol Dependencies

Determine how the ToolHandler delegates work.

**Required:**
- Whether to create a new protocol or reuse an existing one
- Protocol method signatures matching declared tools

Rules: protocols only, no concrete implementations, no persistence logic.

If missing, ask the user.

---

### Step 6: Generate ToolHandler

Generate the ToolHandler struct following the selected pattern file.

- Depend only on protocol(s)
- Decode arguments using `ToolHandlerHelpers`
- Delegate work to protocol
- Encode results

No business logic, no file system access, no concrete services.

---

### Step 7: Wire FeatureCapability

Append exactly one `FeatureCapability` to the target `FeatureModule`.

- Preserve existing capability ordering
- Do not modify other capabilities
- For ResourceTool, also generate the ResourceDescriptor and ResourceModule, then pass resources to `.init(handler:resources:)`

See the loaded pattern file for wiring syntax.

---

## Folder Structure Convention

Place new files under the Feature's `Capabilities/` directory:

```
{FeatureName}/Capabilities/
  {CapabilityName}/                    # ReadTool or WriteTool
    {CapName}ToolDescriptor.swift
    {CapName}ToolHandler.swift
    {ArgumentsType}.swift              # WriteTool only, if needed

  {CapabilityName}/                    # ResourceTool
    Tool/
      {CapName}ToolDescriptor.swift
      {CapName}ToolHandler.swift
    Resource/
      {CapName}ResourceDescriptor.swift
      {CapName}ResourceModule.swift
      {CapName}Rules.swift             # Static content, if needed
```

## References

- For MCPServerKit protocol signatures and Schema API: `ApiReference.md`
- For code templates: `ReadToolPattern.md`, `WriteToolPattern.md`, `ResourceToolPattern.md`
- For canonical constraints and rules: `Reference.md`
