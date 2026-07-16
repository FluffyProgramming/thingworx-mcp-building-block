# ThingWorx MCP Building Block: Tool Roadmap

**Author:** Derrick Swint
**Purpose:** Planning doc for the MCP building block that connects Claude Code to a live ThingWorx server. This is the reference for Claude Code to help design and implement the remaining tools.

---

## 1. Why this exists

Across every ThingWorx project I evaluated Claude Code on (DragDropListWidget, the Optilite/PDX.Datawatch pipeline, FTPHandler, and CWC), the single structural limitation was the same: Claude Code cannot reach a live ThingWorx instance. It can write and reason about entities, but it can't import them, run a service, read a log, or query data. So every test cycle was manual: edit XML, import, run a TEST_ service, read the result, read the logs, report back.

This MCP building block closes that loop. Each tool below maps to one step of that manual cycle. The goal is that Claude Code can complete a full write - import - run - inspect - fix cycle on its own, with the developer supervising rather than shuttling results back and forth by hand.

**Design stance:** the real work lives in versioned ThingWorx services inside this building block; the MCP server is a thin wrapper that calls them (same pattern as the first tool, `ImportEntityZip`). That keeps the MCP layer small and makes the capability itself shippable and version-controlled as a building block.

---

## 2. Current state

- **`ImportEntityZip`** (built): accepts a source-control zip of entities as base64, saves it to a FileRepository, extracts it, and imports the entities into the system. This is the gateway action and the foundation the rest build on.
- **Local build/package tooling** (built): `scripts/PackageSourceControlZip.ps1` + `scripts/lib/SourceControlPackager.psm1` regenerate `ToolsConfiguration` and package this repo's entity folders into an `ImportEntityZip`-ready zip, base64-encoded, written to `dist/`. See design doc: `docs/superpowers/specs/2026-07-16-source-control-packaging-design.md`. The Claude Code skill that chains this to an `ImportEntityZip` call (with a confirmation prompt first) is still open — see Section 7.

---

## 3. Build order

Ranked by how much each would have changed the investigation. Build the core loop first.

1. `ExecuteService` — makes the TEST_ pattern autonomous. Highest value.
2. `GetLogEntries` — removes the paste-the-error friction.
3. `ExportEntities` — kills stale state, enforces export discipline, completes the round trip.
4. `GetEntityDefinition` — read live entity structure instead of guessing.
5. `ListEntities` — discover what exists before referencing it.
6. `ValidateImport` (dry run) — catch failures before committing.
7. `GetPlatformInfo` — calibrate to the actual server (Rhino version, extensions).
8. `QueryDataTable` / `QueryStream` — verify output against real data.
9. `ManageFileRepository` — stage sample files and inspect parser output.

---

## 4. Tool specifications

Each tool notes its purpose, inputs, output shape, whether it mutates server state, and the failure mode it removes from the manual loop.

### 4.1 `ExecuteService`  (build first)

**Purpose:** Call a service on any Thing with typed inputs and return the result as JSON. This is what makes the TEST_ pattern self-driving: Claude writes a service, imports it, runs its TEST_ harness, sees PASS:/FAIL:, and fixes it without a human in the loop.

- **Mutates state:** Potentially (a service can write data). Treat as a write-class tool; see safety gating in Section 5.
- **Inputs:** `thingName` (string), `serviceName` (string), `params` (object of name to value), optional `timeoutSeconds`.
- **Output:** structured result: `{ success, result (InfoTable rows as JSON or scalar), executionTimeMs, error }`.
- **Removes:** the core edit - import - run - read loop that was the biggest time sink in the Optilite and CWC work.
- **Notes:** map ThingWorx base types to JSON cleanly (INFOTABLE to array of objects, DATETIME to ISO string, etc.). Return the ThingWorx error detail on failure, not just an HTTP code.

### 4.2 `GetLogEntries`

**Purpose:** Return application and script logs, so Claude can diagnose a failed run itself.

- **Mutates state:** No (read-only, safe to call freely).
- **Inputs:** optional `sinceMinutes` or explicit time window, `level` (ERROR/WARN/INFO/DEBUG), optional `search` string, optional `maxRows`.
- **Output:** array of `{ timestamp, level, source, message }`.
- **Removes:** the opaque-debugging problem. In the retrospectives, diagnosing a bad TEST_ result meant a human copying log output into the chat. This removes that entirely.
- **Notes:** if feasible, support correlating logs to a specific service run (e.g., a request id) so Claude sees only the relevant lines.

### 4.3 `ExportEntities`

**Purpose:** Pull a zip (or single entity XML) of named entities, a project, or everything, back out of the server. The reverse of `ImportEntityZip`.

- **Mutates state:** No (read-only).
- **Inputs:** one of `entityNames` (array), `projectName`, or `all`; optional `format` (zip base64 or raw XML).
- **Output:** base64 zip or XML string, plus a manifest of what was exported.
- **Removes:** stale-state bugs. The retrospectives flagged "export before every session" as essential because entities edited in Composer make Claude's view stale. This automates that discipline: Claude exports current state before starting.

### 4.4 `GetEntityDefinition`

**Purpose:** Return the live definition of a Thing, ThingTemplate, ThingShape, or DataShape: properties, services with signatures, events, and inherited members.

- **Mutates state:** No.
- **Inputs:** `entityName`, `entityType`.
- **Output:** structured definition (properties with base types, services with input/output signatures, events, config tables, inheritance chain).
- **Removes:** the "approximate knowledge" failures. Claude reads the actual entity instead of inferring it from a possibly-stale export.

### 4.5 `ListEntities`

**Purpose:** Discover what exists on the server before referencing it.

