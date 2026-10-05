---
description: Instructions for managing Git commits and branches in the project.
# Runs as the delivery agent: the one agent that runs git, so branch and commit policy live in one
# place (agents/delivery.agent.md). The built-in agent here gave /git a second, diverging policy.
agent: 'delivery'
---
# istruzioni per ogni modifica applicata

## Supporto Lingua (EN/IT)
- Questo prompt supporta input in inglese e italiano.
- Rispondi nella stessa lingua usata dall'utente.
- Mantieni invariati comandi git, nomi branch e formato commit.

per ogni modifica applicata al codice sorgente bisogna creare un commit.
il commit deve seguire lo standard per conventional commits. nel body del messaggio deve essere indicato il nome dell'istruzione di prompting ricevuta e una breve spiegazione del motivo
## branching e workflow

Il modello è **Gitflow** (`instructions/gitflow.instructions.md`, `docs/WORKFLOW_AUTHORITY.md`): i
branch `feature/*` partono da **`develop`**, mai da `main`; su `main` e `develop` non si committa mai
direttamente. Se il progetto dichiara un modello diverso in `project-context.md`, vale quello.

Stabilisci lo stato e scegli la mossa con la tabella **"Always establish state before proposing
anything"** dell'agente `delivery` — è l'unica policy, non duplicarla qui. In sintesi:
- `feature/<issue-id>-<descrizione-breve>` da **`develop`**, mai da `main` (da `main` solo `hotfix/*`).
  **Serve l'ID dell'issue o del work item**: se manca, chiedilo — non inventarlo e non ometterlo.
  Conferma il nome del branch con l'utente prima di crearlo.
- su un branch protetto **con** modifiche non committate: `git stash` → crea il branch →
  `git stash pop`. **Non committare prima**: il commit finirebbe sul branch protetto.
- già su un `feature/*`: non crearne un altro, continua lì.


## conventional commits

Generate a git commit message following this structure:
1. First line: conventional commit format (type: concise description) (remember to use semantic types like feat, fix, docs, style, refactor, perf, test, chore, etc.)
2. Optional bullet points if more context helps:
   - Keep the second line blank
   - Keep them short and direct
   - Focus on what changed
   - Always be terse
   - Don't overly explain
   - Drop any fluffy or formal language

Return ONLY the commit message - no introduction, no explanation, no quotes around it.

### Quick examples
* `feat: new feature`
* `fix(scope): bug in scope`
* `feat!: breaking change` / `feat(scope)!: rework API`
* `chore(deps): update dependencies`

# Commit types
* `build`: Changes that affect the build system or external dependencies (example scopes: gulp, broccoli, npm)
* `ci`: Changes to CI configuration files and scripts (example scopes: Travis, Circle, BrowserStack, SauceLabs)
* **`chore`: Changes which doesn't change source code or tests e.g. changes to the build process, auxiliary tools, libraries**
* `docs`: Documentation only changes
* **`feat`: A new feature**
* **`fix`: A bug fix**
* `perf`: A code change that improves performance
* `refactor`:  A code change that neither fixes a bug nor adds a feature
* `revert`: Revert something
* `style`: Changes that do not affect the meaning of the code (white-space, formatting, missing semi-colons, etc)
* `test`: Adding missing tests or correcting existing tests

# Reminders
* Put newline before extended commit body
* More details at **[conventionalcommits.org](https://www.conventionalcommits.org/)**
