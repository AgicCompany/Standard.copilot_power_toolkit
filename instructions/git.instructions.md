---
description: Instructions for managing Git commits and branches in the project. On-demand reference — the operative rules are summarised in copilot-instructions.md.
---
<!--
LOADING: intentionally has no `applyTo` — see the note in gitflow.instructions.md. Git work has no
file-pattern trigger, so this is reference material reached via the `/git` prompt or manual attach.
The rules that must always be in effect live in `copilot-instructions.md`.
-->

# Git Instructions (Aligned With Gitflow)

## Language Support (EN/IT)
- Queste istruzioni supportano input in inglese e italiano.
- Rispondi nella stessa lingua usata dall'utente.
- Mantieni invariati comandi git, nomi branch e formato commit.

Queste regole operano insieme a `.github/instructions/gitflow.instructions.md`.
In caso di conflitto, prevale Gitflow.

## Branching operativo

1. Verifica stato repository con `git status`.
2. Non lavorare direttamente su `main` o `develop`.
3. Crea branch da base corretta secondo Gitflow:
   - `feature/*` da `develop`
   - `release/*` da `develop`
   - `hotfix/*` da `main`
4. Naming consigliato:
   - `feature/<id>-<descrizione-breve>`
   - `release/vX.Y.Z`
   - `hotfix/vX.Y.Z`

## Pull request e merge

1. Ogni modifica passa da Pull Request.
2. Prima della PR, aggiorna il branch con la branch base corretta.
3. Verifica build e test locali prima di aprire la PR.
4. Dopo merge, elimina branch di supporto quando appropriato.

## Commit messages (Conventional Commits)

Formato: `type(scope): description`

Tipi principali:
- `feat`: nuova funzionalita
- `fix`: correzione bug
- `refactor`: refactoring senza variazione funzionale
- `perf`: miglioramento performance
- `test`: test aggiunti/aggiornati
- `docs`: sola documentazione
- `chore`: manutenzione/build/tooling
- `ci`: pipeline e automazione CI/CD

Linee guida:
- Messaggio breve, concreto, orientato all'impatto.
- Un commit per modifica logica coerente (atomic commit).
- Evita commit rumorosi o con cambi non correlati.
- Non includere segreti o dati sensibili.

## Esempi

- `feat(requests): add flow orchestration in save pipeline`
- `fix(projects): prevent stale lock overwrite`
- `docs(github): align copilot instructions with gitflow`