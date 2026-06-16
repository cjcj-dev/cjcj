# CHIR Analysis Status

## 2026-06-17 Deepening Pass

- Scope: CHIR dataflow and transform-driving analysis support in `packages/chir/src`.
- Reference read: `include/cangjie/CHIR/Analysis/{SInt,ConstantRange}.h` and `src/CHIR/Analysis/{SInt,ConstantRange}.cpp`.
- Build baseline: `cjpm build` passed before edits.

## Implemented

- Replaced `ConstantRange.From`, range wrapping predicates, containment, min/max extraction, difference, add/sub, intersection, and union with behavior matching the C++ reference algorithms for wrapped and unwrapped intervals.
- Removed the previous scan-based signed min/max and intersection logic, which was not viable for 64-bit domains and did not match C++ preferred-range selection.
- Added `ConstantRange.Inverse` and preferred-range selection for signed, unsigned, and smallest covering intervals.
- Deepened `SInt` with C++-style unsigned/signed comparison helpers and min/max selectors used by `ConstantRange`.
- Corrected 64-bit signed extrema and sign-bit handling in `SInt`, and marked arithmetic helpers that model fixed-width integer behavior with `@OverflowWrapping`.

## Remaining

- `SInt` still lacks much of the C++ API surface: string construction, bit counting/manipulation helpers, extension/truncation helpers, division/remainder, overflow-reporting operations, and saturating operations.
- `ConstantRange` still lacks C++ operations beyond the core interval algebra implemented here: zero/sign extension, truncation, multiplication, division, remainder, saturating arithmetic, absolute value, and negate.
- Higher-level CHIR analyses remain partial compared with C++ `AnalysisWrapper`, `Engine`, `Results`, `ConstAnalysis`, `TypeAnalysis`, `ValueAnalysis`, and `ValueRangeAnalysis`.

## Verification

- `cjpm build` passed after implementation.
- `TODO(selfhost:CHIR)` count in `packages/chir/src`: 0.
