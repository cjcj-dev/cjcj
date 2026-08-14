#!/usr/bin/env zx

import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {hostLoaderPath} from '../../../build/lib/runtime-split.mjs';
import {getTarget} from '../../../build/lib/targets.mjs';
import {platformizeCjcToml} from '../../platform_matrix/link_option.mjs';

$.stdio = 'inherit';

const workspace = process.env.CANGJIE_WORKSPACE;
const githubWorkspace = process.env.GITHUB_WORKSPACE;
const targetKey = process.env.CJCJ_SRCBUILD_TARGET;
const hostSdk = process.env.CJCJ_SRCBUILD_HOST_SDK;
const hostCompiler = process.env.CJCJ_SRCBUILD_HOST_CJC;
if (!workspace || !githubWorkspace || !targetKey || !hostSdk || !hostCompiler) {
  throw new Error(
    'CANGJIE_WORKSPACE, GITHUB_WORKSPACE, CJCJ_SRCBUILD_TARGET, ' +
    'CJCJ_SRCBUILD_HOST_SDK and CJCJ_SRCBUILD_HOST_CJC are required',
  );
}
const target = getTarget(targetKey);
if (process.platform !== target.spec.nodePlatform || process.arch !== target.spec.nodeArch) {
  throw new Error(`target ${targetKey} requires ${target.spec.nodePlatform}/${target.spec.nodeArch}`);
}

const sdk = `${workspace}/software/cangjie`;
const hostLibraryPath = hostLoaderPath({
  hostSdk,
  targetSdk: sdk,
  target,
  inherited: process.env[target.spec.loaderEnv] || '',
});
const workspaceToml = path.resolve('cjpm.toml');
const workspaceTomlBackup = `${workspaceToml}.O2bak`;
const cjcToml = path.resolve('packages', 'cjc', 'cjpm.toml');
const cjcConfig = await fs.readFile(cjcToml, 'utf8');
await fs.writeFile(cjcToml, platformizeCjcToml(cjcConfig, process.platform, sdk));
await fs.copyFile(workspaceToml, workspaceTomlBackup);
await fs.writeFile(
  workspaceToml,
  (await fs.readFile(workspaceToml, 'utf8')).replace('compile-option = "-O2"', 'compile-option = "-O1"'),
);
// Upstream cjc miscompiles cjcj at -O2. Build the seed at -O1 to avoid the
// generic concrete-to-interface upcast loss in the upstream CHIR optimizer.
const oracleCompilerDir = await fs.mkdtemp(path.join(os.tmpdir(), 'cjcj-host-cjc-'));
const oracleCompiler = path.join(oracleCompilerDir, 'cjc');
await fs.writeFile(oracleCompiler, `#!/usr/bin/env node
const {spawnSync} = require('node:child_process');
const env = {...process.env, ${JSON.stringify(target.spec.loaderEnv)}: ${JSON.stringify(hostLibraryPath)}};
const child = spawnSync(${JSON.stringify(hostCompiler)}, process.argv.slice(2), {env, stdio: 'inherit'});
if (child.error) {
  console.error(child.error.message);
  process.exit(1);
}
process.exit(child.status ?? 1);
`, {mode: 0o755});
const oracleEnv = {...process.env, PATH: `${oracleCompilerDir}${path.delimiter}${process.env.PATH || ''}`};
try {
  await $({env: oracleEnv})`cjpm build`;
} finally {
  await fs.rm(oracleCompilerDir, {recursive: true, force: true});
}

// Put the seed under the SDK so <exe>/../runtime resolves. The source-built C++
// oracle already occupies sdk/bin/cjc; replace it only after the seed is built.
// The mapped seed must not be named cjc: the Linux runtime reserves that basename
// for native C++ cjc and otherwise excludes managed frames from GC root scanning.
// `cjpm build success` followed by a missing binary says nothing about which of
// the two it is: a build that quietly produced no executable, or one that named
// it something else. Report the directory so the next run answers that on its
// own -- a CI round trip here costs hours.
const seed = 'target/release/bin/cjcj::cjc';
try {
  await fs.access(seed);
} catch {
  const binDir = 'target/release/bin';
  let listing;
  try {
    listing = (await fs.readdir(binDir)).sort();
  } catch (error) {
    listing = `<${binDir} unreadable: ${error.code || error.message}>`;
  }
  throw new Error(
    `cjpm build reported success but ${seed} does not exist.\n` +
    `${binDir} contains: ${JSON.stringify(listing)}`,
  );
}
await $`install -m0755 ${seed} ${sdk}/bin/cjcj-stage1`;
await $`rm -f ${sdk}/bin/cjc`;
await $`ln -s cjcj-stage1 ${sdk}/bin/cjc`;
const scanDir = await fs.mkdtemp(path.join(os.tmpdir(), 'cjcj-stage1-scan-'));
const scanJson = path.join(scanDir, 'scan.json');
await $`${sdk}/bin/cjc -p ${githubWorkspace}/packages/basic/src --scan-dependency > ${scanJson}`;
await $`grep -q '"package":"cjcj::basic"' ${scanJson}`;
await fs.rm(scanDir, {recursive: true, force: true});
await fs.rename(workspaceTomlBackup, workspaceToml);
await $`cjpm clean`;
