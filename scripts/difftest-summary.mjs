function summary(text, pattern, fields, label) {
  const matches = [...text.matchAll(pattern)];
  if (matches.length !== 1) throw new Error(`${label}: expected one summary, found ${matches.length}`);
  return Object.fromEntries(fields.map((field, i) => {
    const value = Number(matches[0][i + 1]);
    if (!Number.isSafeInteger(value) || value < 0) throw new Error(`${label}.${field}: invalid count`);
    return [field, value];
  }));
}

export function parseSummary(name, text) {
  if (name === 'difftest') {
    const counts = summary(text, /^TOTAL=(\d+)\s+PASS=(\d+)\s+MATCH=(\d+)\s+MISMATCH=(\d+)\s+FAIL=(\d+)\s+UNKNOWN=(\d+)\s*$/gm,
      ['total', 'pass', 'match', 'mismatch', 'fail', 'unknown'], name);
    if (!counts.total || counts.total !== counts.pass + counts.match + counts.mismatch + counts.fail ||
        counts.unknown > counts.total || counts.pass + counts.unknown > counts.total) {
      throw new Error('difftest: empty or inconsistent total');
    }
    return counts;
  }
  throw new Error('unexpected compiler check: ' + name);
}

// Retain the original compiler-check accounting and rejection criteria.
export const FULL_GATE_FLOOR_SCHEMA = 1;
export const FULL_GATE_FLOOR_EVIDENCE_RESULTS = 'G8_FULL_GATE.json';

const CAMPAIGN_ID = /^[0-9a-f]{40}-[0-9]{8}T[0-9]{6}Z-[1-9][0-9]*$/;
const SHA40 = /^[0-9a-f]{40}$/;
const UTC_SECOND = /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$/;
const EVIDENCE_NAME = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

export const FULL_GATE_FLOOR_IDENTITY_FIELDS = Object.freeze([
  Object.freeze({field: 'campaign_id', pattern: CAMPAIGN_ID, description: 'frozen campaign id'}),
  Object.freeze({field: 'cjcj_head_sha', pattern: SHA40, description: 'frozen cjcj head'}),
  Object.freeze({field: 'measured_utc', pattern: UTC_SECOND, description: 'UTC second the run finished'}),
]);

// Keep the stable order used in diagnostics.
export const FULL_GATE_FLOOR_METRICS = Object.freeze([
  'difftest.total',
  'difftest.pass',
  'difftest.match',
  'difftest.unknown',
  'difftest.mismatch',
  'difftest.fail',
  'smoke.pass',
  'smoke.fail',
  'bcgate.shared',
  'bcgate.byte_identical',
  'bcgate.differing',
  'bcgate.compile_errors',
  'verify_exit',
]);

// Every field the floor must carry before it can leave PENDING: the three
// identity fields plus the measured integers.
export const FULL_GATE_FLOOR_FIELDS = Object.freeze([
  ...FULL_GATE_FLOOR_IDENTITY_FIELDS.map(entry => entry.field),
  ...FULL_GATE_FLOOR_METRICS.map(metric => `baseline.${metric}`),
]);

export class FloorRefused extends Error {
  constructor(reasons) {
    super(reasons.join('; '));
    this.name = 'FloorRefused';
    this.reasons = reasons;
  }
}

function plainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function nestedField(value, dotted) {
  return dotted.split('.').reduce((current, field) => (plainObject(current) ? current[field] : undefined), value);
}

// A failed or unqualified run cannot serve as the baseline for another run.
function inadmissibleFields(baseline) {
  const failures = [];
  const difftest = baseline.difftest;
  const bcgate = baseline.bcgate;
  if (difftest.unknown !== 0) failures.push(`baseline.difftest.unknown=${difftest.unknown} (execution qualification UNKNOWN)`);
  if (difftest.match !== 0) failures.push(`baseline.difftest.match=${difftest.match} (MATCH is not PASS)`);
  // release-gates.mjs:900-901
  if (difftest.pass !== difftest.total) {
    failures.push(`baseline.difftest.pass=${difftest.pass} is not baseline.difftest.total=${difftest.total}`);
  }
  if (difftest.mismatch !== 0) failures.push(`baseline.difftest.mismatch=${difftest.mismatch}`);
  if (difftest.fail !== 0) failures.push(`baseline.difftest.fail=${difftest.fail}`);
  // release-gates.mjs:905
  if (baseline.smoke.fail !== 0) failures.push(`baseline.smoke.fail=${baseline.smoke.fail}`);
  // release-gates.mjs:910
  if (bcgate.compile_errors !== 0) failures.push(`baseline.bcgate.compile_errors=${bcgate.compile_errors}`);
  // release-gates.mjs:915
  if (baseline.verify_exit !== 0) failures.push(`baseline.verify_exit=${baseline.verify_exit}`);
  return failures;
}

