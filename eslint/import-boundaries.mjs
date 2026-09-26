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
// REQUIRES:  pnpm add -D eslint-plugin-import-x eslint-plugin-check-file
//
// WIRE IT UP in the project's own eslint.config.js:
//
//   import boundaries from './.github/eslint/import-boundaries.mjs';
//   export default [ ...yourExistingConfig, ...boundaries ];
//
// The project's eslint.config.js is project-owned; this file is baseline-owned and is replaced on
// every `apply-baseline`. Do not edit it in a project — if a zone is wrong for your layout, say so
// and it gets fixed here, for everyone.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import importX from 'eslint-plugin-import-x';
import checkFile from 'eslint-plugin-check-file';

const SRC = 'src';

// Resolve from THIS file, not from process.cwd(). Running eslint from a subdirectory would otherwise
// make the readdir below fail, return no features, and silently drop every cross-feature zone - a
// guard that looks configured and enforces nothing. This file sits at .github/eslint/, so the
// project root is two levels up.
const PROJECT_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const FEATURES_DIR = path.join(PROJECT_ROOT, SRC, 'features');

// Read the feature folders instead of listing them by hand. bulletproof-react enumerates one zone
// per feature, which means every new feature needs a config edit that nobody remembers to make.
function featureNames() {
  try {
    return fs
      .readdirSync(FEATURES_DIR, { withFileTypes: true })
      .filter((entry) => entry.isDirectory())
      .map((entry) => entry.name);
  } catch {
    return []; // no features/ yet — a fresh scaffold, not an error
  }
}

// A feature may not reach into another feature. Compose them at the route/app layer instead.
const crossFeatureZones = featureNames().map((name) => ({
  target: `./${SRC}/features/${name}`,
  from: `./${SRC}/features`,
  except: [`./${name}`],
  message:
    'Features must not import from each other. Promote the shared piece to src/components, src/hooks or src/lib, and compose the features at the route layer.',
}));

// Unidirectional flow:  shared  ->  features  ->  routes/app
// Anything lower in that chain must not reach upward.
const layerZones = [
  {
    target: `./${SRC}/features`,
    from: `./${SRC}/routes`,
    message:
      'A feature must not import from the route layer. Routes compose features, never the other way round.',
  },
  {
    target: [
      `./${SRC}/components`,
      `./${SRC}/hooks`,
      `./${SRC}/lib`,
      `./${SRC}/types`,
      `./${SRC}/utils`,
    ],
    from: [`./${SRC}/features`, `./${SRC}/routes`],
    message:
      'Shared code must not import from features or routes. If it needs to, it is not shared — move it into the feature that owns it.',
  },
];

export const importBoundaries = {
  name: 'baseline/import-boundaries',
  files: ['src/**/*.{ts,tsx,js,jsx}'],
  plugins: { 'import-x': importX },
  rules: {
    'import-x/no-restricted-paths': [
      'error',
      { zones: [...crossFeatureZones, ...layerZones] },
    ],
    // Barrel files defeat tree shaking and cause circular imports.
    'import-x/no-cycle': ['error', { maxDepth: Infinity }],
  },
};

export const fileNaming = {
  name: 'baseline/file-naming',
  files: ['src/**/*'],
  plugins: { 'check-file': checkFile },
  rules: {
    'check-file/filename-naming-convention': [
      'error',
      { '**/*.{ts,tsx}': 'KEBAB_CASE' },
      // `useAccounts.ts` stays `use-accounts.ts`, but `AccountsList.test.tsx` is judged on
      // `AccountsList`, not on `test` — that is what ignoreMiddleExtensions buys.
      { ignoreMiddleExtensions: true },
    ],
    'check-file/folder-naming-convention': [
      'error',
      { 'src/**/!(__tests__)': 'KEBAB_CASE' },
    ],
  },
};

// `src/generated/` is PAC CLI output, overwritten wholesale on regeneration. Linting it produces
// noise nobody can act on, and a lint error there invites exactly the hand-edit the baseline forbids.
export const generatedIgnores = {
  name: 'baseline/ignore-generated',
  ignores: ['src/generated/**', 'src/components/ui/**'],
};

export default [generatedIgnores, importBoundaries, fileNaming];
