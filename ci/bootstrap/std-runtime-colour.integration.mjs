#!/usr/bin/env zx
// Formal guard qualification using an existing frozen verification input and
// the official H archive. This does not qualify a target std or compiler.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileDigest, readJson} from './sdk-io.mjs';

const planFile = process.env.STD_COLOUR_INPUTS;
const output = process.env.STD_COLOUR_OUTPUT;
test('formal std/runtime guard accepts fixed H and rejects a colour/H mismatch',
  async () => {
    assert.ok(planFile, 'STD_COLOUR_INPUTS is required');
    assert.ok(output, 'STD_COLOUR_OUTPUT is required');
    const plan = await readJson(planFile);
    const official=plan.host;
    assert.ok(official,'fixed H std input required');
    const std=official.std.path;
    assert.equal(await fileDigest(std),official.std.sha256,'std bytes match original fixed H input');
    for (const input of [plan.verification.colourRuntime, plan.verification.hostRuntime])
      assert.equal(await fileDigest(input.path), input.sha256, 'runtime bytes match frozen verification input');
    await fs.mkdir(output, {recursive: true});
    const command = (runtime, name) => {
      const argv = [new URL('./std-runtime-colour.mjs', import.meta.url).pathname,
        '--platform', plan.platform, '--colour-runtime', plan.verification.colourRuntime.path,
        '--host-runtime', plan.verification.hostRuntime.path, '--runtime', runtime,
        '--std', std, '--source', 'original-official-H'];
      const result = spawnSync(process.execPath, argv, {encoding:'utf8', maxBuffer:64*1024*1024});
      return fs.writeFile(path.join(output, name+'.json'), JSON.stringify({argv,rc:result.status,signal:result.signal,
        error:result.error?.message,stdout:result.stdout,stderr:result.stderr},null,2)).then(()=>result);
    };
    const accepted = await command(plan.verification.hostRuntime.path, 'host');
    assert.equal(accepted.status, 0, accepted.stderr);
    assert.match(accepted.stdout, /STD-RUNTIME-PAIR-OK .*runtime_symbols=none std_symbols=none/);
    console.log('STD_COLOUR_TARGET_ASSERTION_EXECUTED fixed-H-pair');
    const exports = accepted.stderr.match(/colour_only=([^\n]*)/)?.[1]?.split(',') || [];
    console.log(`STD_COLOUR_TARGET_ASSERTION_EXECUTED mask-export=${exports.filter(name=>name==='g_cjLoadBadMask').length}`);
    assert.equal(exports.filter(name=>name==='g_cjLoadBadMask').length, 1,
      'target native export reader preserves the actual mask identity');
    const rejected = await command(plan.verification.colourRuntime.path, 'mismatch');
    console.log(`STD_COLOUR_TARGET_ASSERTION_EXECUTED mismatch-rc=${rejected.status}`);
    assert.equal(rejected.status, 1, 'target formal guard must reject colour runtime with original H std');
    assert.match(rejected.stderr, /STD-RUNTIME-COLOUR-MISMATCH .*runtime_symbols=\S+ std_symbols=none/);
  });
