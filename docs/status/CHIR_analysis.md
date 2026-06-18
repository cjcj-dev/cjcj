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

## 2026-06-17 ValueRange Analysis Pass

- Reference read: C++ `include/cangjie/CHIR/Analysis/ValueRangeAnalysis.h` and `src/CHIR/Analysis/ValueRangeAnalysis.cpp`.
- Added `ValueRangeAnalysis.cj` to mirror the C++ component split instead of leaving range analysis folded into the numeric-domain helpers.
- Ported the C++ `ValueRange`, `BoolRange`, `SIntRange`, and `RangeValueDomain` lattice behavior, including clone, join, top/bottom, string, literal, default integer/bool range, and tracked-global helpers.
- Added a concrete `RangeDomain` over the current self-hosted CHIR `Value` IDs, with clone, join, update, bound-setting, clear, and abstract-value lookup behavior needed by transform-driving range analysis.
- Added a C++-shaped `RangeAnalysis` subset over the real local CHIR IR: integer arithmetic transfer through `ComputeArithmeticBinop`, integer relation transfer through `ComputeRelIntBinop`, bool equality transfer, constant seeding, typecast numeric-bound transfer, in-queue limiting, and simple branch pruning.
- Kept `OverflowStrategy` de-isolated through the real `cangjie_compiler::utils` package import.

## Remaining After ValueRange Analysis Pass

- Full C++ `ValueAnalysis`/`State` infrastructure is still not present in the self-hosted CHIR package, so this pass provides the range-specific state and transfer layer rather than the complete template framework.
- The local Cangjie IR surface still lacks typed C++ nodes such as `TypeCast`, `TypeCastWithException`, `MultiBranch`, and expression-level overflow strategy access, so exception routing, multibranch pruning, single-value diagnostic overflow emission, and exact per-expression overflow strategies remain incomplete.
- Higher-level wiring into `AnalysisWrapper`, `Engine`, `Results`, `ConstAnalysis`, and `TypeAnalysis` remains partial compared with the C++ pipeline.

## Verification After ValueRange Analysis Pass

- `cjpm build` passed after implementation.
- `TODO(selfhost:CHIR)` count in `packages/chir/src`: 0.

## 2026-06-18 Devirtualization Analysis Tightening

- Reference read: C++ `src/CHIR/Analysis/{CallGraphAnalysis,ConstMemberVarCollector,DevirtualizationInfo}.cpp` and matching headers.
- Reworked `ConstMemberVarCollector` to follow the C++ const-member devirtualization algorithm more closely: candidates are now direct immutable instance members, indexed with the inherited-field base offset, and `StoreElementRef` handling uses the real static path/location/value APIs instead of operand-name guessing.
- Kept a narrow `StoreElementByName` compatibility path for pre-`UpdateMemberVarPath` IR, but the faithful `StoreElementRef` path is now the primary behavior.
- Tightened `DevirtualizationInfo` subtype collection to preserve existing custom type objects, record superclass/interface edges through actual `ClassType` values, avoid duplicate subtype records, and model the C++ package relation rule for default-internal types using the available CHIR access attributes.
- Updated call-graph virtual invoke handling to extract the real receiver, method name, and parameter signature from `Invoke`/`InvokeWithException`, strip receiver refs, reject non-class receivers, and sort discovered virtual callees as the C++ path does. The callee lookup remains empty because the current C++ reference still returns an empty set.

## Remaining After Devirtualization Analysis Tightening

- The local CHIR `Attribute` enum still lacks C++ `INTERNAL` and `SKIP_ANALYSIS`, so exact skip-analysis filtering and explicit-internal tests cannot be imported within this scope.
- `CallGraph::GetAllPossibleCalleeOfInvoke` remains limited by the C++ reference's empty implementation.
- Full C++ `AnalysisWrapper`, `Engine`, `Results`, `ConstAnalysis`, `TypeAnalysis`, and template `ValueAnalysis` infrastructure remains absent.

## Verification After Devirtualization Analysis Tightening

- `cjpm build` passed after implementation.
- `TODO(selfhost:CHIR)` count in `packages/chir/src`: 0.
