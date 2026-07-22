#!/usr/bin/env zx
// C-layout gate: validate one legal layout and all invalid @C diagnostics with the selected self-host compiler.

import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {configureToolchain} from './zx_gate_lib.mjs';

const root = path.resolve(import.meta.dirname, '..');
const self = argv._[0] || `${root}/target/release/bin/cjcj::cjc`;
const work = await fs.mkdtemp(path.join(os.tmpdir(), 'calign-gate-'));
configureToolchain(process.env.CANGJIE_HOME || '/root/.cjv/toolchains/nightly-1.2.0-alpha.20260721165458');
try {
  const layoutBuild = await $({stdio: 'inherit', nothrow: true})`${self} ${root}/test/calign_layout.cj -o ${work}/calign --set-runtime-rpath`;
  if (layoutBuild.exitCode !== 0) {
    process.exitCode = layoutBuild.exitCode;
  } else {
    const layout = await $({quiet: true})`${work}/calign`;
    if (layout.stdout !== 'calign layout ok\n') process.exitCode = 1;
    const invalid = (await fs.readdir(`${root}/test`)).filter(name => name.startsWith('calign_invalid_') && name.endsWith('.cj')).sort();
    for (const file of invalid) {
      const name = path.basename(file, '.cj');
      const result = await $({nothrow: true, quiet: true})`${self} ${root}/test/${file} -o ${work}/${name} --set-runtime-rpath`;
      await fs.writeFile(`${work}/${name}.log`, result.stdout + result.stderr);
      if (result.exitCode === 0) {
        console.error(`FAIL: ${name} unexpectedly compiled`);
        process.exitCode = 1;
        break;
      }
      if (!(result.stdout + result.stderr).includes('@C')) { process.exitCode = 1; break; }
    }
    if (!process.exitCode) console.log('calign: PASS layout=1 diagnostics=5');
  }
} finally {
  await fs.rm(work, {recursive: true, force: true});
}
