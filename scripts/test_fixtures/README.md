# `--test` / mock gate fixtures

Backing fixtures for `scripts/test_gate.mjs`, the focused golden gate for `--test`,
test registration, and mock generation. The flat 114-file difftest corpus and bcgate
contain no `--test`/mock samples, so these fixtures cover a distinct product mode.

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
Golden transcripts are established with the C++ reference compiler. Recheck or compare
them with:

```sh
npx --yes zx@8 scripts/test_gate.mjs --check
npx --yes zx@8 scripts/test_gate.mjs --self <path-to-cjc>
```

The runner uses throwaway directories, removes generated products after each fixture,
and exports `cjHeapSize=12GB` for the std.unittest-heavy selfhost path. Current pass counts
are intentionally not stored here: they must be measured with the compiler HEAD under
review instead of copied from an earlier integration campaign.
