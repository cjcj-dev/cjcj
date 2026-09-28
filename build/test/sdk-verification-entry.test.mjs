import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';

// These are executable shell fixtures for the verification device, not a
// substitute for the final compiler/std hello acceptance on a rebuilt SDK.
test('verify CLI compiles with the packaged compiler in the activated SDK environment', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'sdk-verify-entry-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const sdk = path.join(root, 'software/cangjie');
  const host = path.join(root, 'host');
  const write = async (file, text, mode = 0o644) => {
    await fs.mkdir(path.dirname(file), {recursive: true});
    await fs.writeFile(file, text, {mode});
  };
  for (const [directory, identity] of [[sdk, 'PACKAGED'], [host, 'HOST']]) {
    await write(path.join(directory, 'bin/cjc'), `#!/bin/bash
set -e
printf '%s\\n' '${identity}' > compiler-observed
printf '%s\\n' "$CANGJIE_HOME" "$LD_LIBRARY_PATH" > environment-observed
printf '#!/bin/sh\\necho HELLO_FROM_${identity}\\n' > hello
chmod +x hello
`, 0o755);
  }
  await write(path.join(sdk, 'envsetup.sh'), `export CANGJIE_HOME='${sdk}'
export PATH="$CANGJIE_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$CANGJIE_HOME/runtime/lib:$CANGJIE_HOME/tools/lib"
`);
  const pin = await fs.readFile(new URL('../../ci/host_sdk_pin.env', import.meta.url), 'utf8');
  const toolchain = pin.match(/^CJCJ_TOOLCHAIN=(\S+)$/m)[1];
  const home = path.join(root, 'home');
  await fs.mkdir(path.join(home, '.cjv/toolchains', toolchain), {recursive: true});
  // This existing gate is part of the CLI entry, even with shell compiler fixtures.
  await write(path.join(sdk, 'runtime/lib/linux_x86_64_cjnative/gc_unit_gate.status'),
    'LANGUAGE_TESTS=LANGUAGE_DONE\nGATE=PASS\n');
  const result = spawnSync(process.execPath, [path.resolve('build/cli.mjs'),
    '--workspace', root, '--target', 'linux-x64', 'verify'], {
    encoding: 'utf8', env: {...process.env, HOME: home,
      CJCJ_SRCBUILD_HOST_SDK: host, LD_LIBRARY_PATH: '/runner/incorrect/llvm',
      CANGJIE_HOME: host, PATH: `${host}/bin:${process.env.PATH}`},
  });
  assert.ifError(result.error);
  console.log(`VERIFY_ENTRY_RESULT_ASSERT_REACHED rc=${result.status}`);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  const work = path.join(root, 'verify');
  const identity = (await fs.readFile(path.join(work, 'compiler-observed'), 'utf8')).trim();
  const environment = (await fs.readFile(path.join(work, 'environment-observed'), 'utf8')).trim().split('\n');
  console.log(`VERIFY_SELECTED_COMPILER_ASSERT_REACHED ${identity}`);
  assert.equal(identity, 'PACKAGED');
  console.log(`VERIFY_LOADER_ENV_ASSERT_REACHED ${JSON.stringify(environment)}`);
  assert.deepEqual(environment, [sdk, `${sdk}/runtime/lib:${sdk}/tools/lib`]);
  assert.match(result.stdout + result.stderr, /HELLO_FROM_PACKAGED/);
});
