import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';

export function linkedPeFixture(t, symbol) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pe-symbols-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const evidence = process.env.WINDOWS_PE_EVIDENCE && path.join(process.env.WINDOWS_PE_EVIDENCE, symbol);
  if (evidence) fs.mkdirSync(evidence, {recursive: true});
  const records = [];
  function run(program, args) {
    const pinned = path.join(program === 'clang' ? '/usr/lib/llvm-15/bin' : '/usr/lib/llvm-14/bin', program);
    const executable = fs.existsSync(pinned) ? pinned : program;
    const r = spawnSync(executable, args, {cwd: root, encoding: 'utf8'});
    records.push({program, executable, args, rc: r.status, signal: r.signal, error: r.error?.message, stdout: r.stdout, stderr: r.stderr});
    if (evidence) fs.writeFileSync(path.join(evidence, 'commands.json'), JSON.stringify(records, null, 2));
    assert.equal(r.status, 0, JSON.stringify(records.at(-1)));
  }
  fs.writeFileSync(path.join(root, 'runtime.c'), `__declspec(dllexport) int ${symbol} = 1;\n`);
  fs.writeFileSync(path.join(root, 'consumer.c'), `__declspec(dllimport) extern volatile int ${symbol};\nint entry(void) { return ${symbol}; }\n`);
  run('clang', ['--target=x86_64-pc-windows-msvc', '-c', 'runtime.c', '-o', 'runtime.obj']);
  run('lld-link', ['/dll', '/noentry', '/out:runtime.dll', '/implib:runtime.lib', 'runtime.obj']);
  run('clang', ['--target=x86_64-pc-windows-msvc', '-c', 'consumer.c', '-o', 'consumer.obj']);
  run('lld-link', ['/entry:entry', '/subsystem:console', '/nodefaultlib', '/out:consumer.exe', 'consumer.obj', 'runtime.lib']);
  if (evidence) {
    const files = {};
    for (const name of fs.readdirSync(root)) {
      const bytes = fs.readFileSync(path.join(root, name));
      files[name] = {sha256: createHash('sha256').update(bytes).digest('hex'), bytes: bytes.length};
      fs.writeFileSync(path.join(evidence, name), bytes);
    }
    fs.writeFileSync(path.join(evidence, 'files.json'), JSON.stringify(files, null, 2));
  }
  return root;
}
