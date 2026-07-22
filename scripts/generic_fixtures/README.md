# Generic-call resolution gate fixtures

Backs `scripts/generic_gate.mjs` — the focused gate for the sema C2 campaign
(`audit_persist/SEMA_C2_DESIGN.md`, CheckGenericCallCompatible cluster). The 114-file
difftest corpus exercises generic calls but does not isolate the multi-mapping
resolution / ambiguity-diagnostic path that C2b/C2c target.

## Fixtures

- **gf1_constraint** — generic function with an interface upper-bound (`where T <: Shape`).
- **gf2_nested** — nested generic instantiation (`unwrap(wrap(42))`).
- **gf3_overload** — generic vs fixed overload resolution (`conv<T>` vs `conv(Int64)`).
- **gf4_twoparam** — two type params with return-target-driven inference (`cast2<T,R>`).
- **gf5_ambiguous** — a type implementing two interfaces called against two
  `where T<:A` / `where T<:B` overloads: genuinely ambiguous. This is the **C2 target** —
  C++ emits the full `DiagnoseForMultiMapping` ambiguity notes (6 locations); the current
  selfhost emits fewer.

## Golden + baseline (as of C2a, before C2b/C2c)

Golden established with the C++ reference compiler; `npx --yes zx@8 scripts/generic_gate.mjs --check` → PASS 5/5.
`npx --yes zx@8 scripts/generic_gate.mjs --self <selfhost cjc>` current baseline: **PASS=4 FAIL=1** — gf1–gf4 pass
(single-mapping model already resolves them; these are regression guards C2c must keep green),
gf5 fails on the missing multi-mapping ambiguity diagnostic (the DiagnoseForMultiMapping gap,
ported in C2b and wired in C2c). The selfhost cjc needs a large heap; the gate exports
`cjHeapSize=12GB` (harmless for the reference cjc).
