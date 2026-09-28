import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {parseArgs} from 'node:util';
import {fileURLToPath} from 'node:url';
import {campaignPlan, campaignTables, observeRun, runKey, GCLOG_SCHEMA} from '../../build/lib/gc-campaign.mjs';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const digest = value => crypto.createHash('sha256').update(value).digest('hex');
const sha = async file => digest(await fs.readFile(file));
function command(program, args) {
  const r = spawnSync(program, args, {encoding: 'utf8'});
  if (r.status !== 0) throw new Error(`${program}: ${r.error?.message || r.stderr}`);
  return r.stdout.trim();
}
async function write(root, file, value) {
  await fs.mkdir(path.dirname(path.join(root, file)), {recursive: true});
  await fs.writeFile(path.join(root, file), value);
}
async function inventory(root, directory = root) {
  const result = {};
  for (const entry of await fs.readdir(directory, {withFileTypes: true})) {
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) Object.assign(result, await inventory(root, file));
    else if (entry.isFile() && entry.name !== 'EVIDENCE_BINDING.json') result[path.relative(root, file)] = await sha(file);
    else if (!entry.isFile()) throw new Error(`non-regular evidence: ${file}`);
  }
  return result;
}
export async function bindCampaign(root, gate, head, started, finished) {
  const payload = await inventory(root);
  await write(root, 'EVIDENCE_BINDING.json', JSON.stringify({
    schema: 1, gate, cjcj_head_sha: head,
    producer: {repository: 'cjcj-dev/cjcj', head_sha: head, head_file: 'meta.txt'},
    recipe: {id: `${gate.toLowerCase()}-single-profile-v2`, file: 'RECIPE.txt', sha256: payload['RECIPE.txt']},
    measurement: {started_utc: started, finished_utc: finished}, payload_sha256: payload,
  }, null, 2) + '\n');
}

async function validateArtifact(item, label) {
  if (!item || !path.isAbsolute(item.path || '') || !/^[a-f0-9]{64}$/.test(item.sha256 || '')) {
    throw new Error(`${label} needs an absolute path and sha256`);
  }
  if (await sha(item.path) !== item.sha256) throw new Error(`${label} sha256 mismatch`);
}

