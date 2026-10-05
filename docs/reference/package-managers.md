# Package managers — which one, and the command for each

This baseline names no package manager. **The project's lockfile decides**, and
`.github/project-context.md` records the answer:

| Lockfile at the app's root | Package manager |
|---|---|
| `package-lock.json` | npm |
| `pnpm-lock.yaml` | pnpm |
| `yarn.lock` | yarn — **and check which generation**: a `.yarnrc.yml`, or `"packageManager": "yarn@2…"` or later in `package.json`, means Yarn 2+ (Berry); neither means Yarn 1 (Classic). Their commands differ below |
| none | a brand-new project: **ask once**, then record the answer in `project-context.md` |

Two lockfiles is a defect to report, not a choice to make. In a repository whose app sits in a
subfolder (`src/frontend/`), look next to that app's `package.json` first, then at the repository root
(a workspace keeps one lockfile at the root).

**Never suggest a different package manager than the one recorded**, and never mix them: an
`npm install` in a pnpm project writes a second lockfile and a differently resolved `node_modules`.

## How baseline files write commands

Commands in the baseline's instructions, skills and prompts use these placeholders. Substitute the
project's column; do not run the placeholder.

| Placeholder | npm | pnpm | Yarn 1 (Classic) | Yarn 2+ (Berry) |
|---|---|---|---|---|
| `<pm> run <script>` | `npm run <script>` | `pnpm run <script>` | `yarn run <script>` | `yarn run <script>` |
| `<pm> install` | `npm install` | `pnpm install` | `yarn install` | `yarn install` |
| `<pm-ci>` (install exactly the lockfile: CI, deploys) | `npm ci` | `pnpm install --frozen-lockfile` | `yarn install --frozen-lockfile` | `yarn install --immutable` |
| `<pm-add> <pkg>` (`-D` for dev) | `npm install <pkg>` | `pnpm add <pkg>` | `yarn add <pkg>` | `yarn add <pkg>` |
| `<pm-remove> <pkg>` | `npm uninstall <pkg>` | `pnpm remove <pkg>` | `yarn remove <pkg>` | `yarn remove <pkg>` |
| `<pm-dlx> <pkg>` (run a package without installing it) | `npx <pkg>` | `pnpm dlx <pkg>` | `npx <pkg>` — Yarn 1 has no `dlx` | `yarn dlx <pkg>` |
| `<pm-exec> <bin>` (run an **installed** binary) | `npx --no-install <bin>` | `pnpm exec <bin>` | `yarn <bin>` | `yarn <bin>` |

- **`<pm-exec>` must fail when the binary is missing, not fetch it.** Plain `npx <bin>` downloads
  and runs a registry package when the local one is absent — an undeclared tool, at whatever version
  the registry serves. `npx --no-install` refuses instead.

- **Only run a script `package.json` defines.** Read it first: a missing script is a stop-on-failure
  error (npm: `Missing script`; pnpm: `ERR_PNPM_NO_SCRIPT`), not a no-op.
- **Passing arguments to a script:** npm needs `--` before them (`npm run test -- --run`). Prefer
  calling the tool directly when the flags matter: `<pm-exec> vitest run`.
- **On Windows PowerShell** use `npm.cmd` / `pnpm.cmd` when forwarding arguments: the `.ps1` shims can
  swallow `--` and anything after it.
- **Package metadata** (`npm view <pkg> dist-tags`, `npm view <pkg> license`) reads the registry and
  works the same in any project — npm ships with Node.

## pnpm-specific behaviour worth knowing

Applies only when the lockfile is `pnpm-lock.yaml`:

- **pnpm 10+ blocks dependency build scripts until they are approved** and the block fails every
  later `pnpm <script>` with an unrelated-looking error. The fix is in `pnpm-workspace.yaml`, which
  pnpm writes itself — see the `power-apps-code-app-scaffold` skill.
- `pnpm deploy` is a built-in command, not your script: spell it `pnpm run deploy`.
- GitHub-hosted runners do not ship pnpm: CI needs `pnpm/action-setup` before `setup-node`.
