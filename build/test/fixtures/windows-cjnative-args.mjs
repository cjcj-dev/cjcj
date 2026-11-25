#!/usr/bin/env zx
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

// Evaluate the MinGW branch from the compiler actually handed to configure.
// Bound it by its unchanged neighbours so nested conditions run as written.
export function assertCjnativeHostArgs(compiler, work) {
  const source = fs.readFileSync(path.join(compiler, 'third_party/CMakeLists.txt'), 'utf8').replaceAll('\r\n', '\n');
  const block = /list\(APPEND LLVM_CMAKE_ARGS -DLLVM_LINK_LLVM_DYLIB=ON\)\n([\s\S]+?)\n *list\(APPEND LLVM_CMAKE_ARGS -DCMAKE_EXE_LINKER_FLAGS=/.exec(source);
  assert.ok(block, 'missing cjnative MinGW configuration');
  const script = path.join(work, 'cjnative-host-args.cmake');
  fs.writeFileSync(script, [
    'set(MINGW ON)', 'set(CMAKE_HOST_WIN32 ${windows_host})', block[1],
    'foreach(arg IN LISTS LLVM_CMAKE_ARGS)', '  message("arg=${arg}")', 'endforeach()', '',
  ].join('\n'));
  for (const host of ['OFF', 'ON']) {
    const run = spawnSync('cmake', ['-Dwindows_host=' + host, '-P', script], {encoding: 'utf8'});
    assert.equal(run.status, 0, run.stderr);
    const args = run.stderr.split(/\r?\n/).filter(line => line.startsWith('arg=')).map(line => line.slice(4));
    assert.ok(args.includes('-DLLVM_HOST_TRIPLE=x86_64-w64-mingw32'), 'MinGW must keep its LLVM triple');
    for (const flag of ['-DCMAKE_SYSTEM_NAME=Windows', '-DCROSS_TOOLCHAIN_FLAGS_LLVM_NATIVE=-Wno-dev|-Wno-deprecated'])
      assert.equal(args.includes(flag), host === 'OFF', `CMAKE_HOST_WIN32=${host}: ${flag}`);
  }
}
