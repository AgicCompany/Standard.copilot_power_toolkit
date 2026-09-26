---
description: 'Bilingual parity audit (EN/IT) between legacy Canvas behavior and React implementation for a scoped feature'
agent: 'agent'
---

# Parity Audit Prompt | Prompt Audit Parita

Use the same language used by the user (English or Italian).

## English

Audit parity for the requested feature slice by comparing:
- legacy behavior in `canvas_src/Src/*.fx.yaml`
- datasource/flow references in `canvas_src/DataSources/*.json`
- current implementation in `src/`

### Required Output
1. Legacy behavior summary (exact rules/conditions).
2. Current React behavior summary.
3. Parity gaps ordered by severity.
4. Recommended minimal implementation plan.
5. Validation plan (build + functional checks).

### Constraints
- Do not propose broad rewrites when a targeted fix is possible.
- Prioritize server-side parity where legacy logic runs at query level.
- Explicitly call out required datasources/flows if missing.

## Italiano

Esegui l'audit di parita per la feature richiesta confrontando:
- comportamento legacy in `canvas_src/Src/*.fx.yaml`
- riferimenti datasource/flow in `canvas_src/DataSources/*.json`
- implementazione attuale in `src/`

### Output Richiesto
1. Sintesi comportamento legacy (regole/condizioni esatte).
2. Sintesi comportamento React attuale.
3. Gap di parita ordinati per severita.
4. Piano minimo di implementazione consigliato.
5. Piano di validazione (build + verifiche funzionali).

### Vincoli
- Non proporre riscritture ampie se e possibile una correzione mirata.
- Dare priorita alla parita lato server quando la logica legacy vive nella query.
- Evidenziare esplicitamente datasource/flow mancanti quando necessario.
