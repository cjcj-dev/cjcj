#!/usr/bin/env zx

import fs from 'node:fs/promises';
import path from 'node:path';

$.stdio = 'inherit';

const workspace = process.env.CANGJIE_WORKSPACE;
const githubWorkspace = process.env.GITHUB_WORKSPACE;
if (!workspace || !githubWorkspace) throw new Error('CANGJIE_WORKSPACE and GITHUB_WORKSPACE are required');

// Runtime is upstream plus the cjcj writer-preference and toRegion2Idx fixes.
const runtime = `${workspace}/cangjie_runtime`;
const patchDir = path.join(githubWorkspace, 'ci/srcbuild/runtime-patches');
const patches = (await fs.readdir(patchDir)).filter((name) => name.endsWith('.patch')).sort();
if (patches.length === 0) throw new Error(`no runtime patches found in ${patchDir}`);
for (const name of patches) {
  console.log(`[runtime] applying ${name}`);
  await $`git -C ${runtime} apply --verbose ${path.join(patchDir, name)}`;
}
