#!/usr/bin/env node

import {spawnSync} from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..', '..');
const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'lldwrap-test-'));
const windows = process.platform === 'win32';
const wrapper = path.join(temp, windows ? 'ld.lld.exe' : 'ld.lld');
const real = path.join(temp, windows ? 'ld.lld-real.exe' : 'ld.lld-real');
const compiler = process.env.CC || (windows ? 'C:\\msys64\\mingw64\\bin\\gcc.exe' : 'cc');
const fakeSource = path.join(temp, 'fake_lld.c');
const capture = path.join(temp, 'args.txt');

async function compile(source, output) {
  const result = spawnSync(compiler, ['-std=c11', '-O2', '-Wall', '-Wextra', source, '-o', output], {encoding: 'utf8'});
  if (result.status !== 0) {
    const probe = spawnSync(compiler, ['--version'], {encoding: 'utf8'});
    // R26 windows-2022: status=1 with BOTH streams empty while --version works —
    // the driver dies before its own diagnostics reach the node pipes. Re-run
    // -v through cmd with file redirection (bypasses pipe capture) to see which
    // driver stage stops, and compile a trivial source to split
    // toolchain-broken from source-specific.
    let verbose = '(n/a)';
    let trivial = '(n/a)';
    if (windows) {
      const vLog = path.join(temp, 'gcc-v.log');
      spawnSync('cmd.exe', ['/d', '/s', '/c',
        `""${compiler}" -v -std=c11 -O2 "${source}" -o "${output}" > "${vLog}" 2>&1"`], {encoding: 'utf8'});
      verbose = await fs.readFile(vLog, 'utf8').catch(() => '(no -v log written)');
      const tOut = path.join(temp, 'trivial.exe');
      const t = spawnSync(compiler, [fakeSource, '-o', tOut], {encoding: 'utf8'});
      trivial = `status=${t.status} error=${t.error ?? 'none'} stderr=${JSON.stringify(t.stderr)} produced=${await fs.access(tOut).then(() => true, () => false)}`;
    }
    throw new Error([
      `compile failed (${source}):`,
      `status=${result.status} signal=${result.signal} error=${result.error ?? 'none'}`,
      `stdout=${JSON.stringify(result.stdout)} stderr=${JSON.stringify(result.stderr)}`,
      `probe(--version): status=${probe.status} error=${probe.error ?? 'none'} stdout=${JSON.stringify(probe.stdout)} stderr=${JSON.stringify(probe.stderr)}`,
      `probe(trivial compile): ${trivial}`,
      `probe(-v via cmd redirect):\n${verbose}`,
    ].join('\n'));
  }
}

async function invoke(args, exitCode = 0) {
  await fs.rm(capture, {force: true});
  const result = spawnSync(wrapper, args, {
    encoding: 'utf8',
    env: {...process.env, LLDWRAP_CAPTURE: capture, LLDWRAP_EXIT: String(exitCode)},
  });
  const captured = (await fs.readFile(capture, 'utf8')).split('\n').filter(Boolean);
  return {result, captured};
}

try {
  await fs.writeFile(fakeSource, String.raw`#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    FILE *out = fopen(getenv("LLDWRAP_CAPTURE"), "wb");
    int i;
    if (!out) return 126;
    for (i = 1; i < argc; ++i) fprintf(out, "%s\n", argv[i]);
    fclose(out);
    return atoi(getenv("LLDWRAP_EXIT"));
}
`);
  await compile(path.join(root, 'ci', 'platform_matrix', 'lldwrap.c'), wrapper);
  await compile(fakeSource, real);

  const argvCase = await invoke(['-o', 'target/release/bin/cjcj::cjc.exe', '--flag']);
  if (argvCase.result.status !== 0 || argvCase.captured.join('|') !== '-o|target/release/bin/cjcj.exe|--flag') {
    throw new Error(`argv rewrite failed: ${JSON.stringify(argvCase)}`);
  }
  console.log('WRAP_TEST argv_rewrite=pass');

  const rsp = path.join(temp, 'link.rsp');
  await fs.writeFile(rsp, '"one/cjcj::cjc.exe"\n--keep\n"two/cjcj::cjc.exe"\n');
  const rspCase = await invoke([`@${rsp}`]);
  const rewrittenRsp = await fs.readFile(rsp, 'utf8');
  if (rspCase.result.status !== 0 || rewrittenRsp !== '"one/cjcj.exe"\n--keep\n"two/cjcj.exe"\n') {
    throw new Error(`rsp rewrite failed: status=${rspCase.result.status} content=${JSON.stringify(rewrittenRsp)}`);
  }
  console.log('WRAP_TEST rsp_rewrite=pass');

  const exitCase = await invoke(['--fail'], 37);
  if (exitCase.result.status !== 37) throw new Error(`exit passthrough failed: ${exitCase.result.status}`);
  console.log('WRAP_TEST exit_passthrough=pass');

  const cleanRsp = path.join(temp, 'clean.rsp');
  const cleanContent = '"target/release/bin/cjcj.exe"\n--unchanged\n';
  await fs.writeFile(cleanRsp, cleanContent);
  const cleanCase = await invoke(['--plain', `@${cleanRsp}`]);
  if (cleanCase.result.status !== 0 || await fs.readFile(cleanRsp, 'utf8') !== cleanContent || cleanCase.captured.join('|') !== `--plain|@${cleanRsp}`) {
    throw new Error(`no-match case changed: ${JSON.stringify(cleanCase)}`);
  }
  console.log('WRAP_TEST no_match=pass');
  console.log('WRAP_TESTS=4 PASS=4');
} finally {
  await fs.rm(temp, {recursive: true, force: true});
}
