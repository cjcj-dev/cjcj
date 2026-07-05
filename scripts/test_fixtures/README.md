# `--test` / mock gate fixtures

Backing fixtures for `scripts/test_gate.sh` — the `--test`/mock focused compile gate
for the TestManager+Mock live-integration campaign
(`audit_persist/TESTMANAGER_LIVE_DESIGN.md`, slice S5). The 114-file difftest corpus
and sc_bcgate contain no `--test`/mock samples, so this gate is the only signal for
the mock/test-marking behaviour that slices S3/S4 turn on.

## Fixtures

- **t1_test_basic** — a minimal `@Test` class with two `@TestCase` methods. Compiled
  with `--test`; exercises the plain test-registration path.
- **t2_mock_member** — a `@Test` case that `mock<Service>()`s an open class member and
  stubs it with `@On(...).returns(...)`. Compiled with `--test --mock=on`; exercises the
  sema TestManager mock hooks (`PrepareToMock` marks `MOCK_SUPPORTED`; `HandleCreateMock`
  + `MockSupportManager` generate the `$ToMock` accessors — the S4 behaviour surface,
  visible as `ToMock` symbol count in golden).
- **t3_test_vs_normal** — identical source with both a `main()` and a `@Test` class,
  compiled two ways: normal (builds a `main` app, prints `5`) and `--test` (builds the
  test runner). Captures the same-source two-mode product difference.

## Golden signals

Per fixture the gate records: compile exit code + normalized diagnostics; produced-binary
run exit code (and, for the normal `main`, its deterministic stdout); and a stable count of
`--test`/mock entry symbols (`TestPackage`, `register*Suite`, `entry_main`, `ToMock`).
Golden is established with the C++ reference compiler and is self-consistent
(`test_gate.sh --check` → PASS 3/3).

## Selfhost baseline (as of slices S0–S2, before S3/S4 wiring)

`test_gate.sh --self <selfhost cjc>` currently FAILs all three vs golden — the intended
baseline. Two deterministic divergences:

1. Spurious `warning: unused import 'std.unittest.*'` that the reference does not emit
   (selfhost's unused-import analysis does not credit usage introduced by `@Test`
   expansion).
2. Fewer test-registration symbols (e.g. t3 `TestPackage`/`register*Suite` = 95/13 vs
   golden 103/19), reflecting the not-yet-wired mark/mock passes and the separate macro
   campaign.

Both binaries still compile (rc=0) and run (exit=0). The selfhost cjc needs a large
managed heap for the std.unittest-heavy fixtures; the gate exports `cjHeapSize=12GB`
(harmless for the reference cjc). As S3/S4 (mark + mock hooks) and the macro campaign
land, `--self` should converge toward golden.
