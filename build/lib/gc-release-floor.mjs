import {YOUNG_PHASES} from './gc-campaign.mjs';

// Single-profile G12′/G14′, controller ruling 2026-09-28.
// Runtime dafcd904 GcLog.h:41,107,132; ZGC zGeneration.cpp:891-905.
export const GC_RELEASE_FLOOR = Object.freeze({
  schema: 2,
  release: '0.0.2',
  measurement: Object.freeze({
    heap_mib: 256, runs: 20, profile: 'DEFAULT', gclog_schema: 5,
    checksum: '635925223159200',
  }),
  blocking: Object.freeze([
    Object.freeze({id: 'F1', metric: 'completed_workload_rc0_checksum'}),
    Object.freeze({id: 'F2', metric: 'young_generation_minor_sequence'}),
    Object.freeze({id: 'F3', metric: 'remembered_verification', positive_control_minimum: 1}),
    Object.freeze({id: 'F4', metric: 'young_mark_completed_before_relocation'}),
  ]),
  recording: Object.freeze([
    Object.freeze({id: 'R1', metric: 'young_phase_share', phases: YOUNG_PHASES}),
    Object.freeze({id: 'R2', metric: 'stw_held_ns'}),
    Object.freeze({id: 'R4', metric: 'live_reclaimed_bytes'}),
  ]),
});
