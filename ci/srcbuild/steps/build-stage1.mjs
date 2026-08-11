#!/usr/bin/env zx

import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {getTarget} from '../../../build/lib/targets.mjs';
import {platformizeCjcToml} from '../../platform_matrix/link_option.mjs';

$.stdio = 'inherit';

const workspace = process.env.CANGJIE_WORKSPACE;
const githubWorkspace = process.env.GITHUB_WORKSPACE;
const targetKey = process.env.CJCJ_SRCBUILD_TARGET;
const hostCompiler = process.env.CJCJ_SRCBUILD_HOST_CJC;
if (!workspace || !githubWorkspace || !targetKey || !hostCompiler) {
  throw new Error(
    'CANGJIE_WORKSPACE, GITHUB_WORKSPACE, CJCJ_SRCBUILD_TARGET and CJCJ_SRCBUILD_HOST_CJC are required',
  );
}
const target = getTarget(targetKey);
if (process.platform !== target.spec.nodePlatform || process.arch !== target.spec.nodeArch) {
  throw new Error(`target ${targetKey} requires ${target.spec.nodePlatform}/${target.spec.nodeArch}`);
}

const sdk = `${workspace}/software/cangjie`;
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
const oracleEnv = {
  ...process.env,
  PATH: `${path.dirname(hostCompiler)}${path.delimiter}${process.env.PATH || ''}`,
};
await $({env: oracleEnv})`cjpm build`;

// Put the seed under the SDK so <exe>/../runtime resolves. The C++ oracle stays
// in cangjie_compiler/output/bin and is never copied into the SDK tree.
// The mapped seed must not be named cjc: the Linux runtime reserves that basename
// for native C++ cjc and otherwise excludes managed frames from GC root scanning.
await $`install -m0755 target/release/bin/cjcj::cjc ${sdk}/bin/cjcj-stage1`;
await $`rm -f ${sdk}/bin/cjc`;
await $`ln -s cjcj-stage1 ${sdk}/bin/cjc`;
const scanDir = await fs.mkdtemp(path.join(os.tmpdir(), 'cjcj-stage1-scan-'));
const scanJson = path.join(scanDir, 'scan.json');
await $`${sdk}/bin/cjc -p ${githubWorkspace}/packages/basic/src --scan-dependency > ${scanJson}`;
await $`grep -q '"package":"cjcj::basic"' ${scanJson}`;
await fs.rm(scanDir, {recursive: true, force: true});
await fs.rename(workspaceTomlBackup, workspaceToml);
await $`cjpm clean`;
