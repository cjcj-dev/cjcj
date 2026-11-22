#!/usr/bin/env zx
import fs from 'node:fs/promises';
import path from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {runtimeSourceRepository} from '../../build/lib/runtime-source-inputs.mjs';
import {readSourcePins} from '../native-llvm-inputs.mjs';

const exec = promisify(execFile);
// The executor can bind the pinned upstream runtime to its registered Git
// common directory. An inputs file alone cannot declare a mirror equivalent.
export async function checkoutSourceRepository(name, checkout, commit, env) {
  const origin = await runtimeSourceRepository(checkout);
  const root = env.CJCJ_PINNED_RUNTIME_GIT_DIR;
  if (name !== 'runtime' || root === undefined) return origin;
  const {runtime: pin} = readSourcePins();
  if (!path.isAbsolute(root) || commit !== pin.RUNTIME_REF
      || !(origin === pin.RUNTIME_SRC_URL || path.isAbsolute(origin) || origin.startsWith('file://')))
    throw Error('NATIVE_RUNTIME_MIRROR_PIN');
  const {stdout} = await exec('git', ['-C', checkout, 'rev-parse', '--path-format=absolute',
    '--git-common-dir', '--absolute-git-dir', 'HEAD^{commit}']);
  const [common, gitDir, head] = stdout.trimEnd().split('\n');
  if (common !== await fs.realpath(root) || gitDir === common || head !== commit)
    throw Error('NATIVE_RUNTIME_MIRROR_CHECKOUT');
  return pin.RUNTIME_SRC_URL;
}
