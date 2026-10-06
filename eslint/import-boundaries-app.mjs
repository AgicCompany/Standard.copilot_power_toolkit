// Import boundaries for an app in a subfolder (e.g. src/frontend/src/, as in a multi-host template).
// Same rules as import-boundaries.mjs, anchored at the app folder instead of the repository root.
//
// REQUIRES:  eslint-plugin-import-x, eslint-plugin-check-file and eslint-import-resolver-typescript
//            as dev dependencies OF THE APP, installed with the package manager the project's
//            lockfile shows. The resolver is not optional: without it `@/` imports never resolve and
//            no boundary is enforced (see boundaries-core.mjs).
//
// Wire it up in an eslint.config.js IN THE APP FOLDER:
//
//   import { boundariesFor } from '../../.github/eslint/import-boundaries-app.mjs';
//   export default [ ...yourExistingConfig, ...(await boundariesFor(import.meta.dirname)) ];
//
// The resolver reads the app folder's tsconfig.json (following `references`). If the `@/` paths live
// in a tsconfig that file does not reach, name it: boundariesFor(import.meta.dirname, { tsconfig: 'tsconfig.app.json' }).
//
// Why a separate file, and why async: Node resolves a bare import from the importing FILE's location,
// so plugins imported at the top of a file under .github/eslint/ are looked up in the repository
// root's node_modules. An app that installs them in its own node_modules (pnpm, or an app outside a
// hoisting workspace) could never load them. This file imports no plugin; boundariesFor resolves
// both from appDir at call time.
//
// Baseline-owned: replaced on every `apply-baseline`. Do not edit it in a project.

import path from 'node:path';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

import { buildConfig } from './boundaries-core.mjs';

async function loadFrom(appRoot, name) {
  // createRequire needs a file path inside the folder to resolve from; it does not have to exist.
  const resolve = createRequire(path.join(appRoot, 'noop.js')).resolve;
  let resolved;
  try {
    resolved = resolve(name);
  } catch {
    throw new Error(
      `[import-boundaries] Cannot find ${name} from ${appRoot}. Install it as a dev dependency of the app.`,
    );
  }
  return import(pathToFileURL(resolved).href);
}

export async function boundariesFor(appDir, { tsconfig } = {}) {
  const appRoot = path.resolve(appDir);
  const [importX, checkFile, resolver] = await Promise.all([
    loadFrom(appRoot, 'eslint-plugin-import-x'),
    loadFrom(appRoot, 'eslint-plugin-check-file'),
    loadFrom(appRoot, 'eslint-import-resolver-typescript'),
  ]);
  const c = buildConfig(appRoot, {
    importX: importX.default ?? importX,
    checkFile: checkFile.default ?? checkFile,
    createTypeScriptImportResolver:
      resolver.createTypeScriptImportResolver ?? resolver.default?.createTypeScriptImportResolver,
    tsconfig,
  });
  return [c.generatedIgnores, c.importBoundaries, c.fileNaming];
}
