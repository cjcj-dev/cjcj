import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {parseCpus,limit,validate} from './envelope.mjs';

test('suite envelope inherits a narrow process affinity and the tightest ancestor quota',()=>{
  const selected=limit(parseCpus('8-11'),['max 100000','350000 100000','125000 100000']);
  assert.deepEqual(selected,{affinity:[8,9,10,11],quota:125000,period:100000});
  assert.deepEqual(limit([9,10],['max 100000','400000 100000']),{affinity:[9,10],quota:200000,period:100000});
  assert.deepEqual(limit([9],['50000 100000']),{affinity:[9],quota:50000,period:100000});
});
test('suite envelope rejects CPU and quota expansion while allowing narrower child bounds',()=>{
  const parent={affinity:[8,9,10,11],quota:200000,period:100000};
  assert.deepEqual(validate({affinity:[9],quota:100000,period:100000},parent),{affinity:[9],quota:100000,period:100000});
  for(const request of [
    {affinity:[8,12],quota:100000,period:100000},
    {affinity:[8,9],quota:200001,period:100000},
    {affinity:[8],quota:200000,period:100000},
    {affinity:[],quota:100000,period:100000},
    {affinity:[8,8],quota:100000,period:100000},
  ])assert.throws(()=>validate(request,parent),/request exceeds parent affinity\/quota/);
});
function envelope(mode, request, layout = 'v2') {
  const fixture = new URL('./fixtures/envelope-cgroup.mjs', import.meta.url);
  fixture.searchParams.set('layout', layout);
  const args = ['--import', fixture.href, fileURLToPath(new URL('./envelope.mjs', import.meta.url)), mode];
  if (request) args.push(JSON.stringify(request));
  const result = spawnSync(process.execPath, args, {encoding: 'utf8'});
  assert.ifError(result.error);
  assert.equal(result.signal, null);
  return result;
}
test('missing unified cgroup membership still rejects a formal launch plan', () => {
  const result = envelope('plan', undefined, 'v1');
  assert.equal(result.status, 1, result.stdout);
  assert.match(result.stderr, /CPU_ENVELOPE: cgroup v2 required/);
});
test('formal launch options reject an excessive request before creating a systemd scope', () => {
  const planned = envelope('plan');
  assert.equal(planned.status, 0, planned.stderr);
  const selected = JSON.parse(planned.stdout);
  assert.deepEqual(selected.affinity, [8, 9]);
  assert.equal(selected.quota, 125000);
  const normal = envelope('options', selected);
  assert.equal(normal.status, 0, normal.stderr);
  assert.deepEqual(JSON.parse(normal.stdout), ['AllowedCPUs=8,9', 'CPUQuota=125%', 'CPUQuotaPeriodSec=0.1s']);
  for (const request of [{...selected, quota: 150000}, {...selected, affinity: [8, 10]}]) {
    const excessive = envelope('options', request);
    assert.equal(excessive.status, 1, excessive.stdout + excessive.stderr);
    assert.match(excessive.stderr, /request exceeds parent affinity\/quota/);
  }
  const restored = envelope('options', selected);
  assert.equal(restored.status, 0, restored.stderr);
  assert.deepEqual(JSON.parse(restored.stdout), JSON.parse(normal.stdout));
});
