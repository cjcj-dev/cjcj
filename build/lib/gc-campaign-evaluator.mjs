import crypto from 'node:crypto';
import {GC_RELEASE_FLOOR as floor} from './gc-release-floor.mjs';
import {campaignPlan, campaignTables, observeRun, runKey, MISSING_REMEMBERED, YOUNG_PHASES} from './gc-campaign.mjs';

const sha = text => crypto.createHash('sha256').update(text).digest('hex');
const hash = value => /^[0-9a-f]{64}$/.test(value || '');
function requireValue(condition, reason) { if (!condition) throw new Error(reason); }
function metadata(text) {
  const result = {};
  for (const line of text.trim().split(/\r?\n/)) {
    const i = line.indexOf('=');
    requireValue(i > 0, 'meta.txt: expected KEY=value');
    const key = line.slice(0, i);
    requireValue(!Object.hasOwn(result, key), `meta.txt: duplicate ${key}`);
    result[key] = line.slice(i + 1);
  }
  for (const key of ['HEAD', 'CORES', 'LOADAVG_BEGIN', 'LOADAVG_END', 'UPTIME_BEGIN', 'UPTIME_END',
    'STARTED_UTC', 'FINISHED_UTC', 'RUNTIME_SHA256', 'BOUNDSCHECK_SHA256', 'RUNTIME_STAMP']) {
    requireValue(Boolean(result[key]?.trim()), `meta.txt: missing ${key}`);
  }
  requireValue(result.GCLOG_SCHEMA === '5' && result.HEAP === '256MB' && result.N === '20', 'meta.txt: incompatible campaign definition');
  requireValue(result.EXPECTED_CHECKSUM === floor.measurement.checksum, 'meta.txt: wrong workload checksum contract');
  requireValue(/^[a-f0-9]{40}$/.test(result.HEAD), 'meta.txt: invalid producer HEAD');
  requireValue(/^CJRT-COMMIT:[a-f0-9]{40}$/.test(result.RUNTIME_STAMP), 'meta.txt: invalid runtime stamp');
  requireValue(hash(result.RUNTIME_SHA256) && hash(result.BOUNDSCHECK_SHA256), 'meta.txt: invalid SO hashes');
  for (const key of ['LOADAVG_BEGIN', 'LOADAVG_END']) {
    requireValue(/^\d+(?:\.\d+)? \d+(?:\.\d+)? \d+(?:\.\d+)? \d+\/\d+ \d+$/.test(result[key]), `meta.txt: invalid ${key}`);
  }
  for (const key of ['UPTIME_BEGIN', 'UPTIME_END']) requireValue(/\bup\b.*load average/.test(result[key]), `meta.txt: invalid ${key}`);
  requireValue(Number.isFinite(Date.parse(result.STARTED_UTC)) && Date.parse(result.FINISHED_UTC) >= Date.parse(result.STARTED_UTC), 'meta.txt: invalid measurement interval');
  requireValue(/^\d+(?:-\d+)?(?:,\d+(?:-\d+)?)*$/.test(result.CORES), 'meta.txt: invalid CORES');
  const cores = new Set();
  for (const part of result.CORES.split(',')) {
    const [lo, hi = lo] = part.split('-').map(Number);
    requireValue(hi >= lo && hi <= 65535, 'meta.txt: invalid core range');
    for (let i = lo; i <= hi; i++) cores.add(i);
  }
  requireValue(cores.size >= 64, 'meta.txt: fewer than 64 CPUs');
  return result;
}
const summary = values => {
  requireValue(values.length > 0, 'recording has no samples');
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return {samples: values.length, median: sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2,
    max: sorted.at(-1)};
};

