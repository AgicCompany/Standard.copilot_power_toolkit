// Import boundaries — makes three prose rules mechanical.
//
// `react-ts.instructions.md` already says all three of these in words:
//   - a feature never imports from another feature's internals   (line ~132)
//   - import from the specific module, not a barrel file          (line ~129)
//   - use the `@/` alias across features, relative paths within   (line ~131)
//
// Words lose to the task. AGENTS.md is explicit that a mechanically checkable rule with no
// judgement belongs in a check, not in prose — this is that check. Adapted from
// https://github.com/alan2207/bulletproof-react (docs/project-structure.md).
//
// REQUIRES:  eslint-plugin-import-x, eslint-plugin-check-file and eslint-import-resolver-typescript
//            as dev dependencies, installed with the package manager the project's lockfile shows.
//            The resolver is not optional: without it `@/` imports never resolve and no boundary is
//            enforced (see boundaries-core.mjs). It reads the repository root's tsconfig.json.
//
// THIS FILE is for an app whose src/ sits at the repository root, with the plugins installed there.
// Wire it up in the project's own eslint.config.js:
//
//   import boundaries from './.github/eslint/import-boundaries.mjs';
//   export default [ ...yourExistingConfig, ...boundaries ];
//
// For an app in a subfolder (e.g. src/frontend/src/) use import-boundaries-app.mjs instead: it
// loads the plugins from the app's own node_modules, which this file cannot.
//
// The project's eslint.config.js is project-owned; this file is baseline-owned and is replaced on
// every `apply-baseline`. Do not edit it in a project — if a zone is wrong for your layout, say so
// and it gets fixed here, for everyone.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import importX from 'eslint-plugin-import-x';
import checkFile from 'eslint-plugin-check-file';
import { createTypeScriptImportResolver } from 'eslint-import-resolver-typescript';

import { buildConfig, nestedFeaturesDir } from './boundaries-core.mjs';

// The repository root, resolved from THIS file, not from process.cwd(): running eslint from a
// subdirectory would otherwise read the wrong folder, find no features, and silently drop every
// cross-feature zone - a guard that looks configured and enforces nothing. This file sits at
// .github/eslint/, so the repository root is two levels up.
const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

// This wiring assumes src/ at the repository root. When it is not there but an app's src/features
// exists further down, it would enforce nothing, silently. Say so once.
if (!fs.existsSync(path.join(REPO_ROOT, 'src', 'features'))) {
  const nested = nestedFeaturesDir(REPO_ROOT);
  if (nested) {
    console.warn(
      `[import-boundaries] No src/features at the repository root, but found ${path.relative(REPO_ROOT, nested)}. ` +
        'This wiring enforces nothing for that app. Use import-boundaries-app.mjs from an eslint.config.js ' +
        'in the app folder (see its header).',
    );
  }
}

const root = buildConfig(REPO_ROOT, { importX, checkFile, createTypeScriptImportResolver });
export const importBoundaries = root.importBoundaries;
export const fileNaming = root.fileNaming;
export const generatedIgnores = root.generatedIgnores;

export default [generatedIgnores, importBoundaries, fileNaming];
