// Bind the copied official host SDK, keeping all loader paths in the handoff.
import fs from 'node:fs/promises';
import path from 'node:path';
import {getTarget} from '../../build/lib/targets.mjs';
const sdk = path.resolve(process.argv[2]);
const {spec} = getTarget(process.env.CJCJ_SRCBUILD_TARGET);
const dirs = ['third_party/llvm/lib', `runtime/lib/${spec.runtimeTuple}`, 'tools/lib'];
await fs.appendFile(process.env.GITHUB_ENV,
  `${spec.loaderEnv}=${dirs.map(dir => path.join(sdk, dir)).join(path.delimiter)}\n`);
// setup_sdk rewrites this link directory before the SDK is copied.
const toml = path.join(process.env.GITHUB_WORKSPACE, 'packages/cjc/cjpm.toml');
const original = path.join(process.env.HOME, '.cjv/toolchains', process.env.CJCJ_TOOLCHAIN);
await fs.writeFile(toml, (await fs.readFile(toml, 'utf8')).replaceAll(original, sdk));
