# Generic-call resolution gate fixtures

These fixtures back `scripts/generic_gate.mjs`, a focused golden gate for generic-call
mapping, overload resolution, and related diagnostics. The main 114-case difftest corpus
exercises generic code, but does not isolate every multi-mapping and overload-conflict path.

## Fixtures

- **gf1_constraint**: generic function with an interface upper bound (`where T <: Shape`).
- **gf2_nested**: nested generic instantiation (`unwrap(wrap(42))`).
- **gf3_overload**: generic versus fixed overload resolution.
- **gf4_twoparam**: two type parameters with return-target-driven inference.
- **gf5_ambiguous**: a type implementing two interfaces is passed to two constrained
  overloads; the golden records the complete ambiguity diagnostic and notes.
- **gf6_overload_conflict**: two declarations differ only in generic constraints; constraints
  do not form an overload distinction, so the golden records the declaration conflict.

The first five cases were introduced with the C2 generic-call campaign. `gf6` was added with
the faithful `PreCheckFuncRedefinition` overload-conflict implementation.

## Usage

```sh
npx --yes zx@8 scripts/generic_gate.mjs --check
npx --yes zx@8 scripts/generic_gate.mjs --self <path-to-cjc>
```

`--check` recompiles all six fixtures with the configured reference compiler and compares
their normalized compile/run transcripts with `golden/`. `--self` applies the same comparison
to the selected cjcj compiler.

Set `CANGJIE_HOME` to select the SDK and `REF_CJC` to override its reference `cjc`. The gate
creates throwaway build directories and removes generated binaries after each case. Current
selfhost pass counts are intentionally not stored here: they must come from a run against the
same compiler HEAD being evaluated.
