// G12 release floor for 0.0.2.  Keep this data-only: ci/release-gates.mjs
// imports it and recomputes every blocking result from archived measurements.
export const GC_RELEASE_FLOOR = Object.freeze({
  schema: 1,
  release: '0.0.2',
  measurement: Object.freeze({
    heap_mib: 256,
    workload_sha8: 'e75cdefd',
    runs: 20,
    interleaved: true,
    profiles: Object.freeze({
      DEFAULT: Object.freeze({run_arm: 'DEFAULT', full_young_scan: 1}),
      FYS0: Object.freeze({run_arm: 'FYS0', full_young_scan: 0}),
    }),
  }),
  evidence: Object.freeze({
    metadata: 'meta.txt',
    run_results: 'runs.tsv',
    remset_results: 'remset.tsv',
    throughput_results: 'throughput.tsv',
    phase_log: 'gc.log',
    profiles: Object.freeze({
      DEFAULT: Object.freeze({
        f3_counts: 'default/f3.log',
        f3_positive_control: 'default/f3-control.log',
        mark_survival: 'default/marksurvive.log',
        mark_survival_positive_control: 'default/marksurvive-control.log',
      }),
      FYS0: Object.freeze({
        f3_counts: 'fys0/f3.log',
        f3_positive_control: 'fys0/f3-control.log',
        mark_survival: 'fys0/marksurvive.log',
        mark_survival_positive_control: 'fys0/marksurvive-control.log',
      }),
    }),
  }),
  blocking: Object.freeze([
    Object.freeze({id: 'F1', metric: 'workload_rc0', profile: 'DEFAULT', expected_runs: 20, expected_rc0: 20}),
    Object.freeze({
      id: 'F2', metric: 'hello_alloc_rc0', profile: 'DEFAULT', expected_runs: 20,
      expected_rc0: 20, minimum_minor_cycles_per_run: 1,
    }),
    Object.freeze({
      id: 'F3', metric: 'f3_dead_arm_count', profile: 'DEFAULT', maximum_count: 0,
      positive_control_minimum: 1,
    }),
    Object.freeze({
      id: 'F4', metric: 'mark_survival_signature_count', profile: 'DEFAULT', maximum_count: 0,
      positive_control_minimum: 1,
    }),
    Object.freeze({
      id: 'F5', metric: 'remset_never_seen_count', profile: 'DEFAULT', loads: Object.freeze(['O0', 'O2']),
      maximum_count: 0, positive_control_minimum: 1,
    }),
    Object.freeze({
      id: 'F6', metric: 'profile_gate_conjunction', profile: 'FYS0', full_young_scan: 0,
      required_gate_count: 5,
    }),
  ]),
  recording: Object.freeze([
    Object.freeze({
      id: 'R1', metric: 'minor_phase_share', unit: 'ratio', phases: Object.freeze([
        'young.mark_closure', 'young.ref_fix', 'young.evac_finish', 'young.copy',
      ]),
    }),
    Object.freeze({
      id: 'R2', metric: 'remset_size', unit: 'slots', aggregates: Object.freeze(['median', 'max']),
      loads: Object.freeze(['O0', 'O2']),
    }),
    Object.freeze({
      id: 'R3', metric: 'generational_task_clock_ratio', unit: 'ratio',
      generational_arm: 'A', minor_disabled_arm: 'B', aggregates: Object.freeze(['median']),
    }),
    Object.freeze({
      id: 'R4', metric: 'gc_phase_stw', unit: 'us', aggregates: Object.freeze(['median', 'max']),
    }),
  ]),
});
