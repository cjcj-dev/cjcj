# Macro-focused gate fixtures

Fixtures backing `../macro_gate.mjs`, the macro-expansion gate for the
frontend↔macro integration campaign (design:
`audit_persist/MACRO_INTEGRATION_DESIGN.md`, slice **S4** pre-gate).

## Why this exists

The 114-file difftest corpus contains **no real macro samples** (only
`131_when_local_decl.cj`, which uses `@When` conditional compilation and does not
go through the macro pipeline). So difftest/bcgate are blind to macro-expansion
behavior. These fixtures give S4 an independent, reference-anchored gate before
the live `CompileStrategy.MacroExpand()` stub is replaced.

## Fixtures

Each fixture is a directory with a macro-definition package (`mdef/`) and a user
package (`use/`) that triggers expansion. `golden/<fixture>.golden` records the
reference compiler's behavior (exit codes + normalized diagnostics + run result).

| Fixture | C++ path exercised | Reference behavior |
|---|---|---|
| `f1_decl_identity` | Collect→Evaluate→ReplaceAST, single call/single decl | compiles; app returns 42 |
| `f2_multi_decl` | `ReplaceDecls`/decl-vector splice (one call → many decls) | compiles; app returns 3 |
| `f3_nested` | nested expansion / `ReEvalAfterEvalMacroCalls` | compiles; app returns 7 |
| `f4_attr_macro` | attribute macro `(attr, input)` / `CheckAttrTokens` | compiles; app returns 5 |
| `f5_unused_import` | `SaveUsedMacros`→`AddUsedMacroDecls`→CheckUnusedImport (IM3 gate) | positive: no unused-import warning, app returns 3; control: genuinely-unused `import std.collection.*` still warns |

`f5` includes a `control/` case proving the positive suppression is real
macro-usage accounting, not a blanket disable of the unused-import check.

## Usage

```sh
npx --yes zx@8 scripts/macro_gate.mjs                       # establish/refresh golden (reference cjc)
npx --yes zx@8 scripts/macro_gate.mjs --check               # re-run reference, diff vs golden (determinism)
npx --yes zx@8 scripts/macro_gate.mjs --self <path-to-cjc>  # run selfhost cjc, diff vs golden
```

Env overrides: `CANGJIE_HOME` (default `/root/cj_build/cangjie_compiler/output`),
`REF_CJC` (default `$CANGJIE_HOME/bin/cjc`). The selfhost compiler is assumed to
reuse the reference `CANGJIE_HOME` std/runtime; only the `cjc` frontend differs.

Fixtures build in throwaway temp dirs, so this tree is never polluted with
`.cjo`/`.so`/binaries. Only sources and `golden/` are committed.

## Current selfhost status (as of golden creation)

`--self` against the selfhost cjc FAILs all fixtures, as expected pre-integration.
The failure is **earlier** than the `MacroExpand()` stub: the selfhost cannot even
`--compile-macro` a macro-definition package — it reports a spurious
`redefinition of declaration '<macro>'` (same line reported as its own previous
declaration), so expansion is never reached. This is an additional selfhost gap
upstream of the integration root, surfaced by these fixtures.
