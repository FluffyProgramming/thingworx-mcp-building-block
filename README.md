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

## Current tools

### `ImportEntityZip`

Uploads a base64-encoded zip of ThingWorx source-control entity XML into
`SystemRepository`, extracts it, and imports the entities into the running
server — upload, extract, and import in a single call.

| Input | Type | Required | Description |
|---|---|---|---|
| `zipContent` | string | yes | Base64-encoded bytes of the zip. The zip must use source-control layout — entity-type folders (`DataShapes/`, `Things/`, etc.) directly at the zip root, forward-slash entry paths. |
| `fileName` | string | yes | Name to give the uploaded file, e.g. `"VPS.zip"`. |
| `folderName` | string | yes | Subfolder under the `SystemRepository` root to upload/extract/import into, e.g. `"vps"`. Rejected if empty or containing `..`, `/`, or `\`. |

| Output | Type | Description |
|---|---|---|
| `result` | string | Human-readable summary of what was imported. On failure, the service throws instead of returning a value. |

Implemented on `Management_TS` (inherited by any `Thing` that implements the
shape, e.g. `Manager`).

### `ExecuteService`

Calls a service on any Thing with the given `params` and returns a
structured JSON result — never throws, even when the target Thing/service
doesn't exist or the call itself fails.

| Input | Type | Required | Description |
|---|---|---|---|
| `thingName` | string | yes | Name of the Thing to call the service on. |
| `serviceName` | string | yes | Name of the service to call on that Thing. |
| `params` | object | yes | Parameter name → value to pass to the target service. Pass `{}` if it takes none. |

| Output | Type | Description |
|---|---|---|
| `result` | object | Always `{ success, result, executionTimeMs, error }`. `result` holds the target service's return value (`InfoTable` rows as an array of objects, dates as ISO strings, scalars as-is); `error` holds a message on failure. Never throws. |

Implemented on `Management_TS`. **Known limitation:** calling a service that
itself does BLOB/binary parameter handling (e.g. `ImportEntityZip`'s own
`SaveBinary` call) through `ExecuteService` doesn't currently work —
ThingWorx's base64-to-BLOB auto-conversion applies to the platform's own
request-binding path, not to nested script-to-script calls. Ordinary
scalar/JSON params are unaffected.

### `GetLogEntries`

Returns application/script log entries from the live server, optionally
filtered by time window, level, and search text. Read-only; throws on
failure (e.g. an invalid `logName`).

| Input | Type | Required | Description |
|---|---|---|---|
| `logName` | string | no | One of `ApplicationLog`, `CommunicationLog`, `ConfigurationLog`, `ScriptLog`, `SecurityLog`. Defaults to `ApplicationLog`. |
| `sinceMinutes` | number | no | Return entries from this many minutes ago through now. Ignored if `startTime`/`endTime` are given. |
| `startTime` | string | no | Explicit ISO 8601 start of the time window. Takes precedence over `sinceMinutes`. |
| `endTime` | string | no | Explicit ISO 8601 end of the time window. Takes precedence over `sinceMinutes`. |
| `search` | string | no | Plain substring to search for in log message content. |
| `level` | string | no | Filter to exactly this level: `ERROR`, `WARN`, `INFO`, or `DEBUG` (case-insensitive). |
| `maxRows` | number | no | Maximum rows to return. Defaults to 50 if omitted, clamped to a minimum of 1 and a maximum of 200. |

| Output | Type | Description |
|---|---|---|
| `result` | array | Array of `{ timestamp, level, source, message }`. Empty array if nothing matched — not an error. Throws on genuine failure (e.g. an invalid `logName`). |

Implemented on `Management_TS`. Note: all inputs above are functionally
optional, but the generated MCP tool schema currently marks every
parameter as required (a pre-existing limitation of this repo's
`ToolsConfigGenerator.psm1`, already true for `ExecuteService`'s `params`)
— pass an empty string/omit-equivalent value if your MCP client requires
sending every listed field.

### `ExportEntities`

Exports a project's entities from the live server as a base64-encoded zip
(the reverse of `ImportEntityZip`), with a manifest of what was included.
Read-only aside from scratch-file cleanup in `SystemRepository`; throws on
failure.

| Input | Type | Required | Description |
|---|---|---|---|
| `projectName` | string | yes | Name of the ThingWorx project to export. No default. |
| `includeDependents` | boolean | no | Whether to include entities the project depends on but doesn't directly contain. Defaults to `true`. |
| `startDate` | string | no | Optional ISO 8601 start bound, for incremental exports. |
| `endDate` | string | no | Optional ISO 8601 end bound, for incremental exports. |

| Output | Type | Description |
|---|---|---|
| `result` | object | `{ zipContent, manifest, entityCount }`. `zipContent` is a base64-encoded zip in the same format `ImportEntityZip` accepts, so the two tools compose. `manifest` is an array of the entity file paths included. `entityCount` is `manifest.length`. Throws on failure (e.g. an invalid `projectName`). |

Implemented on `Management_TS`. Note: `includeDependents`/`startDate`/
`endDate` are functionally optional, but the generated MCP tool schema
currently marks every parameter as required (a pre-existing limitation of
this repo's `ToolsConfigGenerator.psm1`, already true for `ExecuteService`'s
`params` and `GetLogEntries`'s optional inputs) — pass an empty/omit-
equivalent value if your MCP client requires sending every listed field.
Known limitation: composing this tool's `zipContent` output directly into
an `ImportEntityZip` call through an MCP client (rather than persisting it
to a file first) requires the client to reproduce the full base64 string as
a fresh tool-call argument, which carries the same payload-size/corruption
risk already tracked in `docs/ThingworxMCPToolRoadmap.md` Section 8 — for
large exports, prefer writing `zipContent` to a local file before re-using
it, rather than passing it straight through as generated output.

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