- **Mutates state:** No.
- **Inputs:** filters: `entityType`, `projectName`, `template`, `tag`, `nameContains`.
- **Output:** array of `{ name, type, project, template }`.
- **Removes:** the dangling-reference class of bug (referencing an entity or DataShape field that does not exist). This is the server-side version of the import-readiness skill.

### 4.6 `ValidateImport`  (dry run)

**Purpose:** Attempt an import and report what would fail (missing referenced entities, permission gaps, malformed XML) without committing it.

- **Mutates state:** No (that is the point; it is a dry run).
- **Inputs:** same payload as `ImportEntityZip` plus `dryRun: true`.
- **Output:** `{ wouldSucceed, problems: [{ entity, issue }] }`.
- **Removes:** the import-fails-at-runtime surprise. Turns the import-readiness static check into a server-verified one.

### 4.7 `GetPlatformInfo`

**Purpose:** Report the server's ThingWorx version, Rhino/JavaScript engine version, and installed extensions with versions.

- **Mutates state:** No.
- **Inputs:** none.
- **Output:** `{ thingworxVersion, scriptEngine, extensions: [{ name, version }] }`.
- **Removes:** guesswork about what the server actually supports. Instead of the Rhino linter assuming which ES features fail, Claude can calibrate to the real engine. Also surfaces extension version ambiguity (e.g., the CSVParser version question from Optilite).

### 4.8 `QueryDataTable` / `QueryStream`

**Purpose:** Read actual data rows so Claude can verify a service produced correct output against real records, not just sample files.

- **Mutates state:** No.
- **Inputs:** `thingName`, optional `query`/filter, `maxRows`.
- **Output:** rows as JSON.
- **Removes:** the gap between "parser logic looks right" and "parser produced the right row." Lets Claude check Build*Row-style output end to end.

### 4.9 `ManageFileRepository`

**Purpose:** List, read, and write files in a FileRepository.

- **Mutates state:** Yes for write/delete (write-class); no for list/read.
- **Inputs:** `repositoryName`, `operation` (list/read/write/delete), `path`, optional `contentBase64`.
- **Output:** depends on operation (file listing, file content, or write confirmation).
- **Removes:** manual sample-file staging. The TEST_ pattern depends on sample files being present; this lets Claude stage them and inspect parser output files directly.

---

## 5. Safety and design requirements (apply to every tool)

These come straight from the destructive-action and prompt-injection guardrails I already use with Claude Code. An MCP that can import, run, and delete on a live server is powerful and needs guardrails.

- **Separate read-class from write-class tools.** Read-only tools (`GetLogEntries`, `GetEntityDefinition`, `ListEntities`, `GetPlatformInfo`, `ExportEntities`, query/list operations) are safe to call freely. Mutating tools (`ImportEntityZip`, `ExecuteService`, delete/write operations) must be clearly marked and, ideally, gated behind an explicit confirmation.
- **Provide a dry-run / read-only mode as a first-class concept.** `ValidateImport` is the model; where a mutating tool can offer a preview, it should.
- **Scope to a target environment.** Configure the server/project the MCP points at, so Claude cannot accidentally act against production. Never let the target be set from within untrusted content.
- **Return structured, parsed errors.** The value on failure is in the ThingWorx error detail. Parse it into something Claude can reason about and act on, not a bare HTTP status.
- **Never destructive without confirmation.** No hard deletes, no overwrites of unrelated entities, no production writes without an explicit go-ahead from the developer.
- **Reversibility.** Prefer additive/importable operations; make destructive operations the rare, clearly-flagged exception.

---

## 6. Architecture note

The building-block pattern (real work in versioned ThingWorx services, thin MCP wrapper calling them) has a nice property: Claude Code can help build the services themselves using the exact workflow from the investigation. Spec first, then plan, then implement, then run the service's own TEST_ harness through `ExecuteService` once that tool exists. The MCP effectively bootstraps its own development.

Open decision to settle early: confirm whether each tool is a ThingWorx service in this building block (with the MCP calling it) or a direct REST-API call from the MCP server. `ImportEntityZip` sounds like the former, which is the cleaner, more shippable design. Keep that consistent.

---

## 7. Local build/package tooling

The zip-build step that has to happen *before* `ImportEntityZip` can be called — walking the repo's entity folders, packaging them into a correctly-formed source-control zip, base64-encoding the result — is local, client-side work. It isn't a ThingWorx service and doesn't fit the "real work lives in a versioned service" pattern above; there's no server to put it on.

**Decision:** implement this as a Claude Code skill, not an MCP tool. It's portable across any ThingWorx repo (not just this one — the same packaging logic applies to `PDX.Datawatch` and every other building block), and a skill can encode known gotchas as executable guidance instead of letting each project rediscover them. The concrete one already hit: PowerShell's `Compress-Archive` writes backslash-separated entry paths, which ThingWorx's Java-based zip extraction silently mis-reads as literal filename characters instead of folder separators — the zip has to be built with forward-slash paths (e.g. via `System.IO.Compression.ZipArchive` directly) or the import silently produces broken, flat entity output.

**Keeping it usable by non-Claude callers:** mirror the same thin-wrapper principle used for the server side, applied to the client side instead. The actual packaging logic lives in a plain, standalone script/module — extending `scripts/lib/ExtensionPackager.psm1` (or a new sibling module) with a function that builds the zip and base64-encodes it — callable directly from the command line by a human, a CI job, or any other agent, with no dependency on Claude or the skills system. The skill's only job is teaching *Claude specifically* when to invoke that script and what pitfalls to avoid; it's a discoverability/guidance layer, not where the capability actually lives. Claude Code gets the best experience (automatic triggering, gotchas front-loaded); everyone else gets identical correct output by running the script directly.