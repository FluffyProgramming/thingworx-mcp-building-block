# ThingWorx MCP Building Block

A ThingWorx 10.1 extension that turns ThingWorx services into [Model Context
Protocol](https://modelcontextprotocol.io/) (MCP) tools, callable by any MCP
client (Claude, other LLM agents, etc.) via ThingWorx 10.1's native MCP
support (`Resources["MCPServices"]`).

Add a service to one ThingShape, run the build script, and it shows up as a
tool an AI agent can call against your live ThingWorx server — no separate
MCP server process, no hand-written tool schemas.

## How it works

```
Management_TS.xml (source of truth for services)
        │  build script: regenerate config
        ▼
EntryPoint.xml → ConfigurationTables → ToolsConfiguration (checked into repo)
        │  runtime: EntryPoint.RegisterTools service
        ▼
Resources["MCPServices"].AddTools(toolInfo: <InfoTable>)
```

- **`Management_TS`** (`ThingShapes/VPS.Development.MCP.Management_TS.xml`) —
  a `ThingShape` holding every service you want exposed as an MCP tool.
  Services (and their default implementations) live here, not on any
  individual `Thing`.
- **`Manager`** (`Things/VPS.Development.MCP.Manager.xml`) — implements
  `Management_TS` (via `Manager_TT`) and is the live instance whose services
  actually get invoked.
- **`EntryPoint`** (`Things/VPS.Development.MCP.EntryPoint.xml`) — reads the
  services on `Management_TS`, generates a `ToolsConfiguration` config table
  describing each one (name, description, JSON Schema for inputs/outputs),
  and registers them with ThingWorx's `MCPServices` on start.
- **`scripts/Build.ps1`** — regenerates `ToolsConfiguration` from
  `Management_TS`'s current `ServiceDefinition`s and packages the whole thing
  into an importable ThingWorx extension zip.

## What's included

The extension currently ships one working MCP tool as a reference
implementation:

- **`ImportEntityZip`** — uploads a base64-encoded zip of ThingWorx
  source-control entity XML into `SystemRepository`, extracts it, and
  imports the entities into the running server. Lets an MCP-connected agent
  push entity changes straight into a live ThingWorx instance in one call.

## Repository layout

```
DataShapes/        DataShape entity XML
Groups/             User group entity XML
Organizations/       Organization entity XML
Projects/            Project entity XML
Things/               Thing entity XML (EntryPoint, Manager)
ThingShapes/           ThingShape entity XML (Management_TS)
ThingTemplates/         ThingTemplate entity XML
scripts/                 PowerShell build pipeline + Pester tests
docs/                     Design docs and implementation plans
```

Entity XML files are the source of truth — they're hand-authored/edited
directly (not solely round-tripped through Composer export), so formatting
in each file matches Composer's own conventions as closely as possible.

## Building

Requires PowerShell and [Pester](https://pester.dev/) 3.4.0 for the test
suite.

```powershell
# Run the build: regenerates ToolsConfiguration and packages the extension
./scripts/Build.ps1

# Run the test suite
Invoke-Pester -Path scripts/tests
```

Build output lands in `dist/VPS.Development.MCP-extension-<version>.zip`.

## Installing

1. Build the extension zip (above), or download one from a release.
2. In ThingWorx Composer: **Import/Export → Import → Extension**, upload the
   zip.
3. Enable the `VPS.Development.MCP.EntryPoint` Thing. On start, it registers
   every service on `Management_TS` as an MCP tool automatically.
4. Point your MCP client at the ThingWorx server's MCP endpoint to start
   calling the registered tools.

## Adding a new tool

1. Add a `ServiceDefinition` (and implementation) to `Management_TS`.
2. Re-run `scripts/Build.ps1` to regenerate `ToolsConfiguration` and
   re-package the extension.
3. Re-import and re-enable `EntryPoint` — the new service appears as an MCP
   tool with no additional wiring.

## Requirements

- ThingWorx 10.1+
- No dependency on PTC's Solution Framework — entities use
  `baseThingTemplate="GenericThing"`, so this imports cleanly into any
  ThingWorx 10.1 system.
