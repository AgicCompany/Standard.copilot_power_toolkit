# MCP Servers

Several agents (`review`, `checklist`, `plan`-family, `prd`, `devops`, `lyra`) list tools that only
exist if the matching MCP server is actually configured and running. `.vscode/mcp.json` (at the
**target project root**, not under `.github/` — VS Code only reads workspace MCP config from
`.vscode/mcp.json`) configures the servers below. `tools:` frontmatter references them as
`server-name/*` or `server-name/tool-name` — a bare tool name with no `server-name/` prefix does
**not** resolve to anything and is silently dropped. If you add a new MCP server, update both this
file and every agent's `tools:` list that should use it.

## Configured

| Server | Type | What it needs |
|--------|------|----------------|
| `context7` | Remote HTTP (`https://mcp.context7.com/mcp`) | Nothing to work; optional `CONTEXT7_API_KEY` header for higher rate limits (free key at context7.com/dashboard) |
| `github` | Remote HTTP (`https://api.githubcopilot.com/mcp`) | GitHub auth via your existing Copilot/VS Code GitHub sign-in |
| `playwright` | Local (`npx -y @playwright/mcp@0.0.82`) | Node/npx available; browsers install on first run |
| `azure-mcp` | Local (`npx -y @azure/mcp@2.0.5 server start`) | **Manual one-time step:** run `Azure: Sign In` from the Command Palette before use. Without this, `azure-mcp/*` tools fail silently — VS Code won't error loudly, calls just won't return useful results |

## Pinned versions — and why not `@latest`

Both local servers are pinned to an exact version. **`@latest` is a moving tag the vendor controls**,
and every developer's VS Code launches these automatically — `-y` suppresses the install prompt. On
2026-09-24 Microsoft pointed `@azure/mcp`'s `latest` tag at `3.0.0-beta.47`, so every project that
followed Microsoft's own README (`@azure/mcp@latest`) began running a beta nobody had chosen. npm
versions are immutable: a pinned version is exactly what was reviewed, on every machine.

**Bump deliberately**, as part of a release rather than whenever a vendor publishes:

1. `npm view <package> dist-tags` — and check `latest` is not a prerelease (`-beta`, `-alpha`,
   `-rc`). If it is, `npm view <package> versions` and take the newest stable one. (`npm view` only
   reads the registry, so it is right in any project, whatever its package manager.)
2. Read what changed between the pinned version and the new one.
3. Update `.vscode/mcp.json` and the table above together.

Pinning makes a server **reproducible**, not **safe**: it is still third-party code running locally.

## Candidates to add (not configured)

Servers `lyra.agent.md` once listed as bare tool names. Those names resolved to nothing — VS Code
drops an unrecognised tool silently — so they were removed from the agent and recorded here instead.
Wire one up only after verifying its package or URL:

- **`Microsoft Docs`** — a Microsoft Learn documentation MCP server exists; exact package/URL not
  yet verified for this baseline. Verify before wiring up.
- **`memory`** — likely intended as a knowledge-persistence MCP server, but this baseline now has a
  simpler non-MCP alternative: `.github/docs/project-memory.md` (see `instructions/memory.instructions.md`).
  Prefer that unless there's a specific reason to want an MCP-based memory server instead.
- **`ado`** — an Azure DevOps MCP server exists; exact package/URL not yet verified for this
  baseline. Verify before wiring up (this would pair naturally with `instructions/work-items.instructions.md`).

## Adding a New Server

1. Add the entry to `.vscode/mcp.json` (`servers.<name>`, either `{"type": "http", "url": "..."}`
   or `{"command": "...", "args": [...]}`).
2. Reference it from agent frontmatter as `<name>/*` (all tools) or `<name>/<tool-id>` (specific tool).
3. **Pin it to an exact version** — never `@latest`; see *Pinned versions* above.
4. Update the tables above.
5. If it needs auth/setup beyond "just works," document the manual step here — don't assume the
   next person (or agent) will discover it by trial and error.
