import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {parseCpus,limit,validate,plan,options} from './envelope.mjs';

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
test('formal launch options reject an excessive request before creating a systemd scope',()=>{
  const selected=plan(),normal=options(selected);
  assert(normal.includes('AllowedCPUs='+selected.affinity.join(',')));
  assert(normal.some(value=>value.startsWith('CPUQuota=')));
  console.log('CPU_ENVELOPE_LAUNCH_CONTROL_REACHED');
  const excessive=spawnSync(process.execPath,[fileURLToPath(new URL('./envelope.mjs',import.meta.url)),'options',JSON.stringify({...selected,quota:selected.quota*2})],{encoding:'utf8'});
  console.log('CPU_ENVELOPE_EXCESS_TARGET_REACHED rc='+excessive.status);
  assert.equal(excessive.status,1,excessive.stdout+excessive.stderr);
  assert.match(excessive.stderr,/request exceeds parent affinity\/quota/);
  assert.throws(()=>options({...selected,affinity:[...selected.affinity,Math.max(...selected.affinity)+1]}),/request exceeds parent affinity\/quota/);
  console.log('CPU_ENVELOPE_EXCESS_REJECTED');
  assert.deepEqual(options(selected),normal);
});
