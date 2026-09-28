// Source-shaped unit fixtures, NOT current-runtime measurement evidence.
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {campaignPlan, campaignTables, observeRun, runKey} from '../build/lib/gc-campaign.mjs';
import {bindCampaign} from './release/gc-campaign.mjs';
export const SHA = 'a'.repeat(64);
export const RUNTIME_HEAD = 'b'.repeat(40);
export const CHECKSUM = '635925223159200';
export const UPTIME = ' 10:00:00 up 18 days, 1 user, load average: 1.00, 1.00, 1.00';
export async function write(root, file, value) {
  await fs.mkdir(path.dirname(path.join(root, file)), {recursive: true});
  await fs.writeFile(path.join(root, file), value);
}
export const gcLog = () => [
  '[GCLOG] v=5 rec=phase seq=1 gc_tag=y name=Concurrent_Mark kind=conc start_ns=10 ns=20',
  '[GCLOG] v=5 rec=phase seq=1 gc_tag=y name=Pause_Mark_End kind=pause start_ns=30 ns=2',
  '[GCLOG] v=5 rec=phase seq=1 gc_tag=y name=Concurrent_Select_Relocation_Set kind=conc start_ns=32 ns=3',
  '[GCLOG] v=5 rec=phase seq=1 gc_tag=y name=Concurrent_Relocate kind=conc start_ns=35 ns=5',
  '[GCLOG] v=5 rec=stw seq=1 gc_tag=y reason=Pause_Mark_End start_ns=30 wait_ns=1 held_ns=2',
  '[GCLOG] v=5 rec=generation seq=1 gc_tag=y name=Young_Generation start_ns=0 dur_ns=40 live_before=20 live_after=10',
  '[GCV2Minor] run=1 liveBytes=10 reclaimedBytes=10 pause=40 us', '',
].join('\n');
export const stdoutLog = () => Array.from({length: 12}, (_, i) => `WAVE_DONE wave=${i} checksum=${CHECKSUM}`).join('\n') +
  `\nNATURAL_WAVE_OK checksum=${CHECKSUM}\n`;
export function checkoutHead(checkout) {
  const result = spawnSync('git', ['-C', checkout, 'rev-parse', 'HEAD'], {encoding: 'utf8'});
  if (result.status !== 0) throw new Error(result.stderr);
  return result.stdout.trim();
}
export async function rebind(root, gate, checkout) {
  await bindCampaign(root, gate, checkoutHead(checkout), '2026-09-28T00:00:00Z', '2026-09-28T00:01:00Z');
  return JSON.parse(await fs.readFile(path.join(root, 'EVIDENCE_BINDING.json'), 'utf8'));
}
export async function campaignFixture(root, gate, checkout, mutate = () => {}) {
  const hash = text => crypto.createHash('sha256').update(text).digest('hex');
  const provenance = '{"fixture":true}\n';
  const patch = 'fixture remembered path cut\n';
  const inputs = {schema: 1, runtime_head: RUNTIME_HEAD, expected_checksum: CHECKSUM,
    runtime: {path: '/fixture/libcangjie-runtime.so', sha256: SHA}, boundscheck: {path: '/fixture/libboundscheck.so', sha256: SHA},
    workloads: {O0: {path: '/fixture/O0', sha256: SHA}, O2: {path: '/fixture/O2', sha256: 'c'.repeat(64)}},
    toolchain_provenance: {path: '/fixture/tuple.json', sha256: hash(provenance)},
    control_runtime: {path: '/fixture/cut/libcangjie-runtime.so', sha256: 'd'.repeat(64)},
    control_patch: {path: '/fixture/cut.diff', sha256: hash(patch)}};
  await write(root, 'inputs.json', JSON.stringify(inputs));
  await write(root, 'toolchain-provenance.json', provenance);
  if (gate === 'G12') await write(root, 'control.diff', patch);
  await write(root, 'RECIPE.txt', `SOURCE=ci/release/${gate.toLowerCase()}.mjs\n`);
  await write(root, 'meta.txt', [
    `HEAD=${checkoutHead(checkout)}`, 'GCLOG_SCHEMA=5', 'CORES=0-63', 'HEAP=256MB', 'N=20',
    'LOADAVG_BEGIN=1.00 1.00 1.00 1/100 100', 'LOADAVG_END=1.00 1.00 1.00 1/100 101',
    `UPTIME_BEGIN=${UPTIME}`, `UPTIME_END=${UPTIME}`, 'STARTED_UTC=2026-09-28T00:00:00Z', 'FINISHED_UTC=2026-09-28T00:01:00Z',
    `RUNTIME_SHA256=${SHA}`, `BOUNDSCHECK_SHA256=${SHA}`, `RUNTIME_STAMP=CJRT-COMMIT:${RUNTIME_HEAD}`,
    `EXPECTED_CHECKSUM=${CHECKSUM}`, `WORKLOAD_ELF_SHA256_O0=${SHA}`, `WORKLOAD_ELF_SHA256_O2=${'c'.repeat(64)}`, '',
  ].join('\n'));
  const receipts = [], rows = [];
  let combined = '';
  for (const item of [...campaignPlan(gate), ...(gate === 'G12' ? [{round: 0, load: 'O0', mode: 'control'}] : [])]) {
    const control = item.mode === 'control';
    const receipt = {...item, rc: control ? 134 : 0, signal: '', error: '', wall_ms: 10,
      env: {ZVerifyRemembered: item.mode === 'normal' ? '0' : '1', ZVerifyRoots: '1', ZVerifyMarking: '1',
        MRT_GC_LOG: '1', cjHeapSize: '256MB', CANGJIE_CJHEAP_SIZE: '256MB', LD_LIBRARY_PATH: '/fixture/lib'},
      argv: ['taskset', '-c', '0-63', '/usr/bin/timeout', '120s', inputs.workloads[item.load].path],
      uptime_begin: UPTIME, uptime_end: UPTIME, workload_sha256: inputs.workloads[item.load].sha256,
      runtime_sha256: control ? inputs.control_runtime.sha256 : SHA, gc_sources: ['stderr.log']};
    const data = {receipt, stdout: stdoutLog(), log: control ? 'Missing remembered field 0x100 in source 0x200\n' : gcLog()};
    mutate(data);
    const base = `runs/${runKey(item)}`;
    await write(root, `${base}/receipt.json`, JSON.stringify(receipt));
    await write(root, `${base}/stdout.log`, data.stdout);
    await write(root, `${base}/stderr.log`, data.log);
    await write(root, `${base}/gc.log`, data.log);
    await write(root, `${base}/loader.txt`, 'libcangjie-runtime.so => /fixture/lib/libcangjie-runtime.so (0x1000)\n');
    receipts.push(receipt);
    if (!control) { rows.push({receipt, observation: observeRun(data.stdout, data.log)}); combined += data.log + '\n'; }
  }
  for (const [file, text] of Object.entries(campaignTables(rows, gate))) await write(root, file, text);
  await write(root, 'gc.log', combined);
  await write(root, 'campaign.json', JSON.stringify({schema: 2, gate, receipts}));
  return rebind(root, gate, checkout);
}
