# Os/Oz 114-sample BC and runtime sweep

## Scope

- Rebased worktree onto `master` `74d4fe37507022550934ab515bd0b50c5e99bdf4`; measurement parent is `9437c6111d41cb5471574a29c54fc8435f4ea507`.
- Corpus: all 114 files in `scripts/difftest_corpus` (sorted-name manifest SHA-256 `672caa08d264d5a67b2272a0a74a084ed119c4dfa53c932297a074ff6fea0b92`).
- Reference: `/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029/bin/cjc`.
- Selfhost: `target/release/bin/cjcj::cjc`, 66,193,096 bytes, SHA-256 `6dad31a09aaae9ef4dea069a8a2c4ced5736e6a488c2312b5b695fc0e4016f01`.
- This task changed no compiler or corpus source. Per-sample evidence is in `OPT_SIZE_BC_MATRIX.tsv` and `OPT_SIZE_DIFFTEST.tsv`.

## Method

The BC matrix compiles each sample with both compilers at each size level using:

```text
<compiler> <sample> -Os|-Oz --experimental --output-type=obj --compile-target exe --save-temps <dir> -o out.o
```

It records compile RC, pre-opt and `.opt.bc` counts and hashes, then runs LLVM 15's verifier on every emitted module:

```text
opt -passes=verify -disable-output <module.bc>
```

Pre-opt parity uses the existing `scripts/bcgate.py`/`scripts/cmpir.py` method: `llvm-dis`, metadata/name normalization, then exact comparison by mangled function name. `PASS` requires both compile RCs to be zero, every pre/opt BC module on both sides to verify, every shared function body to match, and no function to occur on only one side.

`rg -n -- '-Os|-Oz|OPT|optimization' scripts/difftest.sh` returned no matches, so the checked-in harness has no optimization-level variant. The runtime matrix therefore preserves its per-sample isolation and limits while explicitly passing `-Os`/`-Oz`: compile timeout 180s, run timeout 30s, reference/selfhost run-RC and byte-exact stdout/stderr comparison. Selfhost linking also retains `--set-runtime-rpath`.

## Raw gate lines

```text
cjpm build success
BC_MATRIX level=Os TOTAL=114 PASS=0 COMPILE_OK_BOTH=114 VERIFY_OK_BOTH=114 SHARED_FUNCTIONS=2248 IDENTICAL_FUNCTIONS=2023 ONE_SIDE_FUNCTIONS=223
BC_MATRIX level=Oz TOTAL=114 PASS=0 COMPILE_OK_BOTH=114 VERIFY_OK_BOTH=114 SHARED_FUNCTIONS=2248 IDENTICAL_FUNCTIONS=2023 ONE_SIDE_FUNCTIONS=223
DIFFTEST level=Os TOTAL=114 PASS=114 MISMATCH=0 FAIL=0
DIFFTEST level=Oz TOTAL=114 PASS=114 MISMATCH=0 FAIL=0
```

`VERIFY_OK_BOTH=114` means all four verifier cells for every sample passed: reference/selfhost × pre-opt/opt BC.

## O2 comparison and qualification

The established O2 baseline is:

```text
bcgate: shared functions: 2490  |  byte-identical: 2490 (100.0%)  |  differing: 0 | fully-identical samples: 114/114  |  compile-errors: 0
difftest: TOTAL=114  PASS=114  MISMATCH=0  FAIL=0
```

| Level | Both compile | Both verify pre+opt | Shared funcs | Identical shared | Body diffs | Ref-only | Selfhost-only | Fully BC-identical samples | Runtime PASS |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| O2 baseline | 114/114 | not rerun | 2,490 | 2,490 | 0 | 0 | 0 | 114/114 | 114/114 |
| Os | 114/114 | 114/114 | 2,248 | 2,023 | 225 | 3 | 220 | 0/114 | 114/114 |
| Oz | 114/114 | 114/114 | 2,248 | 2,023 | 225 | 3 | 220 | 0/114 | 114/114 |

Thus the Os/Oz-specific gap is not a compiler failure, invalid LLVM IR, or observed runtime mismatch. It is a full-corpus pre-opt BC parity gap: every sample differs from reference, with 225 differing shared bodies and 223 one-side function occurrences per level.

Os and Oz have the same gap set. For both compilers, every sample's raw pre-opt BC hash is identical between Os and Oz (`114/114` on each side), and all per-sample normalized parity counts match. The backend distinguishes the levels later: reference `.opt.bc` hashes match between Os/Oz for 96/114 samples, selfhost for 97/114.

## First-error and first-difference clusters

There are no compile or verifier errors to cluster: reference first error `<none>` 114/114 and selfhost first error `<none>` 114/114 at both levels.

Using deterministic mangled-name order, each non-identical sample's first BC difference clusters as follows; Os and Oz have identical counts and membership:

| First BC difference | Samples per level | Qualification |
|---|---:|---|
| body diff in `0_for_keeping_some_types` | 111 | Reference has four additional type-anchor `alloca`s in the representative `01_return`; both return `void`. |
| body diff in `_CN7default6<main>Hv` | 3 | `122_generic_body_lambda_capture`, `125_generic_body_lambda_higher_order`, `58_array_struct`. |

The three `main` representatives are materially different pre-opt lowering, not naming noise. In `122_generic_body_lambda_capture`, reference stores/prints the folded value `42`; selfhost allocates the closure object, stores capture `41`, invokes its generated function, and retains three selfhost-only closure functions. Both executables nevertheless produce identical output and exit status.

Directionally, 220/223 one-side occurrences are selfhost-only, indicating retained functions rather than broad under-emission. Highest selfhost-only sample counts per level are:

| Sample | Selfhost-only | Ref-only | Body diffs |
|---|---:|---:|---:|
| `43_hashmap` | 32 | 0 | 7 |
| `44_list_methods` | 21 | 0 | 4 |
| `42_arraylist` | 17 | 1 | 4 |
| `57_array2d` | 12 | 0 | 2 |
| `12_str_interp` | 7 | 0 | 1 |
| `58_array_struct` | 7 | 0 | 1 |
| `90_range_subscript` | 7 | 0 | 2 |

The only reference-only occurrences are one each in `116_nonprimitive_array_literal`, `41_array_loop`, and `42_arraylist`. The TSV is the complete new-ammunition list; it includes the per-sample body-diff/ref-only/selfhost-only counts and first BC difference.

## Artifacts

```text
bf10187e7d850b47816cf128a4834a7eeb2df71b4137418d575915e9fe6e279a  OPT_SIZE_BC_MATRIX.tsv
e180dca0cf7cfd63828d4a62b4a8a46595f5edffcad6082a3a36e20c438c1e74  OPT_SIZE_DIFFTEST.tsv
```

Both TSVs contain one header plus 228 data rows (114 Os + 114 Oz).

## Delivery audit

- C++ per-symbol source anchors: N/A; no compiler function, helper, type, field, or branch was added or modified.
- Platform-branch grep: N/A; no C++ or compiler platform code was modified.
- Full branch coverage: N/A; this is a measurement-only chore, not a C++ port.
- 无任何 grep 不到 C++ 出处的新编译器符号。
- 未改业务源码绕过、未加 band-aid 吞 bug。
- 未撞到系统根；无系统根替代实现。
