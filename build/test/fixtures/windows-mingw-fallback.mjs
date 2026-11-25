#!/usr/bin/env zx
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

// Run the compiler's own include guard; a local module records inclusion
// without starting the legacy external project.
export function assertMinGWRuntimeFallback(compiler, work, runtimeFilesArg) {
  const source = fs.readFileSync(path.join(compiler, 'third_party/CMakeLists.txt'), 'utf8').replaceAll('\r\n', '\n');
  const block = source.match(/^    if\([^\n]*\)\n        include\(AddMinGWLibs\)\n    endif\(\)$/m);
  assert.ok(block, 'missing AddMinGWLibs block in the configured compiler');
  fs.writeFileSync(path.join(work, 'AddMinGWLibs.cmake'), 'message("included AddMinGWLibs")\n');
  const script = path.join(work, 'mingw-fallback.cmake');
  fs.writeFileSync(script, ['cmake_minimum_required(VERSION 3.20)', 'set(CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}")', block[0]].join('\n'));
  for (const [arg, expected] of [['-DCANGJIE_TOOLCHAIN_RUNTIME_FILES=', true], [runtimeFilesArg, false]]) {
    const run = spawnSync('cmake', ['-DMINGW=ON', arg, '-P', script], {encoding: 'utf8'});
    assert.equal(run.status, 0, run.stderr);
    assert.equal(run.stderr.trim(), expected ? 'included AddMinGWLibs' : '', 'AddMinGWLibs inclusion for ' + arg);
  }
}
