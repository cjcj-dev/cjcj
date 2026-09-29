// Evidence consumers for release campaigns; no build or dispatch occurs here.
const SHA256 = /^[a-f0-9]{64}$/;
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const nonempty = value => typeof value === 'string' && value.trim().length > 0;

function verdict(missing, failures) {
  return {status: failures.length ? 'NOT_MET' : missing.length ? 'UNKNOWN' : 'MET', missing, failures};
}

// The required axes come from targets.mjs, never from the submitted records.
export function platformRequirements(gate, scope) {
  if (gate === 'G6') return [...new Set(scope.platforms.map(p => p.llvm_platform))].map(id => ({
    id, checks: ['producer', 'manifest_pin', 'llc_sha', 'opt_sha', 'llc_version', 'opt_version', 'shim'],
    artifacts: ['llc.gz', 'opt.gz', 'manifest', 'shim'],
  }));
  return scope.platforms.flatMap(p => gate === 'G3' ? p.std_tuples.map(tuple => ({
    id: `${p.key}/${tuple}`, checks: ['producer', 'assertFinalStd'], artifacts: ['final_std'],
  })) : [{id: p.key,
    checks: gate === 'G7' ? ['archive_manifest', 'clean_stamp', 'artifact_sha'] :
      ['package', 'smoke', 'checksums', ...(p.host.startsWith('darwin-') ? ['darwin_lto'] : [])],
    artifacts: ['archive', 'manifest', ...(gate === 'G9' ? ['checksums'] : [])],
  }]);
}

export function platformEvidence(gate, scope, data, payload) {
  const missing = [], failures = [];
  const required = platformRequirements(gate, scope);
  if (!object(data) || data.schema !== 1 || data.gate !== gate || !Array.isArray(data.records)) {
    return verdict([`${gate}_RESULTS.json:schema/gate/records`], failures);
  }
  for (const record of data.records) {
    if (!object(record) || !required.some(item => item.id === record.id)) failures.push(`unexpected record:${record?.id}`);
  }
  for (const item of required) {
    const rows = data.records.filter(row => row?.id === item.id);
    // A missing platform/tuple is a known coverage failure, including blocked/excluded rows.
    if (rows.length !== 1) {
      failures.push(`${item.id}:records=${rows.length}`);
      if (!rows.length) missing.push(`${item.id}:record`);
      continue;
    }
    const row = rows[0];
    for (const name of item.checks) {
      const label = `${item.id}:${name}`;
      const check = row.checks?.[name];
      if (!object(check) || !Number.isInteger(check.rc) || !nonempty(check.log) || !SHA256.test(payload[check.log] || '')) {
        missing.push(label);
      } else if (check.rc !== 0) failures.push(`${label}:rc=${check.rc}`);
    }
    for (const name of item.artifacts) {
      const artifact = row.artifacts?.[name];
      if (!object(artifact) || !nonempty(artifact.name) || !SHA256.test(artifact.sha256 || '') ||
          !Number.isSafeInteger(artifact.bytes) || artifact.bytes <= 0) missing.push(`${item.id}:artifact:${name}`);
    }
  }
  return verdict(missing, failures);
}

// Schema 1 is produced by #725 ci/g10/run.mjs. Recompute from raw records:
// the producer's summary cannot hide a failed, skipped, duplicate or absent case.
export function g10Evidence(data, head) {
  const missing = [], failures = [];
  if (!object(data) || data.schema !== 1 || data.gate !== 'G10' || !Array.isArray(data.records) || !Array.isArray(data.corpus)) {
    return verdict(['G10_RESULTS.json:schema/gate/records/corpus'], failures);
  }
  if (data.head !== head) missing.push('G10_RESULTS.json:head');
  const ids = data.corpus.map(c => c?.id);
  if (ids.length < 50 || new Set(ids).size !== ids.length || data.corpus.some(c =>
    !nonempty(c?.id) || c.expected_rc !== 0 || !SHA256.test(c.sha256 || ''))) missing.push('corpus:>=50 unique ids/source_sha256/expected_rc');
  if (data.injection !== null) failures.push('injection');
  const phases = {version: Array.from({length: 20}, (_, i) => String(i + 1)),
    compile: Array.from({length: 20}, (_, i) => String(i + 1)), crashsweep: ids};
  for (const record of data.records) {
    if (!['official', 'selfhost'].includes(record?.arm) || !phases[record?.phase]?.includes(record.id)) failures.push(`unexpected record:${record?.arm}/${record?.phase}/${record?.id}`);
  }
  for (const arm of ['official', 'selfhost']) {
    const identity = data.arms?.[arm];
    if (identity?.status !== 'ran' || data.not_run?.[arm]) missing.push(`${arm}:NOT_RUN`);
    if (!SHA256.test(identity?.compiler_sha256 || '')) missing.push(`${arm}:compiler_sha256`);
    for (const lib of ['libcangjie-runtime.so', 'libboundscheck.so']) {
      if (!SHA256.test(identity?.runtime?.[lib] || '')) missing.push(`${arm}:runtime:${lib}`);
    }
    for (const [phase, expected] of Object.entries(phases)) for (const id of expected) {
      const label = `${arm}/${phase}/${id}`;
      const rows = data.records.filter(r => r?.arm === arm && r.phase === phase && r.id === id);
      if (rows.length !== 1) {
        (rows.length ? failures : missing).push(`${label}:records=${rows.length}`);
        continue;
      }
      const row = rows[0];
      if (phase !== 'version') {
        if (!SHA256.test(row.source_sha256 || '')) missing.push(`${label}:source_sha256`);
        if (!SHA256.test(row.elf_sha256 || '')) missing.push(`${label}:elf_sha256`);
        if (phase === 'crashsweep' && row.source_sha256 !== data.corpus.find(c => c.id === id)?.sha256) failures.push(`${label}:source mismatch`);
      }
      for (const step of phase === 'version' ? ['invoke'] : ['compile', 'run']) {
        const value = row[step];
        if (!object(value) || !Object.hasOwn(value, 'rc') || !Object.hasOwn(value, 'signal') ||
            !Object.hasOwn(value, 'error') || typeof value.timed_out !== 'boolean' ||
            !Number.isSafeInteger(value.skipped_who) || value.skipped_who < 0 || !nonempty(value.signature)) {
          missing.push(`${label}:${step}`);
        } else if (value.rc !== 0 || value.signal !== null || value.error !== null || value.timed_out ||
            value.skipped_who !== 0 || value.signature !== 'OK') failures.push(`${label}:${step}:${value.signature}`);
      }
    }
  }
  if (data.skipped_who !== 0) failures.push('skipped_who');
  if (!Array.isArray(data.failures)) missing.push('failures');
  else if (data.failures.length) failures.push(...data.failures.map(f => `summary:${f.arm}/${f.phase}/${f.id}:${f.step || f.reason}`));
  if (!['MET', 'NOT_MET', 'UNKNOWN'].includes(data.status)) missing.push('status');
  else if (data.status === 'NOT_MET') failures.push('summary:NOT_MET');
  else if (data.status === 'UNKNOWN') missing.push('summary:UNKNOWN');
  return verdict(missing, failures);
}
