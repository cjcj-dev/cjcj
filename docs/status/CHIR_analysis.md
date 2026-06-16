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

## 2026-06-17 Continuation

- Reference read: `src/CHIR/Analysis/{SInt,ConstantRange,SIntDomain}.cpp` and matching headers.
- Added fixed-width `SInt` division/remainder, extension/truncation primitives, active-bit inspection, overflow-detecting arithmetic, and saturating arithmetic.
- Added `ConstantRange` zero/sign extension, unsigned/signed multiply, unsigned/signed divide, unsigned/signed remainder, saturating arithmetic, absolute value, and negation following the C++ transfer functions.
- Added signed-division range splitting by positive/negative operands, including the C++ special handling around signed-min divided by `-1`.
- Added `SIntDomain` arithmetic wrappers for multiply, divide, modulo, and saturating add/sub/mul/div so analyses can consume the new range behavior through the domain layer.

## Remaining After Continuation

- `ConstantRange.Truncate` is still missing, along with the numeric conversion and type-cast range routines in C++ `SIntDomain.cpp`.
- `SInt` still lacks string construction/format parity, full bit-manipulation helpers, shift overflow/saturation helpers, and some bit-counting APIs.
- Higher-level CHIR analysis orchestration remains partial compared with C++ `AnalysisWrapper`, `Engine`, `Results`, `ConstAnalysis`, `TypeAnalysis`, `ValueAnalysis`, and `ValueRangeAnalysis`.

## Verification After Continuation

- `cjpm build` passed after implementation.
- `TODO(selfhost:CHIR)` count in `packages/chir/src`: 0.

## 2026-06-17 Truncation Pass

- Reference read: C++ `ConstantRange::SplitWrapping` and `ConstantRange::Truncate` in `src/CHIR/Analysis/ConstantRange.cpp`.
- Added immutable `SInt.ClearBit` support needed by the truncation transfer function.
- Added `ConstantRange.SplitWrapping`.
- Added `ConstantRange.Truncate`, including C++ behavior for upper-wrapped ranges, high-bit adjustment before truncation, destination-width full coverage detection, and union with the wrapped part.

## Remaining After Truncation Pass

- Numeric conversion and type-cast range routines from C++ `SIntDomain.cpp` still need a real Cangjie port.
- `SInt` still lacks full C++ parity for string construction/formatting and several bit-counting/shift overflow helpers.
- Higher-level CHIR analysis orchestration remains partial compared with C++ `AnalysisWrapper`, `Engine`, `Results`, `ConstAnalysis`, `TypeAnalysis`, `ValueAnalysis`, and `ValueRangeAnalysis`.

## Verification After Truncation Pass

- `cjpm build` passed after implementation.
- `TODO(selfhost:CHIR)` count in `packages/chir/src`: 0.

## 2026-06-17 SIntDomain Transfer Pass

- Reference read: C++ `SIntDomain.cpp` arithmetic, relational, equality, symbolic merge, and numeric conversion/type-cast sections.
- De-isolated overflow strategy use by importing `cangjie_compiler::utils.OverflowStrategy` into CHIR and adding the CHIR package dependency needed for that real sibling package.
- Added C++-style `CHIRArithmeticBinopArgs`, `CHIRRelIntBinopArgs`, `ComputeArithmeticBinop`, `ComputeRelIntBinop`, `ComputeEqualityBoolBinop`, `NumericConversion`, and `ComputeTypeCastNumericBound`.
- Ported symbolic add/sub propagation, total-order and equality comparison refinement, unsigned/signed/same-sign conversion, throwing/wrapping/saturating narrowing, and type-cast numeric bound logic.
- Adjusted `SIntDomain.IsSame` and symbolic merge bottom handling to match the C++ reference behavior.

## Remaining After SIntDomain Transfer Pass

- Higher-level CHIR analysis orchestration remains partial compared with C++ `AnalysisWrapper`, `Engine`, `Results`, `ConstAnalysis`, `TypeAnalysis`, `ValueAnalysis`, and `ValueRangeAnalysis`.
- `ValueRangeAnalysis` integration is still missing the full C++ cache/projection/update engine that consumes the new transfer helpers.
- `SInt` still lacks full string construction/format parity and some non-core bit-counting/shift helper APIs.

## Verification After SIntDomain Transfer Pass

- `cjpm build` passed after implementation.
- `TODO(selfhost:CHIR)` count in `packages/chir/src`: 0.

## 2026-06-17 CallGraph Analysis Pass

- Reference read: C++ `include/cangjie/CHIR/Analysis/CallGraphAnalysis.h` and `src/CHIR/Analysis/CallGraphAnalysis.cpp`.
- Split the local call graph implementation out of `Analysis.cj` into `CallGraphAnalysis.cj`, matching the C++ component file layout.
- Replaced the prior direct-callee list with C++-shaped `CallGraph`, `CallGraphNode`, and `CallGraphEdge` structures, including entry/exit nodes and direct/virtual edge kinds.
- Added graph population over nested block groups, direct apply/apply-with-exception edges, virtual invoke/invoke-with-exception handling matching the current C++ empty devirtual callee fallback, and compatibility `Run(pkg)`.
- Added SCC post-order construction over the call graph so transform scheduling can consume a real call graph order rather than a flat function list.

## Remaining After CallGraph Analysis Pass

- The generic `Analysis`, `Engine`, `Results`, and full `ValueAnalysis` state framework remain absent compared with the C++ templates.
- `ValueRangeAnalysis`, `TypeAnalysis`, and `ConstAnalysis` integration still need full C++-faithful state propagation over CHIR expressions and terminators.
- Virtual call target expansion is limited by the same empty `GetAllPossibleCalleeOfInvoke` behavior present in the current C++ implementation, plus missing CHIR-specific invoke wrapper classes in the local Cangjie IR surface.

## Verification After CallGraph Analysis Pass

- `cjpm build` passed after implementation.
- `TODO(selfhost:CHIR)` count in `packages/chir/src`: 0.
