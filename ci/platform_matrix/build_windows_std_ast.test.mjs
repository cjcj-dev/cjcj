#!/usr/bin/env zx

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

const producer = path.join(import.meta.dirname, 'build_windows_std_ast.mjs');
const zxBin = process.env.ZX_BIN || 'zx';
const temporaryRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'stdast-gen-'));
const schemaBytes = 'namespace Cj;\nroot_type Schema;\n';
const headerBytes = '/* StdAstFormat_generated.h generation-a */\n';
const publicBytes = '/* AST.h generation-a */\n';
const archiveBytes = 'ast-support-generation-a\n';
const schemaDigest = crypto.createHash('sha256').update(schemaBytes).digest('hex');

const failures = [];
try {
  const source = await fs.readFile(producer, 'utf8');
  if (source.includes('NodeFormat.fbs') || source.includes('shallowClone') || source.includes('llvm-ar')) {
    failures.push('producer still names NodeFormat.fbs, shallowClone, or llvm-ar');
  }

  const writeFake = async (name, body) => {
    const file = path.join(temporaryRoot, 'toolchain', 'bin', name);
    await fs.mkdir(path.dirname(file), {recursive: true});
    await fs.writeFile(file, body);
    await fs.chmod(file, 0o755);
  };
  await writeFake('x86_64-w64-mingw32-clang++', `#!/bin/bash
set -euo pipefail
out=""
prev=""
for arg in "$@"; do
  if [[ "$prev" == "-o" ]]; then out="$arg"; fi
  prev="$arg"
done
mkdir -p "$(dirname "$out")"
printf 'obj\\n' > "$out"
if [[ -n "\${STDAST_COMPILE_MARKER:-}" ]]; then printf 'compiled\\n' > "$STDAST_COMPILE_MARKER"; fi
`);
  await writeFake('x86_64-w64-mingw32-gcc', `#!/bin/bash
set -euo pipefail
out=""
prev=""
for arg in "$@"; do
  if [[ "$prev" == "-o" ]]; then out="$arg"; fi
  prev="$arg"
done
mkdir -p "$(dirname "$out")"
printf 'dll\\n' > "$out"
`);
  await writeFake('llvm-readobj', `#!/bin/bash
set -euo pipefail
kind="$1"
dll="$2"
ours=0
case "$dll" in
  *stdast-work*) ours=1 ;;
esac
if [[ "$kind" == "--coff-exports" ]]; then
  printf '  Name: CJ_AST_Bar\\n  Name: CJ_AST_Foo\\n'
  if [[ "$ours" == 1 && "\${STDAST_GUARD_DIVERGE:-}" != 1 ]]; then
    printf '  Name: CJ_MacroCall_RegisterHostCallbacks\\n'
  fi
elif [[ "$kind" == "--coff-imports" ]]; then
  printf '  Name: libcangjie-runtime.dll\\n  Symbol: CJ_Runtime_Anchor\\n'
else
  exit 2
fi
`);

  const materialize = async (name, mutate) => {
    const root = path.join(temporaryRoot, name);
    await fs.rm(root, {recursive: true, force: true});
    const files = {
      'compiler/schema/StdAstFormat.fbs': schemaBytes,
      'artifact/include/flatbuffers/StdAstFormat_generated.h': headerBytes,
      'artifact/include/cangjie/AST.h': publicBytes,
      'artifact/libcangjie-ast-support.a': archiveBytes,
      'sdk/schema/StdAstFormat.fbs': schemaBytes,
      'sdk/include/flatbuffers/StdAstFormat_generated.h': headerBytes,
      'sdk/include/cangjie/AST.h': publicBytes,
      'sdk/lib/windows_x86_64_cjnative/libcangjie-ast-support.a': archiveBytes,
      'sdk/third_party/flatbuffers/include/flatbuffers/flatbuffers.h': '/* flatbuffers */\n',
      'sdk/runtime/lib/windows_x86_64_cjnative/libcangjie-std-core.dll': 'core\n',
      'sdk/runtime/lib/windows_x86_64_cjnative/libcangjie-std-collection.dll': 'collection\n',
      'sdk/runtime/lib/windows_x86_64_cjnative/libcangjie-std-sort.dll': 'sort\n',
      'sdk/runtime/lib/windows_x86_64_cjnative/libcangjie-std-math.dll': 'math\n',
      'sdk/runtime/lib/windows_x86_64_cjnative/libboundscheck.dll': 'bounds\n',
      'sdk/runtime/lib/windows_x86_64_cjnative/libcangjie-std-ast.dll': 'official\n',
      'runtime-install/lib/windows_x86_64_cjnative/section.o': 'section\n',
      'runtime-install/lib/windows_x86_64_cjnative/cjstart.o': 'cjstart\n',
      'runtime-install/runtime/lib/windows_x86_64_cjnative/libcangjie-runtime.dll': 'runtime\n',
      'runtime-source/stdlib/libs/std/ast/native/ast_api.cpp': 'int CJ_MacroCall_RegisterHostCallbacks(){return 0;}\n',
      'stdlib-out/ast.o': 'ast-object\n',
      'stdlib-out/std-ast.provenance': `schema_sha256=${schemaDigest}\ncompiler=174db8f40d5efddee63c47a3162bbf676bc227a0\n`,
    };
    mutate(files);
    for (const [rel, body] of Object.entries(files)) {
      const file = path.join(root, rel);
      await fs.mkdir(path.dirname(file), {recursive: true});
      await fs.writeFile(file, body);
    }
    return root;
  };

  const runCase = async (name, mutate, extraEnv = {}) => {
    const root = await materialize(name, mutate);
    const marker = path.join(root, 'compile-marker');
    const envExtra = typeof extraEnv === 'function' ? extraEnv(root) : extraEnv;
    const result = spawnSync(zxBin, [producer], {
      encoding: 'utf8',
      env: {
        ...process.env,
        RUNTIME_SOURCE: path.join(root, 'runtime-source'),
        RUNTIME_TOOLCHAIN: path.join(temporaryRoot, 'toolchain'),
        CANGJIE_HOME: path.join(root, 'sdk'),
        COMPILER_SOURCE: path.join(root, 'compiler'),
        AST_SUPPORT_ARTIFACT: path.join(root, 'artifact'),
        RUNTIME_INSTALL: path.join(root, 'runtime-install'),
        STDLIB_AST_OBJECT: path.join(root, 'stdlib-out', 'ast.o'),
        STDLIB_AST_PROVENANCE: path.join(root, 'stdlib-out', 'std-ast.provenance'),
        STDAST_WORKDIR: path.join(root, 'stdast-work'),
        STDAST_COMPILE_MARKER: marker,
        ...envExtra,
      },
      maxBuffer: 8 * 1024 * 1024,
    });
    const installed = await fs.stat(path.join(root, 'runtime-install', 'runtime', 'lib', 'windows_x86_64_cjnative', 'libcangjie-std-ast.dll')).then(() => true, () => false);
    const compiled = await fs.stat(marker).then(() => true, () => false);
    console.log(`SELFTEST_CASE=${name} rc=${result.status} compiled=${compiled} installed=${installed}`);
    process.stdout.write(result.stdout || '');
    process.stderr.write(result.stderr || '');
    return {result, installed, compiled};
  };

  const schema = await runCase('schema-mismatch', (files) => {
    files['sdk/schema/StdAstFormat.fbs'] = 'namespace Cj;\nroot_type Other;\n';
  });
  console.log('ASSERT generation schema reject');
  if (schema.result.status !== 4
      || !schema.result.stdout.includes('WINDOWS_STDAST_GENERATION_REJECT kind=schema')
      || schema.result.stdout.includes('kind=archive')
      || schema.result.stdout.includes('kind=header')
      || schema.compiled
      || schema.installed) {
    console.log(`ASSERT_FAIL generation schema reject status=${schema.result.status} compiled=${schema.compiled} installed=${schema.installed}`);
    failures.push('schema mismatch was not rejected alone before compile');
  }

  const archive = await runCase('archive-mismatch', (files) => {
    files['sdk/lib/windows_x86_64_cjnative/libcangjie-ast-support.a'] = 'official-archive\n';
  });
  console.log('ASSERT generation archive reject');
  if (archive.result.status !== 7
      || !archive.result.stdout.includes('WINDOWS_STDAST_GENERATION_REJECT kind=archive')
      || !archive.result.stdout.includes('WINDOWS_STDAST_GENERATION_PASS kind=schema')
      || !archive.result.stdout.includes('WINDOWS_STDAST_GENERATION_PASS kind=header')
      || archive.result.stdout.includes('WINDOWS_STDAST_GENERATION_REJECT kind=schema')
      || archive.compiled
      || archive.installed) {
    console.log(`ASSERT_FAIL generation archive reject status=${archive.result.status}`);
    failures.push('archive mismatch was not rejected alone before compile');
  }

  const header = await runCase('header-mismatch', (files) => {
    files['sdk/include/flatbuffers/StdAstFormat_generated.h'] = '/* other header */\n';
  });
  console.log('ASSERT generation header reject');
  if (header.result.status !== 5
      || !header.result.stdout.includes('WINDOWS_STDAST_GENERATION_REJECT kind=header')
      || !header.result.stdout.includes('WINDOWS_STDAST_GENERATION_PASS kind=schema')
      || header.result.stdout.includes('REJECT kind=archive')
      || header.compiled
      || header.installed) {
    console.log(`ASSERT_FAIL generation header reject status=${header.result.status}`);
    failures.push('header mismatch was not rejected alone before compile');
  }

  const object = await runCase('ast-object-mismatch', (files) => {
    files['stdlib-out/std-ast.provenance'] = `schema_sha256=${'ab'.repeat(32)}\n`;
  });
  console.log('ASSERT generation ast_object reject');
  if (object.result.status !== 8
      || !object.result.stdout.includes('WINDOWS_STDAST_GENERATION_REJECT kind=ast_object')
      || !object.result.stdout.includes('WINDOWS_STDAST_GENERATION_PASS kind=archive')
      || object.compiled
      || object.installed) {
    console.log(`ASSERT_FAIL generation ast_object reject status=${object.result.status}`);
    failures.push('ast object provenance mismatch was not rejected before compile');
  }

  const official = await runCase('official-ast-object', (files) => {
    files['sdk/lib/windows_x86_64_cjnative/ast.o'] = 'official-ast\n';
  }, (root) => ({
    STDLIB_AST_OBJECT: path.join(root, 'sdk', 'lib', 'windows_x86_64_cjnative', 'ast.o'),
  }));
  console.log('ASSERT generation official ast object reject');
  if (official.result.status !== 8
      || !official.result.stdout.includes('WINDOWS_STDAST_GENERATION_REJECT kind=ast_object')
      || official.compiled) {
    console.log(`ASSERT_FAIL generation official ast object status=${official.result.status}`);
    failures.push('official lib ast.o was not rejected');
  }

  const guard = await runCase('guard-diverge', () => {}, {STDAST_GUARD_DIVERGE: '1'});
  console.log('ASSERT dll guard reject');
  if (guard.result.status !== 3
      || !guard.result.stdout.includes('WINDOWS_STDAST_GUARD')
      || !guard.result.stdout.includes('WINDOWS_STDAST_GENERATION_PASS kind=archive')
      || guard.installed) {
    console.log(`ASSERT_FAIL dll guard status=${guard.result.status} installed=${guard.installed}`);
    failures.push('DLL export guard did not reject a divergent surface');
  }

  const match = await runCase('match', () => {});
  console.log('ASSERT generation match installs');
  if (match.result.status !== 0
      || !match.result.stdout.includes('WINDOWS_STDAST_GENERATION_PASS kind=schema')
      || !match.result.stdout.includes('WINDOWS_STDAST_GUARD')
      || !match.result.stdout.includes('added=CJ_MacroCall_RegisterHostCallbacks')
      || !match.compiled
      || !match.installed) {
    console.log(`ASSERT_FAIL generation match status=${match.result.status} compiled=${match.compiled} installed=${match.installed}`);
    failures.push('matching generation did not pass the guard and install');
  }
} finally {
  await fs.rm(temporaryRoot, {recursive: true, force: true});
}

if (failures.length) {
  console.error(`SELFTEST_RESULT=FAIL ${failures.join('; ')}`);
  process.exit(1);
}
console.log('SELFTEST_RESULT=PASS');
