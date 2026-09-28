// G12′/G14′ observation model. Runtime anchors: GcLog.h:41,107,132;
// zStat.cpp:1274,1329; zGeneration.cpp:86-95,446-458,548 (dafcd904).
export const GCLOG_SCHEMA = 5;
export const YOUNG_PHASES = Object.freeze([
  'Concurrent_Mark', 'Concurrent_Select_Relocation_Set', 'Concurrent_Relocate',
]);
export const MISSING_REMEMBERED = /Missing remembered field[^\n]*/g;
const fields = line => Object.fromEntries([...line.matchAll(/(?:^|\s)(\w+)=([^\s]+)/g)]
  .map(match => [match[1], match[2]]));
function integer(value, label) {
  if (!/^\d+$/.test(String(value)) || !Number.isSafeInteger(Number(value))) {
    throw new Error(`${label}: expected nonnegative safe integer, got ${value}`);
  }
  return Number(value);
}

export function observeRun(stdout, gcLog) {
  const minors = [...gcLog.matchAll(/\[GCV2Minor\] run=(\d+) liveBytes=(\d+) reclaimedBytes=(\d+) pause=(\d+) us/g)]
    .map(m => ({run: integer(m[1], 'run'), live: integer(m[2], 'liveBytes'), reclaimed: integer(m[3], 'reclaimedBytes')}));
  const phaseNs = Object.fromEntries(YOUNG_PHASES.map(name => [name, []]));
  const heldNs = [];
  const pending = new Map();
  let generations = 0;
  let completed = 0;
  for (const line of gcLog.split(/\r?\n/)) {
    if (!line.includes('[GCLOG]')) continue;
    const f = fields(line);
    if (f.rec === 'crash') continue; // Crash has its independent schema.
    if (integer(f.v, 'GCLOG.v') !== GCLOG_SCHEMA) throw new Error(`unsupported GCLOG schema ${f.v}`);
    if (!['y', 'Y'].includes(f.gc_tag)) continue;
    const key = `${integer(f.seq, 'seq')}:${f.gc_tag}`;
    if (f.rec === 'phase') {
      const ns = integer(f.ns, `${f.name}.ns`);
      const phases = pending.get(key) || [];
      phases.push(f.name);
      pending.set(key, phases);
      if (Object.hasOwn(phaseNs, f.name)) phaseNs[f.name].push(ns);
    } else if (f.rec === 'stw') {
      heldNs.push(integer(f.held_ns, 'held_ns'));
    } else if (f.rec === 'generation') {
      if (!/^Young_Generation(?:_|$)/.test(f.name)) throw new Error('young tag has a non-young generation name');
      integer(f.dur_ns, 'generation.dur_ns');
      generations++;
      const phases = pending.get(key) || [];
      const mark = phases.lastIndexOf('Pause_Mark_End');
      // Pause_Mark_End alone includes unsuccessful attempts. Require the
      // subsequent relocation and generation completion in the SAME scope.
      if (mark >= 0 && phases.lastIndexOf('Concurrent_Relocate') > mark) completed++;
      // Major preclean can complete two young generations with the same seq/Y.
      pending.delete(key);
    }
  }
  const checksums = [...stdout.matchAll(/^NATURAL_WAVE_OK checksum=(\d+)\s*$/gm)].map(m => m[1]);
  const waves = [...stdout.matchAll(/^WAVE_DONE wave=(\d+) checksum=(\d+).*$/gm)];
  const checksum = checksums.length === 1 ? checksums[0] : '';
  const waveComplete = waves.length === 12 && waves.every((m, i) => Number(m[1]) === i) &&
    waves[11][2] === checksum;
  return {
    checksum, waveComplete, minors: minors.length, generations, completed,
    minorSequence: minors.length > 0 && minors.every((m, i) => m.run === i + 1),
    verifyAborts: [...gcLog.matchAll(MISSING_REMEMBERED)].length,
    phaseNs, heldNs, liveBytes: minors.map(m => m.live), reclaimedBytes: minors.map(m => m.reclaimed),
  };
}

export function campaignPlan(gate, runs = 20) {
  if (!['G12', 'G14'].includes(gate)) throw new Error(`unknown campaign ${gate}`);
  return Array.from({length: runs}, (_, i) => (gate === 'G12'
    ? [{round: i + 1, load: 'O0', mode: 'normal'}, {round: i + 1, load: 'O0', mode: 'verify'}]
    : [{round: i + 1, load: 'O0', mode: 'verify'}, {round: i + 1, load: 'O2', mode: 'verify'}])).flat();
}
export const runKey = row => `${row.load}-${row.mode}-${row.round}`;
function tsv(columns, rows) {
  return [columns.join('\t'), ...rows.map(row => columns.map(c => String(row[c] ?? '')).join('\t')), ''].join('\n');
}
export function campaignTables(rows, gate) {
  const all = rows.map(({receipt: r, observation: o}) => ({
    round: r.round, load: r.load, mode: r.mode, rc: r.rc, signal: r.signal || '-', wall_ms: r.wall_ms,
    checksum: o.checksum, minors: o.minors, generations: o.generations, mark_completed: o.completed,
    verify_aborts: o.verifyAborts,
  }));
  const runs = tsv(['round', 'load', 'mode', 'rc', 'signal', 'wall_ms', 'checksum', 'minors', 'generations',
    'mark_completed', 'verify_aborts'], all);
  return {
    'runs.tsv': runs,
    ...(gate === 'G14' ? {'raw.tsv': runs} : {}),
    'remset.tsv': tsv(['round', 'load', 'rc', 'minors', 'verify_aborts'], all.filter(r => r.mode === 'verify')),
    'throughput.tsv': tsv(['round', 'load', 'mode', 'rc', 'wall_ms'], all),
  };
}
