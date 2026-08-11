// Freeze-head G8 baseline. The first controlled full-gate run replaces PENDING
// and the nulls below with its measured integers; historical 2005/2472/467
// values deliberately do not seed this record.
export const FULL_GATE_RELEASE_FLOOR = Object.freeze({
  schema: 1,
  status: 'PENDING',
  campaign_id: null,
  cjcj_head_sha: null,
  measured_utc: null,
  evidence: Object.freeze({
    results: 'G8_FULL_GATE.json',
  }),
  baseline: Object.freeze({
    difftest: Object.freeze({total: null, pass: null, mismatch: null, fail: null}),
    smoke: Object.freeze({pass: null, fail: null}),
    bcgate: Object.freeze({
      shared: null,
      byte_identical: null,
      differing: null,
      compile_errors: null,
    }),
    verify_exit: null,
  }),
});
