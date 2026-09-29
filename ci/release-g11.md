# G11 evidence from #482

Run `node ci/release-gates.mjs G11 --evidence ARCHIVE --json` (0 MET,
1 NOT_MET, 2 UNKNOWN). `all` uses the same evaluator. No fixed case count
is used. This gate consumes #482's original `identity.json` and each of
Conformance/HLT/LLT's `summary.json` and `cases.json`; it does not run tests.
Keep their raw logs alongside them. `compare.py` remains useful for triage,
but its timeout-excluded failure diff cannot establish release qualification.
G11 compares the unfiltered case records, including timeout failures.

The campaign owner writes `ARCHIVE/G11.json`:

```json
{
  "schema": 1,
  "cjcj_head_sha": "<final compiler source SHA, equal to --repo HEAD or --ref>",
  "official": {
    "directory": "O1",
    "compiler_sha256": "<official cjc SHA256>",
    "runtime_sha256": {"<SDK-relative runtime path>": "<SHA256>"},
    "started_at": "2026-09-29T12:00:00Z",
    "finished_at": "2026-09-29T13:00:00Z"
  },
  "selfhost": {
    "directory": "B1",
    "compiler_sha256": "<final selfhost cjc SHA256>",
    "runtime_sha256": {"<SDK-relative runtime path>": "<SHA256>"},
    "started_at": "2026-09-29T12:00:00Z",
    "finished_at": "2026-09-29T13:00:00Z"
  },
  "allowances": [
    {"suite": "LLT", "name": "<exact official failing case name>", "reason": "<individual Q54-C reason>"}
  ]
}
```

Intervals come from campaign execution records, not file modification times.
The runtime maps are the full maps emitted by `run.py`; SDK hashes must match
those records. Both arms must overlap, use distinct compiler identities,
identical comparison recipe fields from `compare.py:12-14`, and identical
nonempty case sets in each suite. Missing, stale, inconsistent or incomplete
records yield UNKNOWN. Each official failure requires an individual reason;
an allowance for anything outside the measured official failure set is invalid.
A selfhost-only failure yields NOT_MET, and cannot be waived. Complete,
qualified evidence with no selfhost-only failures yields MET. Common failures
are licensed observations, not passed test cases. A newly skipped selfhost
case cannot establish MET. G10 and other release gates remain independent.

This is an evidence consumer, not proof of archive authenticity. The campaign
owner is responsible for recording the correct official and final selfhost SDK
identities and timestamps. Existing #482 run records do not contain absolute
start/end timestamps, so old outputs without campaign records remain UNKNOWN.
