// Shared rules for import-boundaries.mjs (app at the repository root) and
// import-boundaries-app.mjs (app in a subfolder). No plugin imports here on purpose: Node resolves a
// bare import from the importing FILE's location, so a plugin imported at the top of a file under
// .github/eslint/ is looked up in the repository root's node_modules - and an app that installs its
// plugins in its own node_modules could never load. The plugins are passed in by the caller instead.
//
// Baseline-owned: replaced on every `apply-baseline`. Do not edit it in a project.

import fs from 'node:fs';
import path from 'node:path';

const SRC = 'src';

// Read the feature folders instead of listing them by hand. bulletproof-react enumerates one zone
// per feature, which means every new feature needs a config edit that nobody remembers to make.
function featureNames(appRoot) {
  try {
    return fs
      .readdirSync(path.join(appRoot, SRC, 'features'), { withFileTypes: true })
      .filter((entry) => entry.isDirectory())
      .map((entry) => entry.name);
  } catch {
    return []; // no features/ yet — a fresh scaffold, not an error
  }
}

// Returns the three config objects, anchored at appRoot.
export function buildConfig(appRoot, { importX, checkFile }) {
  // A feature may not reach into another feature. Compose them at the route/app layer instead.
  const crossFeatureZones = featureNames(appRoot).map((name) => ({
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

  const importBoundaries = {
    name: 'baseline/import-boundaries',
    files: ['src/**/*.{ts,tsx,js,jsx}'],
    plugins: { 'import-x': importX },
    rules: {
      'import-x/no-restricted-paths': [
        'error',
        // basePath anchors the zones at the app. Without it the rule resolves them against
        // process.cwd(), so they depended on the folder eslint happened to be run from.
        { zones: [...crossFeatureZones, ...layerZones], basePath: appRoot },
      ],
      // Barrel files defeat tree shaking and cause circular imports.
      'import-x/no-cycle': ['error', { maxDepth: Infinity }],
    },
  };

  const fileNaming = {
    name: 'baseline/file-naming',
    files: ['src/**/*'],
    // Vite's React template generates src/App.tsx, and main.tsx imports it by that name. Every other
    // file we name is kebab-case, like the ones shadcn generates (hooks/use-mobile.ts). Component and
    // hook NAMES inside the files stay PascalCase / useCamelCase: React requires that, not the file.
    ignores: ['src/App.tsx'],
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
  const generatedIgnores = {
    name: 'baseline/ignore-generated',
    ignores: ['src/generated/**', 'src/components/ui/**'],
  };

  return { importBoundaries, fileNaming, generatedIgnores };
}

// Finds a src/features below root (up to 4 levels), for the default wiring's nested-app warning.
export function nestedFeaturesDir(dir, depth = 0) {
  if (depth > 4) return null;
  let entries;
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return null; }
  for (const e of entries) {
    if (!e.isDirectory() || ['node_modules', '.git', 'dist', 'build'].includes(e.name)) continue;
    const child = path.join(dir, e.name);
    if (e.name === SRC && fs.existsSync(path.join(child, 'features'))) return path.join(child, 'features');
    const found = nestedFeaturesDir(child, depth + 1);
    if (found) return found;
  }
  return null;
}