// read is the gate's archive-root constrained reader; generic binding has already
// checked HEAD, recipe and every payload hash before this consumer is entered.
export async function evaluateCampaign(gate, read) {
  const meta = metadata(await read('meta.txt'));
  const inputs = JSON.parse(await read('inputs.json'));
  requireValue(inputs.schema === 1 && inputs.runtime_head === meta.RUNTIME_STAMP.slice(12) &&
    inputs.runtime?.sha256 === meta.RUNTIME_SHA256 && inputs.boundscheck?.sha256 === meta.BOUNDSCHECK_SHA256,
  'inputs.json: runtime identity disagrees with metadata');
  requireValue(inputs.expected_checksum === meta.EXPECTED_CHECKSUM, 'inputs.json: checksum contract mismatch');
  requireValue(hash(inputs.toolchain_provenance?.sha256) &&
    sha(await read('toolchain-provenance.json')) === inputs.toolchain_provenance.sha256, 'toolchain provenance hash mismatch');
  const recipe = await read('RECIPE.txt');
  requireValue(recipe.split(/\r?\n/).includes(`SOURCE=ci/release/${gate.toLowerCase()}.mjs`), 'RECIPE.txt: SOURCE is not the in-tree producer');
  const campaign = JSON.parse(await read('campaign.json'));
  requireValue(campaign.schema === 2 && campaign.gate === gate && Array.isArray(campaign.receipts), 'invalid campaign.json');
  const plan = [...campaignPlan(gate, floor.measurement.runs), ...(gate === 'G12' ? [{round: 0, load: 'O0', mode: 'control'}] : [])];
  requireValue(campaign.receipts.length === plan.length, 'campaign.json: incomplete run population');
  const rows = [];
  let combined = '';
  let control;
  for (const [i, expected] of plan.entries()) {
    const receipt = campaign.receipts[i];
    const key = runKey(expected);
    requireValue(receipt.round === expected.round && receipt.load === expected.load && receipt.mode === expected.mode,
      `campaign.json: unexpected run at ${i}, expected ${key}`);
    const base = `runs/${key}`;
    const retained = JSON.parse(await read(`${base}/receipt.json`));
    requireValue(JSON.stringify(retained) === JSON.stringify(receipt), `${key}: receipt mismatch`);
    requireValue(Number.isInteger(receipt.rc) && receipt.rc >= -1 && typeof receipt.signal === 'string' &&
      Number.isFinite(receipt.wall_ms) && receipt.wall_ms >= 0, `${key}: invalid process result`);
    requireValue(receipt.uptime_begin?.includes('load average') && receipt.uptime_end?.includes('load average'), `${key}: missing two-ended uptime`);
    const elf = inputs.workloads?.[expected.load];
    requireValue(hash(elf?.sha256) && elf.sha256 === meta[`WORKLOAD_ELF_SHA256_${expected.load}`] &&
      receipt.workload_sha256 === elf.sha256, `${key}: workload identity mismatch`);
    const runtime = expected.mode === 'control' ? inputs.control_runtime : inputs.runtime;
    requireValue(hash(runtime?.sha256) && receipt.runtime_sha256 === runtime.sha256, `${key}: runtime identity mismatch`);
    requireValue(receipt.env?.ZVerifyRemembered === (expected.mode === 'normal' ? '0' : '1') &&
      receipt.env.MRT_GC_LOG === '1' && receipt.env.ZVerifyRoots === '1' && receipt.env.ZVerifyMarking === '1' &&
      receipt.env.cjHeapSize === '256MB' && receipt.env.CANGJIE_CJHEAP_SIZE === '256MB', `${key}: run environment mismatch`);
    requireValue(receipt.argv?.[0] === 'taskset' && receipt.argv[1] === '-c' && receipt.argv[2] === meta.CORES &&
      receipt.argv.at(-1) === elf.path, `${key}: execution identity mismatch`);
    const loader = await read(`${base}/loader.txt`);
    requireValue(loader.includes(`${receipt.env.LD_LIBRARY_PATH}/libcangjie-runtime.so`), `${key}: loader identity mismatch`);
    const stdout = await read(`${base}/stdout.log`);
    requireValue(Array.isArray(receipt.gc_sources) && receipt.gc_sources[0] === 'stderr.log' &&
      receipt.gc_sources.every(name => /^(?:stderr\.log|report(?:\.[A-Za-z0-9_-]+)?)$/.test(name)) &&
      new Set(receipt.gc_sources).size === receipt.gc_sources.length, `${key}: invalid raw GC sources`);
    const raw = await Promise.all(receipt.gc_sources.map(name => read(`${base}/${name}`)));
    const log = await read(`${base}/gc.log`);
    requireValue(log === raw.join('\n'), `${key}: GC log disagrees with raw sources`);
    if (expected.mode === 'control') {
      requireValue(hash(inputs.control_patch?.sha256) && runtime.sha256 !== inputs.runtime.sha256, 'positive control: missing cut identity');
      requireValue(sha(await read('control.diff')) === inputs.control_patch.sha256, 'positive control: patch hash mismatch');
      control = {aborts: [...log.matchAll(MISSING_REMEMBERED)].length,
        aborted: receipt.rc === 134 || receipt.signal === 'SIGABRT'};
    } else {
      rows.push({receipt, observation: observeRun(stdout, log)});
      combined += log + '\n';
    }
  }
  for (const [file, expected] of Object.entries(campaignTables(rows, gate))) {
    requireValue(await read(file) === expected, `${file}: summary disagrees with raw execution evidence`);
  }
  requireValue(await read('gc.log') === combined, 'gc.log: archive disagrees with per-run logs');
  const check = (id, predicate) => ({id, status: predicate ? 'MET' : 'NOT_MET'});
  const checks = [
    check('F1', rows.every(({receipt: r, observation: o}) => r.rc === 0 && !r.signal && !r.error && o.waveComplete && o.checksum === floor.measurement.checksum)),
    check('F2', rows.every(({observation: o}) => o.minors >= 1 && o.minorSequence && o.generations === o.minors)),
    check('F3', rows.filter(({receipt: r}) => r.mode === 'verify').every(({receipt: r, observation: o}) => r.rc === 0 && !r.signal && o.verifyAborts === 0)),
    check('F4', rows.every(({observation: o}) => o.generations > 0 && o.completed === o.generations)),
  ];
  if (gate === 'G12' && (!control?.aborted || control.aborts < 1)) {
    checks[2] = {id: 'F3', status: 'UNKNOWN', reason: 'positive control did not abort at Missing remembered field'};
  }
  const phaseSums = Object.fromEntries(YOUNG_PHASES.map(name => [name,
    rows.flatMap(row => row.observation.phaseNs[name]).reduce((a, b) => a + b, 0)]));
  const total = Object.values(phaseSums).reduce((a, b) => a + b, 0);
  const phasePresent = YOUNG_PHASES.every(name => rows.every(row => row.observation.phaseNs[name].length > 0));
  const held = rows.flatMap(row => row.observation.heldNs);
  const live = rows.flatMap(row => row.observation.liveBytes);
  const reclaimed = rows.flatMap(row => row.observation.reclaimedBytes);
  const records = [
    {id: 'R1', status: phasePresent && total > 0 ? 'MET' : 'UNKNOWN', value: {ns: phaseSums,
      share: total > 0 ? Object.fromEntries(Object.entries(phaseSums).map(([k, v]) => [k, v / total])) : {}}},
    {id: 'R2', status: rows.every(row => row.observation.heldNs.length > 0) ? 'MET' : 'UNKNOWN', value: held.length ? summary(held) : null},
    {id: 'R4', status: live.length ? 'MET' : 'UNKNOWN', value: live.length ? {liveBytes: summary(live), reclaimedBytes: summary(reclaimed)} : null},
  ];
  const status = checks.some(c => c.status === 'UNKNOWN') ? 'UNKNOWN' : checks.some(c => c.status === 'NOT_MET') ? 'NOT_MET' :
    records.some(r => r.status === 'UNKNOWN') ? 'UNKNOWN' : 'MET';
  return {status, value: `single profile DEFAULT; ${checks.map(c => `${c.id}=${c.status}`).join('; ')}`,
    checks, records, samples: rows.length};
}
