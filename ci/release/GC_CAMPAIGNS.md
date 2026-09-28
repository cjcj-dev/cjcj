# G12′ / G14′ campaign producer

The 2026-09-28 ruling replaces the retired FYS axis with one DEFAULT profile.
G12 runs natural_wave O0 normally and with remembered verification, interleaved
for 20 rounds. G14 retains O0/O2, both with remembered verification, for 20
rounds. Runs on the same measurement CPU set are sequential to avoid changing
one another's load; independent campaigns can use disjoint allocated CPU sets.

**Physical qualification is pending cjcj#135.** Use its current coloured compiler,
stdlib and runtime tuple to build natural_wave at O0/O2. Historical e75 ELFs are
not a replacement. The scripts consume explicit artifacts; they do not download
or assemble an SDK. Toolchain provenance must accompany those artifacts.

From a clean checkout, prepare an input JSON (all paths are absolute):

```json
{
  "schema": 1,
  "runtime_head": "<40 hex runtime source commit>",
  "runtime": {"path": "/path/libcangjie-runtime.so", "sha256": "<64 hex>"},
  "boundscheck": {"path": "/path/libboundscheck.so", "sha256": "<64 hex>"},
  "workloads": {
    "O0": {"path": "/path/natural_wave.O0", "sha256": "<64 hex>"},
    "O2": {"path": "/path/natural_wave.O2", "sha256": "<64 hex>"}
  },
  "toolchain_provenance": {"path": "/path/tuple.json", "sha256": "<64 hex>"},
  "expected_checksum": "635925223159200",
  "control_runtime": {"path": "/path/cut/libcangjie-runtime.so", "sha256": "<64 hex>"},
  "control_patch": {"path": "/path/cut.diff", "sha256": "<64 hex>"}
}
```

G12 requires the control runtime and its source patch. The authorised transient
cut is at the actual remembered path (runtime zGeneration.cpp:429-445), without
new runtime hooks or committed runtime changes. A control only counts when the
same workload, under verification, aborts with `Missing remembered field`.
A timeout, loader error, or arbitrary nonzero exit cannot qualify the control.
G14 does not require these two control inputs.

Run on kkk2 through `box.sh` / `wf_kkk2.sh`, with core dumps disabled, an allocated
CPU set of at least 64 CPUs, and all files below `/root/<full-lane>/`:

```sh
node ci/release/g12.mjs --inputs /path/inputs.json --out /path/new-G12 --cores 0-63
node ci/release/g14.mjs --inputs /path/inputs.json --out /path/new-G14 --cores 64-127
node ci/release-gates.mjs G12 --evidence /path/new-G12 --json
node ci/release-gates.mjs G14 --evidence /path/new-G14 --json
```

Output includes `runs.tsv`, `remset.tsv`, `throughput.tsv`, `gc.log`, `meta.txt`,
`inputs.json`, `toolchain-provenance.json`, `campaign.json`, `RECIPE.txt`,
`EVIDENCE_BINDING.json`, and `runs/<load>-<mode>-<round>/` with stdout, stderr,
runtime report files, combined GC log, loader selection and execution receipt.
G14 also writes `raw.tsv`. Missing data stays missing; there is no fallback to
retired `miss*` counters. `throughput.tsv` records wall time only, not the removed
minor-disabled comparison. No performance threshold is applied.

The gate recomputes every TSV from raw logs and receipts. Schema 5 durations are
nanoseconds. Young phase records join generation completions by `(seq,gc_tag)`;
`y` and `Y` are young, `O` is old. Two young completions can share the same major
sequence (preclean then roots), so a set of sequence IDs is insufficient.
`Pause_Mark_End` alone proves only an attempt; subsequent `Concurrent_Relocate`
and generation completion in the same scope prove progression past marking.
R1 records Concurrent_Mark, Concurrent_Select_Relocation_Set, Concurrent_Relocate;
R2 records STW held_ns; R4 records liveBytes/reclaimedBytes. These names are based
on runtime dafcd904 zGeneration.cpp:86-95 and GcLog.h:219-232; qualification against
current natural_wave logs remains part of the pending physical rerun.

RECIPE's SOURCE points to this checkout's producer, not a lane-private directory.
Copy the accepted evidence to the ops release archive through the controller;
this script never writes shared ops state.