export function validateFullGateFloor(candidate) {
  const missing = [];
  const invalid = [];
  if (!plainObject(candidate)) {
    return {missing: FULL_GATE_FLOOR_FIELDS.slice(), invalid: ['floor must be an object'], inadmissible: []};
  }

  for (const {field, pattern} of FULL_GATE_FLOOR_IDENTITY_FIELDS) {
    const value = candidate[field];
    if (value === undefined || value === null || value === '') missing.push(field);
    else if (typeof value !== 'string' || !pattern.test(value)) invalid.push(`${field}=${String(value)}`);
  }
  if (!plainObject(candidate.baseline)) {
    if (candidate.baseline === undefined || candidate.baseline === null) {
      missing.push(...FULL_GATE_FLOOR_METRICS.map(metric => `baseline.${metric}`));
    } else invalid.push('baseline is not an object');
  } else {
    for (const metric of FULL_GATE_FLOOR_METRICS) {
      const value = nestedField(candidate.baseline, metric);
      if (value === undefined || value === null) missing.push(`baseline.${metric}`);
      else if (!Number.isSafeInteger(value) || value < 0) invalid.push(`baseline.${metric}=${String(value)}`);
    }
  }
  const results = candidate.evidence_results ?? FULL_GATE_FLOOR_EVIDENCE_RESULTS;
  if (typeof results !== 'string' || !EVIDENCE_NAME.test(results)) {
    invalid.push(`evidence.results=${String(candidate.evidence_results)}`);
  }
  // The gate reads the campaign id as the binding between the floor and the
  // frozen head; a floor that fails it is NOT_MET, so it is not worth writing.
  if (!missing.includes('campaign_id') && !missing.includes('cjcj_head_sha') &&
      typeof candidate.campaign_id === 'string' && typeof candidate.cjcj_head_sha === 'string' &&
      !candidate.campaign_id.startsWith(`${candidate.cjcj_head_sha}-`)) {
    invalid.push(`campaign_id=${candidate.campaign_id} does not bind cjcj_head_sha=${candidate.cjcj_head_sha}`);
  }
  // Only once every metric is present and is a non-negative safe integer, so
  // the comparisons below read real measurements rather than nulls or strings.
  const inadmissible = missing.length || invalid.length ? [] : inadmissibleFields(candidate.baseline);
  return {missing, invalid, inadmissible};
}

// A complete, ordered floor record, or a refusal naming every field that made
// it impossible. Never partially fills a floor.
export function buildFullGateFloor(candidate) {
  const {missing, invalid, inadmissible} = validateFullGateFloor(candidate);
  if (missing.length || invalid.length || inadmissible.length) {
    throw new FloorRefused([
      ...(missing.length ? [`missing=${missing.join(',')}`] : []),
      ...(invalid.length ? [`invalid=${invalid.join(',')}`] : []),
      ...(inadmissible.length
        ? [`inadmissible=${inadmissible.join(',')} (the G8 gate would not have passed this run; ` +
          'a floor is a run every later run must match or beat)']
        : []),
    ]);
  }
  const baseline = candidate.baseline;
  return {
    schema: FULL_GATE_FLOOR_SCHEMA,
    status: 'READY',
    campaign_id: candidate.campaign_id,
    cjcj_head_sha: candidate.cjcj_head_sha,
    measured_utc: candidate.measured_utc,
    evidence: {results: candidate.evidence_results ?? FULL_GATE_FLOOR_EVIDENCE_RESULTS},
    baseline: {
      difftest: {
        total: baseline.difftest.total,
        pass: baseline.difftest.pass,
        match: baseline.difftest.match,
        unknown: baseline.difftest.unknown,
        mismatch: baseline.difftest.mismatch,
        fail: baseline.difftest.fail,
      },
      smoke: {pass: baseline.smoke.pass, fail: baseline.smoke.fail},
      bcgate: {
        shared: baseline.bcgate.shared,
        byte_identical: baseline.bcgate.byte_identical,
        differing: baseline.bcgate.differing,
        compile_errors: baseline.bcgate.compile_errors,
      },
      verify_exit: baseline.verify_exit,
    },
  };
}
