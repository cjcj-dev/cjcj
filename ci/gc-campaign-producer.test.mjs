// Device integration only: an explicitly synthetic native child stands in for
// the pending #135 workload tuple. This does NOT qualify runtime correctness.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {gcLog, stdoutLog, RUNTIME_HEAD, CHECKSUM} from './gc-campaign-fixture.mjs';
const repo = path.resolve(import.meta.dirname, '..');
const hash = async file => crypto.createHash('sha256').update(await fs.readFile(file)).digest('hex');
function run(program, args) {
  return spawnSync(program, args, {encoding: 'utf8', maxBuffer: 4 * 1024 * 1024});
}
function cc(args) {
  const r = run('cc', args);
  assert.equal(r.status, 0, r.stderr);
}
async function device(t) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'gc-producer-device-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const artifact = async name => ({path: path.join(root, name), sha256: await hash(path.join(root, name))});
  const cString = text => JSON.stringify(text);
  const source = `#include <stdio.h>\n#include <stdlib.h>\nconst char fixture_stamp[]="CJRT-COMMIT:${RUNTIME_HEAD}";\nvoid gc_fixture(void) { fputs(${cString(gcLog())},stderr); }\n`;
  await fs.writeFile(path.join(root, 'runtime.c'), source);
  cc(['-shared', '-fPIC', path.join(root, 'runtime.c'), '-Wl,-soname,libcangjie-runtime.so', '-o', path.join(root, 'libcangjie-runtime.so')]);
  await fs.writeFile(path.join(root, 'control.c'), source.replace(`fputs(${cString(gcLog())},stderr);`, 'fputs("Missing remembered field at fixture\\n",stderr); abort();'));
  cc(['-shared', '-fPIC', path.join(root, 'control.c'), '-Wl,-soname,libcangjie-runtime.so', '-o', path.join(root, 'control.so')]);
  await fs.writeFile(path.join(root, 'bounds.c'), 'int fixture_bounds(void) { return 0; }\n');
  cc(['-shared', '-fPIC', path.join(root, 'bounds.c'), '-o', path.join(root, 'libboundscheck.so')]);
  await fs.writeFile(path.join(root, 'workload.c'), `#include <stdio.h>\nextern void gc_fixture(void);\nint main(void) { fputs(${cString(stdoutLog())},stdout); gc_fixture(); return 0; }\n`);
  for (const opt of ['O0', 'O2']) cc([`-${opt}`, path.join(root, 'workload.c'), `-L${root}`, '-lcangjie-runtime', '-o', path.join(root, opt)]);
  await fs.writeFile(path.join(root, 'tuple.json'), '{"device_fixture":true,"runtime_qualification":false}\n');
  await fs.writeFile(path.join(root, 'control.diff'), 'synthetic device input; not a runtime product cut\n');
  const inputs = {schema: 1, runtime_head: RUNTIME_HEAD, expected_checksum: CHECKSUM,
    runtime: await artifact('libcangjie-runtime.so'), boundscheck: await artifact('libboundscheck.so'),
    workloads: {O0: await artifact('O0'), O2: await artifact('O2')},
    toolchain_provenance: await artifact('tuple.json'), control_runtime: await artifact('control.so'), control_patch: await artifact('control.diff')};
  await fs.writeFile(path.join(root, 'inputs.json'), JSON.stringify(inputs));
  const allowed = (await fs.readFile('/proc/self/status', 'utf8')).match(/^Cpus_allowed_list:\s*(.+)$/m)[1];
  const cpus = allowed.split(',').flatMap(part => {
    const [lo, hi = lo] = part.split('-').map(Number);
    return Array.from({length: hi - lo + 1}, (_, i) => lo + i);
  });
  assert.ok(cpus.length >= 64, 'run this device integration on kkk2 >=64 CPUs');
  return {root, cores: cpus.slice(0, 64).join(',')};
}
for (const gate of ['G12', 'G14']) {
  test(`${gate} real producer CLI archives executed child output and gate consumes LOADAVG_END`, async t => {
    const {root, cores} = await device(t);
    const output = path.join(root, 'evidence');
    const args = [path.join(repo, `ci/release/${gate.toLowerCase()}.mjs`), '--inputs', path.join(root, 'inputs.json'), '--out', output, '--cores', cores];
    const producer = run(process.execPath, args);
    assert.equal(producer.status, 0, producer.stderr);
    const meta = await fs.readFile(path.join(output, 'meta.txt'), 'utf8');
    // The gate assertion, rather than a fatal existence precheck, bears the cut.
    const consumer = run(process.execPath, [path.join(repo, 'ci/release-gates.mjs'), gate, '--repo', repo, '--evidence', output, '--json']);
    assert.equal(consumer.status, 0, `TARGET_GATE_ARCHIVE_ASSERTION ${consumer.stdout}\n${consumer.stderr}`);
    assert.match(meta, /^LOADAVG_BEGIN=/m);
    assert.match(meta, /^LOADAVG_END=/m);
    assert.match(meta, /^UPTIME_END=/m);
    assert.match(await fs.readFile(path.join(output, 'RECIPE.txt'), 'utf8'), new RegExp(`SOURCE=ci/release/${gate.toLowerCase()}\\.mjs`));
    assert.equal(run(process.execPath, args).status, 2, 'reusing an output directory must fail');
    console.log(`TARGET_ASSERTION_EXECUTED producer-${gate} device-only`);
  });
}
