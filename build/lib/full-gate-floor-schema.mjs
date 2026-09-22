// Schema, validator and renderer for the G8 full-gate release floor.
//
// build/lib/full-gate-release-floor.mjs is deliberately data-only:
// ci/release-gates.mjs imports it and recomputes every G8 result from it, and
// ci/full-gate-floor.test.mjs copies that file verbatim into a fixture
// checkout. So the code that produces it lives here rather than in it, and the
// floor file stays a record that a reader can take in at a glance.
//
// The field list below is the same one ci/release-gates.mjs names when it
// reports the floor incomplete. That duplication is deliberate -- the gate is
// the judge and must not import its own expectations from the thing it judges
// -- and ci/full-gate-floor.test.mjs pins the two lists to each other by
// reading the gate's own missing= output, so a field added on one side and not
// the other goes red.

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

// The eleven measured integers, in the order ci/release-gates.mjs names them.
export const FULL_GATE_FLOOR_METRICS = Object.freeze([
  'difftest.total',
  'difftest.pass',
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
// identity fields plus the eleven measured integers.
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

// A floor is one past run that every later run has to match or beat. So the
// floor itself has to be a run the gate would have passed -- otherwise writing
// it down turns a failed run into the ceiling later runs are measured against,
// and the gate cannot catch that: ci/release-gates.mjs only checks the floor's
// schema (loadG8Floor), never its values, and this command is the only way a
// floor is produced.
//
// The conditions below are not thresholds chosen here. They are
// ci/release-gates.mjs:897-915 -- the whole of what evaluateG8 compares --
// evaluated with the floor as both arms, which is exactly the question "would
// the gate have passed this run". The five baseline-relative comparisons
// (difftest.total <, smoke.pass <, bcgate.shared <, bcgate.byte_identical <,
// bcgate.differing >) are all satisfied by a value against itself and so
// constrain nothing; what is left is the six absolute ones.
function inadmissibleFields(baseline) {
  const failures = [];
  const difftest = baseline.difftest;
  const bcgate = baseline.bcgate;
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

// Names every field that is absent, every field that is present but cannot be
// a measurement, and -- once those are clean -- every field that makes the run
// one the gate would have failed. The first two use the same labels
// ci/release-gates.mjs prints.
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

function renderValue(value, indent) {
  if (typeof value === 'string') {
    if (!/^[A-Za-z0-9][A-Za-z0-9._:-]*$/.test(value)) throw new FloorRefused([`unrenderable string: ${value}`]);
    return `'${value}'`;
  }
  if (typeof value === 'number') return String(value);
  if (!plainObject(value)) throw new FloorRefused([`unrenderable value: ${String(value)}`]);
  const inner = ' '.repeat(indent + 2);
  const entries = Object.entries(value)
    .map(([key, nested]) => `${inner}${key}: ${renderValue(nested, indent + 2)},`);
  return `Object.freeze({\n${entries.join('\n')}\n${' '.repeat(indent)}})`;
}

export function renderFullGateFloorModule(record) {
  return [
    `// Frozen G8 baseline, measured on campaign ${record.campaign_id}.`,
    '// Written by ci/write-full-gate-floor.mjs from that run\'s ' +
      `${record.evidence.results}; change the command or re-run the campaign,`,
    '// not this file. Historical 2005/2472/467 values deliberately do not seed',
    '// this record.',
    `export const FULL_GATE_RELEASE_FLOOR = ${renderValue(record, 0)};`,
    '',
  ].join('\n');
}
