#!/usr/bin/env node

import fs from 'node:fs/promises';
import path from 'node:path';

const root = process.argv[2];
const platform = process.argv[3];
if (!root || !platform) {
  throw new Error('usage: verify_sticky_package.mjs <extracted-sdk> <runtime-platform>');
}

const release = JSON.parse(await fs.readFile(path.join(root, 'CJCJ_RELEASE.json'), 'utf8'));
const sticky = JSON.parse(await fs.readFile(path.join(root, 'STICKY_STD.json'), 'utf8'));
if (release.runtimeRef !== sticky.sourceRef) {
  throw new Error(`package runtime/std ref mismatch: ${release.runtimeRef} != ${sticky.sourceRef}`);
}
if (release.stickyStd.closure !== 'single-sticky' || release.stickyStd.role !== 'final' ||
    release.stickyStd.provenance !== 'official-cjc-sticky-lowering') {
  throw new Error(`package sticky std role mismatch: ${JSON.stringify(release.stickyStd)}`);
}
if (release.stockSdkStdSeed.residual !== 0) {
  throw new Error(`package contains stock SDK std seed SHA residuals: ${release.stockSdkStdSeed.residual}`);
}
const variantDirectory = path.join(root, 'lib', 'cjcj-optimization');
if (await fs.stat(variantDirectory).catch(() => null)) {
  throw new Error(`retired std variant directory survived packaging: ${variantDirectory}`);
}
const libraries = (await fs.readdir(path.join(root, 'lib', platform)))
  .filter(name => /^libcangjie-std.*\.(?:a|so|dylib)$/.test(name));
const runtimeShared = (await fs.readdir(path.join(root, 'runtime', 'lib', platform)))
  .filter(name => /^libcangjie-std.*\.(?:so|dylib)$/.test(name));
const cjos = (await fs.readdir(path.join(root, 'modules', platform, 'std')))
  .filter(name => name.endsWith('.cjo'));
const expectedShared = sticky.sticky.files.filter(name => name.endsWith('.so') || name.endsWith('.dylib')).length;
if (libraries.length !== release.stickyStd.libraries || runtimeShared.length !== expectedShared ||
    cjos.length !== release.stickyStd.cjos) {
  throw new Error(`package sticky std counts mismatch: libraries=${libraries.length}/${release.stickyStd.libraries} `
    + `runtimeShared=${runtimeShared.length}/${expectedShared} cjos=${cjos.length}/${release.stickyStd.cjos}`);
}
console.log(`STICKY_PACKAGE runtime_ref=${release.runtimeRef} libraries=${libraries.length} `
  + `runtime_shared=${runtimeShared.length} cjos=${cjos.length} seed_residual=0 variant_dirs=0`);
