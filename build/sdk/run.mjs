// Child-process supervision: every step records argv, cwd, selected env, cgroup resources and its own rc.
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

const ENV_KEYS = /^(CJCJ_|CANGJIE_|CJFMT_|STDX_|CJPM_|CMAKE_|PATH$|HOME$|TMPDIR$|JAVA_HOME$)/;

function cgroupFacts() {
  try {
    const rel = fs.readFileSync('/proc/self/cgroup', 'utf8').trim().replace(/^0::/, '');
    const read = name => { try { return fs.readFileSync(`/sys/fs/cgroup${rel}/${name}`, 'utf8').trim(); } catch { return null; } };
    return {cpus: read('cpuset.cpus.effective'), memoryMax: read('memory.max'), swapMax: read('memory.swap.max'), peak: read('memory.peak')};
  } catch { return null; }
}

export function createRunner({evidence, env = process.env, dryRun = false} = {}) {
  if (!evidence) throw new Error('RUN_EVIDENCE_DIR');
  fs.mkdirSync(evidence, {recursive: true});
  const records = [];
  function run(label, argv, {cwd = process.cwd(), environment = env} = {}) {
    if (!/^[A-Za-z0-9._-]+$/.test(label)) throw new Error(`RUN_LABEL ${label}`);
    const command = {label, argv, cwd, started: new Date().toISOString(), resources: cgroupFacts(),
      env: Object.fromEntries(Object.entries(environment).filter(([key]) => ENV_KEYS.test(key)))};
    fs.writeFileSync(path.join(evidence, `${label}.command.json`), JSON.stringify(command, null, 2) + '\n');
    if (dryRun) { records.push({label, rc: null, dryRun: true}); return {rc: null}; }
    const log = fs.openSync(path.join(evidence, `${label}.log`), 'w');
    let result;
    try { result = spawnSync(argv[0], argv.slice(1), {cwd, env: environment, stdio: ['ignore', log, log]}); }
    finally { fs.closeSync(log); }
    const record = {label, rc: result.status, signal: result.signal, error: result.error?.message ?? null,
      ended: new Date().toISOString(), resources: cgroupFacts()};
    fs.writeFileSync(path.join(evidence, `${label}.result.json`), JSON.stringify(record, null, 2) + '\n');
    records.push(record);
    if (result.status !== 0 || result.signal || result.error)
      throw Object.assign(new Error(`STEP_FAILED ${label} rc=${result.status} signal=${result.signal ?? ''}`), {rc: result.status ?? 1, record});
    return record;
  }
  return {run, records};
}
