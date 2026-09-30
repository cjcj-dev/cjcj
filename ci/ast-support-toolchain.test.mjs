import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const root = path.resolve(import.meta.dirname, '..');

async function configureProbe() {
  const work = await fs.mkdtemp(path.join(os.tmpdir(), 'ast-toolchain-'));
  const source = path.join(work, 'source');
  const build = path.join(work, 'build');
  const toolchain = path.join(work, 'windows.cmake');
  try {
    await fs.mkdir(source);
    await fs.writeFile(toolchain, 'set(CMAKE_SYSTEM_NAME Windows)\n');
    await fs.writeFile(path.join(source, 'CMakeLists.txt'), `
cmake_minimum_required(VERSION 3.16)
project(ASTToolchainProbe LANGUAGES NONE)
file(WRITE "\${CMAKE_BINARY_DIR}/system.txt" "\${CMAKE_SYSTEM_NAME}")
file(WRITE "\${CMAKE_BINARY_DIR}/environment.txt" "$ENV{CMAKE_TOOLCHAIN_FILE}")
message(FATAL_ERROR "AST_TOOLCHAIN_PROBE_COMPLETE")
`);
    const result = spawnSync('bash', [path.join(root, 'ci/build_ast_support.sh'),
      source, build, path.join(work, 'out'), path.join(work, 'sdk')], {
      encoding: 'utf8', env: {...process.env, CMAKE_TOOLCHAIN_FILE: toolchain},
    });
    assert.equal(result.status, 1, result.stdout + result.stderr);
    assert.match(result.stdout + result.stderr, /AST_TOOLCHAIN_PROBE_COMPLETE/);
    return {
      system: await fs.readFile(path.join(build, 'system.txt'), 'utf8'),
      environment: await fs.readFile(path.join(build, 'environment.txt'), 'utf8'),
    };
  } finally {
    await fs.rm(work, {recursive: true, force: true});
  }
}

test('AST configure keeps the Windows target toolchain explicit', async () => {
  const result = await configureProbe();
  console.log(`AST_TARGET_SYSTEM=${result.system}`);
  assert.equal(result.system, 'Windows');
});

test('AST subprocess environment does not retarget host ExternalProject builds', async () => {
  const result = await configureProbe();
  console.log(`AST_CHILD_TOOLCHAIN=${JSON.stringify(result.environment)}`);
  assert.equal(result.environment, '');
});