export async function main(gate) {
  const {values} = parseArgs({options: {
    inputs: {type: 'string'}, out: {type: 'string'}, cores: {type: 'string'}, help: {type: 'boolean'},
  }});
  if (values.help) {
    console.log(`node ci/release/${gate.toLowerCase()}.mjs --inputs inputs.json --out NEW_DIRECTORY --cores CPU_LIST`);
    return;
  }
  if (!values.inputs || !values.out || !/^\d+(?:-\d+)?(?:,\d+(?:-\d+)?)*$/.test(values.cores || '')) {
    throw new Error('--inputs, --out and --cores are required; see ci/release/GC_CAMPAIGNS.md');
  }
  const selected = new Set();
  for (const part of values.cores.split(',')) {
    const [lo, hi = lo] = part.split('-').map(Number);
    if (hi < lo || hi > 65535) throw new Error('invalid CPU range');
    for (let i = lo; i <= hi; i++) selected.add(i);
  }
  if (selected.size < 64) throw new Error('campaign requires at least 64 CPUs');
  const head = command('git', ['-C', repo, 'rev-parse', 'HEAD']);
  if (command('git', ['-C', repo, 'status', '--porcelain', '--untracked-files=no'])) {
    throw new Error('producer checkout must be clean');
  }
  const inputs = JSON.parse(await fs.readFile(values.inputs, 'utf8'));
  if (inputs.schema !== 1 || !/^[a-f0-9]{40}$/.test(inputs.runtime_head || '') ||
      !/^\d+$/.test(inputs.expected_checksum || '') || !inputs.toolchain_provenance) {
    throw new Error('inputs require schema=1, runtime_head, expected_checksum and toolchain_provenance');
  }
  const loads = gate === 'G12' ? ['O0'] : ['O0', 'O2'];
  const artifacts = {runtime: inputs.runtime, boundscheck: inputs.boundscheck,
    toolchain_provenance: inputs.toolchain_provenance,
    ...Object.fromEntries(loads.map(load => [load, inputs.workloads?.[load]]))};
  if (gate === 'G12') {
    artifacts.control_runtime = inputs.control_runtime;
    artifacts.control_patch = inputs.control_patch;
  }
  for (const [name, item] of Object.entries(artifacts)) await validateArtifact(item, name);
  const stamp = command('strings', [inputs.runtime.path]).split('\n').filter(s => s.startsWith('CJRT-COMMIT:'));
  if (stamp.length !== 1 || stamp[0] !== `CJRT-COMMIT:${inputs.runtime_head}`) throw new Error('runtime clean stamp mismatch');
  const root = path.resolve(values.out);
  await fs.mkdir(root); // Refuse reuse: stale logs must never enter a new campaign.
  const started = new Date().toISOString();
  const begin = command('uptime', []);
  const loadBegin = (await fs.readFile('/proc/loadavg', 'utf8')).trim();
  await write(root, 'inputs.json', JSON.stringify(inputs, null, 2) + '\n');
  await fs.copyFile(inputs.toolchain_provenance.path, path.join(root, 'toolchain-provenance.json'));
  await write(root, 'RECIPE.txt', [
    `GATE=${gate}`, `SOURCE=ci/release/${gate.toLowerCase()}.mjs`, `HEAD=${head}`,
    'PROFILE=DEFAULT', 'HEAP=256MB', 'N=20', `CORES=${values.cores}`,
    `COMMAND=${JSON.stringify(process.argv.slice(1))}`, 'INPUTS=inputs.json', '',
  ].join('\n'));
  // Preserve partial metadata on failure; END is emitted only after all runs.
  await write(root, 'meta.txt', [
    `HEAD=${head}`, `GCLOG_SCHEMA=${GCLOG_SCHEMA}`, `CORES=${values.cores}`, 'HEAP=256MB', 'N=20',
    `LOADAVG_BEGIN=${loadBegin}`, `UPTIME_BEGIN=${begin}`, `STARTED_UTC=${started}`,
    `RUNTIME_SHA256=${inputs.runtime.sha256}`, `BOUNDSCHECK_SHA256=${inputs.boundscheck.sha256}`,
    `RUNTIME_STAMP=${stamp[0]}`, `EXPECTED_CHECKSUM=${inputs.expected_checksum}`,
    ...loads.map(load => `WORKLOAD_ELF_SHA256_${load}=${inputs.workloads[load].sha256}`), '',
  ].join('\n'));
  const receipts = [];
  const rows = [];
  let combined = '';
  for (const item of [...campaignPlan(gate), ...(gate === 'G12' ? [{round: 0, load: 'O0', mode: 'control'}] : [])]) {
    const key = runKey(item);
    const dir = path.join(root, 'runs', key);
    await fs.mkdir(dir, {recursive: true});
    const runtime = item.mode === 'control' ? inputs.control_runtime : inputs.runtime;
    const lib = path.join(root, item.mode === 'control' ? 'control-lib' : 'lib');
    await fs.mkdir(lib, {recursive: true});
    await fs.copyFile(runtime.path, path.join(lib, 'libcangjie-runtime.so'));
    await fs.copyFile(inputs.boundscheck.path, path.join(lib, 'libboundscheck.so'));
    const elf = inputs.workloads[item.load];
    const env = {PATH: process.env.PATH, LD_LIBRARY_PATH: lib, cjHeapSize: '256MB', CANGJIE_CJHEAP_SIZE: '256MB',
      MRT_GC_LOG: '1', MRT_LOG_LEVEL: 'i', MRT_REPORT: path.join(dir, 'report'),
      ZVerifyRemembered: item.mode === 'normal' ? '0' : '1', ZVerifyRoots: '1', ZVerifyMarking: '1'};
    await write(dir, 'loader.txt', command('env', [`LD_LIBRARY_PATH=${lib}`, 'ldd', elf.path]) + '\n');
    if (!(await fs.readFile(path.join(dir, 'loader.txt'), 'utf8')).includes(`${lib}/libcangjie-runtime.so`)) {
      throw new Error(`${key}: loader does not select the retained runtime`);
    }
    const out = await fs.open(path.join(dir, 'stdout.log'), 'w');
    const err = await fs.open(path.join(dir, 'stderr.log'), 'w');
    const before = command('uptime', []);
    const start = performance.now();
    const args = ['-c', values.cores, '/usr/bin/timeout', '--signal=TERM', '--kill-after=5s', '120s', elf.path];
    const child = spawnSync('taskset', args, {env, stdio: ['ignore', out.fd, err.fd]});
    await out.close(); await err.close();
    const receipt = {...item, rc: child.status ?? -1, signal: child.signal || '', error: child.error?.message || '',
      wall_ms: Math.round(performance.now() - start), env, argv: ['taskset', ...args],
      uptime_begin: before, uptime_end: command('uptime', []),
      workload_sha256: elf.sha256, runtime_sha256: runtime.sha256};
    let gcLog = await fs.readFile(path.join(dir, 'stderr.log'), 'utf8');
    for (const name of (await fs.readdir(dir)).filter(name => name === 'report' || name.startsWith('report.')).sort()) {
      gcLog += '\n' + await fs.readFile(path.join(dir, name), 'utf8');
    }
    await write(dir, 'gc.log', gcLog);
    await write(dir, 'receipt.json', JSON.stringify(receipt, null, 2) + '\n');
    receipts.push(receipt);
    if (item.mode !== 'control') {
      rows.push({receipt, observation: observeRun(await fs.readFile(path.join(dir, 'stdout.log'), 'utf8'), gcLog)});
      combined += gcLog + '\n';
    }
  }
  for (const [name, item] of Object.entries(artifacts)) await validateArtifact(item, name);
  for (const [file, text] of Object.entries(campaignTables(rows, gate))) await write(root, file, text);
  await write(root, 'gc.log', combined);
  await write(root, 'campaign.json', JSON.stringify({schema: 2, gate, receipts}, null, 2) + '\n');
  const finished = new Date().toISOString();
  await fs.appendFile(path.join(root, 'meta.txt'),
    `LOADAVG_END=${(await fs.readFile('/proc/loadavg', 'utf8')).trim()}\nUPTIME_END=${command('uptime', [])}\nFINISHED_UTC=${finished}\n`);
  // Shared libraries are inputs, not archived evidence. Their identities remain in inputs/receipts.
  await fs.rm(path.join(root, 'lib'), {recursive: true, force: true});
  await fs.rm(path.join(root, 'control-lib'), {recursive: true, force: true});
  await bindCampaign(root, gate, head, started, finished);
  console.log(`${gate} evidence=${root}; evaluate with node ci/release-gates.mjs ${gate} --evidence ${root} --json`);
}
