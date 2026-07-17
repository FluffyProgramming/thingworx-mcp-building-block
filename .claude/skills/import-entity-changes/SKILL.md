---
name: import-entity-changes
description: Use when the user asks to import, push, or deploy ThingWorx entity changes (this repo's entity XML) to a live ThingWorx server. Packages changes locally via PackageSourceControlZip.ps1, then confirms before calling ImportEntityZip.
---

# Import Entity Changes

Chains this repo's local packaging script into a confirmed `ImportEntityZip`
call. This skill adds no new packaging or import logic of its own — it only
tells you when to run the existing script and how to safely hand its output
to `ImportEntityZip`. Anyone without Claude Code gets identical results by
running the script directly from the command line.

**Trigger:** only when the user explicitly asks to import, push, or deploy
entity changes to a ThingWorx server (e.g. "import my changes," "push this to
ThingWorx," "deploy these entities"). Never trigger this proactively —
`ImportEntityZip` is a write-class action against a live server, and an
unprompted offer to write to it is itself a small confirmation-boundary
violation.

## Why this script exists (read before running anything else)

Do not build a zip any other way — in particular, never call PowerShell's
`Compress-Archive` for this. `Compress-Archive` writes backslash-separated
zip entry paths, and ThingWorx's Java-based zip extraction silently
misreads those backslashes as literal filename characters instead of folder
separators, producing broken, flat entity output on import. This repo's
`scripts/PackageSourceControlZip.ps1` (and the module it calls,
`scripts/lib/SourceControlPackager.psm1`) already solves this — it builds
zips directly via `System.IO.Compression.ZipArchive` with forward-slash entry
paths. Always use that script; never reimplement packaging inline.

## Process

### 1. Determine mode

Default to `-ChangedOnly` — this keeps the base64 payload handed to
`ImportEntityZip` as small as possible, which is the whole reason this flag
exists (large inline base64 payloads have a real, observed corruption risk
when reproduced as generated tool-call output).

Only drop `-ChangedOnly` (run a full-tree package) if the user's own request
explicitly asks for everything — words like "everything," "full package,"
"full import," or "package the whole repo." Absent one of those explicit
signals, always use `-ChangedOnly`.

### 2. Run the script

Changed-files mode (default):
```powershell
./scripts/PackageSourceControlZip.ps1 -ChangedOnly
```

Full-tree mode (only on explicit request):
```powershell
./scripts/PackageSourceControlZip.ps1
```

### 3. If the script throws, stop

The script throws clear errors for "nothing to package" cases (e.g. "no
changed entity files found," "no entity folders found," "all changes are in
excluded folders: ..."). If it throws, surface that error to the user
exactly as raised and stop there. Do not retry. Do not automatically fall
back to the other mode (e.g. don't silently switch from `-ChangedOnly` to
full-tree just because nothing changed) — a "nothing changed" result usually
means the user hasn't actually made the edit they think they have, and
guessing a different scope on their behalf would import something they
didn't ask for.

### 4. On success, read the script's output

The script prints (via `Write-Host`) and writes to disk everything needed
for the next steps — read these directly, do not re-derive or re-encode
anything yourself:

- The file list actually included:
  - `-ChangedOnly` mode: a line like `Changed files included: ThingShapes/VPS.Development.MCP.Management_TS.xml`
  - full mode: a line like `Entity folders included: DataShapes, Things, ThingShapes, ...`
- The suggested `fileName` and `folderName` for `ImportEntityZip`, from a
  line like:
  `For ImportEntityZip -> fileName: 'VPS.Development.MCP.zip'  folderName: 'vps'`
- The base64 content itself, from the file path the script reports as
  `Base64Path` (e.g. `dist/VPS.Development.MCP.zip.b64.txt`) — read that
  file's full contents directly as the `zipContent` value. Do not type it out,
  summarize it, or regenerate it by hand.

### 5. Confirm before importing

Before calling `ImportEntityZip`, show the user:
- The exact file list (or entity-folder list, in full mode) that will be
  imported.
- The target `folderName` this will land in on the server.
- A direct question: **"Import these to ThingWorx? y/n"**

Wait for an explicit yes. Any answer that isn't a clear yes (including
silence, a question back, or an ambiguous reply) means stop — do not call
`ImportEntityZip`. There is no partial or "importing anyway" path.

### 6. On yes, call `ImportEntityZip`

Call the `ImportEntityZip` MCP tool with:
- `zipContent`: the base64 content read in step 4.
- `fileName`: the `fileName` reported by the script in step 4.
- `folderName`: the `folderName` reported by the script in step 4.

### 7. Report the result

`ImportEntityZip` throws on failure and returns a human-readable summary
string on success. Relay whichever one comes back directly to the user —
this skill adds no extra interpretation, retry, or rollback logic on top of
the tool's own behavior.
