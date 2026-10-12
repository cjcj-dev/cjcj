#!/usr/bin/env zx
// Explicit partial-input qualification. This never produces a native receipt.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {compileCjdbShim, CJDB_SHIM_CXX_FLAGS} from './sdk-cjdb-producer.mjs';

const partial = process.env.CJDB_SHIM_PARTIAL;
const output = process.env.CJDB_SHIM_OUTPUT;
const cjo = process.env.CJDB_SHIM_CJO;
const repository = path.resolve(import.meta.dirname, '../..');

test('fixed Cjo schema generates a complete shim and reads a real CJOF package',
  {skip: !partial || !output || !cjo}, async () => {
    await fs.mkdir(output, {recursive: true});
    const commands = [];
    const run = async (argv, {env = process.env, expected = 0} = {}) => {
      const start = new Date().toISOString();
      const result = spawnSync(argv[0], argv.slice(1), {env, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024});
      const index = commands.length;
      commands.push({argv, start, rc: result.status, signal: result.signal, error: result.error?.message});
      await fs.writeFile(path.join(output, `${index}.stdout`), result.stdout || '');
      await fs.writeFile(path.join(output, `${index}.stderr`), result.stderr || '');
      await fs.writeFile(path.join(output, 'commands.json'), JSON.stringify(commands, null, 2));
      assert.equal(result.status, expected, `target command ${index}: ${argv.join(' ')}\n${result.stderr}`);
      return result.stdout;
    };
    const digest = async file => createHash('sha256').update(await fs.readFile(file)).digest('hex');
    const build = path.join(partial, 'build/compiler');
    const compiler = path.join(partial, 'source-inputs/compiler');
    const llvm = path.join(partial, 'source-inputs/llvm');
    const llvmBuild = path.join(build, 'third_party/cjnative-prefix/src/cjnative-build');
    const flatbuffers = path.join(compiler, 'third_party/flatbuffers');
    const clang = '/usr/bin/clang++';
    const object = path.join(output, 'shim.o');
    await compileCjdbShim({flatc: path.join(build, 'bin/flatc'), compiler, llvm, llvmBuild,
      flatbuffers, generatedHeaders: output, repository, object, clang}, run);
    const so = path.join(output, 'libcjofshim.so');
    await run([clang, '-shared', object, `-L${llvmBuild}/lib`, '-lLLVM-15',
      `-Wl,-rpath,${llvmBuild}/lib`, '-o', so]);
    const soSha256 = await digest(so);
    const identities = {partialStatus: 'unsealed qualification input', repository, cxxFlags: CJDB_SHIM_CXX_FLAGS,
      object: {path: object, sha256: await digest(object)},
      shim: {path: so, sha256: soSha256}, probe: 'NOT_LINKED',
      llvm: {path: path.join(llvmBuild, 'lib/libLLVM-15.so'), sha256: await digest(path.join(llvmBuild, 'lib/libLLVM-15.so'))},
      cjo: {path: cjo, sha256: await digest(cjo)}};
    await fs.writeFile(path.join(output, 'identities.json'), JSON.stringify(identities, null, 2));
    const probe = path.join(output, 'surface_probe');
    await run([clang, ...CJDB_SHIM_CXX_FLAGS,
      `-I${flatbuffers}/include`, `-I${output}`, path.join(repository, 'test/cjoffi_probe/surface_probe.cpp'),
      `-L${output}`, '-lcjofshim', `-Wl,-rpath,${output}`, '-o', probe]);
    identities.probe = {path: probe, sha256: await digest(probe)};
    await fs.writeFile(path.join(output, 'identities.json'), JSON.stringify(identities, null, 2));
    await run(['/usr/bin/ldd', probe]);
    const result = await run([probe, cjo], {env: {...process.env, LD_DEBUG: 'libs'}});
    // RESULT D means the actual shim-produced fingerprint equals the independent
    // manual reader's values. A/B/C are classifications, not successful equality.
    console.log(result.trim());
    assert.match(result, /^RESULT\tD\tchecks=[1-9][0-9]*\tgroups=[1-9][0-9]*\t/m,
      'target CJOF read surface equality');
    assert.match(result, /SUMMARY\tN=1\tA=0\tB=0\tC=0\tD=1\tUNKNOWN=0/);
    assert.doesNotMatch(result, /^(?:DIFF|MEMORY_ALERT)\t/m);
    const invalid = path.join(output, 'invalid.cjo');
    const bytes = await fs.readFile(cjo); bytes[4] ^= 1;
    await fs.writeFile(invalid, bytes);
    const rejected = await run([probe, invalid], {expected: 2});
    console.log(rejected.trim());
    assert.match(rejected, /^RESULT\t\?\tchecks=0\tgroups=0\t/m,
      'target Verify and View both reject the actual incorrect CJOF identifier');
    assert.match(rejected, /SUMMARY\tN=1\tA=0\tB=0\tC=0\tD=0\tUNKNOWN=1/,
      'target incorrect CJOF identifier rejected');
    assert.doesNotMatch(rejected, /^(?:DIFF|MEMORY_ALERT)\t/m);
    console.log('TARGET_ASSERTIONS_EXECUTED schema-compile read-equality invalid-identifier');
  });
