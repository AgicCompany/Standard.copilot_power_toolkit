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
| `playwright` | Local (`npx @playwright/mcp@latest`) | Node/npx available; browsers install on first run |
| `azure-mcp` | Local (`npx -y @azure/mcp@latest server start`) | **Manual one-time step:** run `Azure: Sign In` from the Command Palette before use. Without this, `azure-mcp/*` tools fail silently — VS Code won't error loudly, calls just won't return useful results |

## Known Gaps (referenced by `lyra.agent.md`, not yet configured)

These are named in `lyra.agent.md`'s `tools:` list as bare strings — left in place deliberately so
the gap stays visible, not silently dropped by "fixing" them into a name that isn't actually
configured either. Don't trust them to work until they're added to `.vscode/mcp.json`:

- **`Microsoft Docs`** — a Microsoft Learn documentation MCP server exists; exact package/URL not
  yet verified for this baseline. Verify before wiring up.
- **`memory`** — likely intended as a knowledge-persistence MCP server, but this baseline now has a
  simpler non-MCP alternative: `docs/project-memory.md` (see `instructions/memory.instructions.md`).
  Prefer that unless there's a specific reason to want an MCP-based memory server instead.
- **`ado`** — an Azure DevOps MCP server exists; exact package/URL not yet verified for this
  baseline. Verify before wiring up (this would pair naturally with `instructions/work-items.instructions.md`).

## Adding a New Server

1. Add the entry to `.vscode/mcp.json` (`servers.<name>`, either `{"type": "http", "url": "..."}`
   or `{"command": "...", "args": [...]}`).
2. Reference it from agent frontmatter as `<name>/*` (all tools) or `<name>/<tool-id>` (specific tool).
3. Update the tables above.
4. If it needs auth/setup beyond "just works," document the manual step here — don't assume the
   next person (or agent) will discover it by trial and error.
