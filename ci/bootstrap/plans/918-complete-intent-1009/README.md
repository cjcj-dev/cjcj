# Frozen #918 production input delivery (2026-10-09)

This is input preparation, with no product production or self-review clearance.
The product source and producer remain
`4d05592c3b0a05b3ab4d554a379e3885faf25cf2` (tree
`84f6c8bd16ef9be457a3b37448391506cc2ab4d3`), regardless of the commit containing
these data files. The tools producer is
`d6edd90ad2da183e9ff5711af699d4b3921f42eb` (tree
`832a87166e0c6663ab588e93d75c546fa1b26f60`).

`complete.intent.json` was frozen by that product's existing
`ci/bootstrap/freeze-sdk-plan.mjs` on kkk2. `complete-final.plan.json` is its
actual result, SHA256
`4b496335d59a3b239fd63054773e0a2d160dc2624e206faed8886224612937df`.
The formal freezer returned 0; `toolchain-sdk.mjs --dry-run` returned 0.
Seven expected producer receipts are missing. No build root or resolved
manifest was created. Build identities in `component-matrix.json` are expected
identities emitted by the existing identity function, not success receipts.

The complete production request remains **blocked**. Adding the explicit
package declaration (`complete-production.intent.json`) to the actual formal
freezer returns `SDK_MANIFEST_REJECT rule=SCHEMA component=plan`, rc=1.
The existing plan-v1 schema accepts only one platform and no package field or
package adapter. `production-scope.json` preserves the SDK/package obligations,
Windows and other platform coverage, and existing holds; it is not an executable
replacement schema. Independent input review must decide the required adapter
work and production authorization. No scope was removed to call this complete.

## Production graph and installation ownership

Official 1009 host -> paired runtime and AST -> complete same-source 53ce native
LLVM -> source-fixed stage1 compiler -> that compiler's full std -> SDK ->
package/independent unpack and use. The schema component is an independent
174db source producer and an explicit compiler/std dependency. No stage2 or
stage3 success is a stage1 prerequisite.

The native owner derives from `sdk-cjdb-producer.mjs:96-142`, exporting whole
`third_party/llvm`, `tools`, `native-closure`, and native securec. It replaces
all seven old 7ed split LLVM producers. LLDB/Python/IntelFeatures and compiler
frontend/LSP exports remain in scope; no `inputOnly` component is used.
Compiler 174db `src/CMakeLists.txt:275-282,315,347,379-381` and
`third_party/cmake/BuildCJDB.cmake:182-206,218-236,260-279` define the native
paths replacing publisher tool/library paths. Actual native output is missing,
so final per-file ownership and aliases must still pass `resolveFiles` against
its real sealed inventory; directory mappings alone do not prove that gate.

The runtime producer alone owns the runtime SO/boundscheck/static archive pair.
The native installation mapping excludes its exported canonical runtime
`libboundscheck.so`; the runtime producer supplies that SDK path and the native
boundscheck aliases retain their canonical relative destination. Native securec
and XML2 replace the former separate physical library installers, using the
same declared boundscheck source/archive. Old support metadata remains historical
in `original-request.json`; it must not become a false native success record.

AST owns its headers and StdAst schema. `compiler-schema` owns StdxChirFormat;
AST's schema mapping excludes that duplicate path. The std mapping retains its
full native/module outputs and excludes the runtime-owned boundscheck and
third-party host inputs. The official source remains an independent complete
host distribution for actual producers; its installation projection excludes
replaced target paths. The authenticated Linux publisher projection excludes
only the three Windows target roots. Windows requirements remain explicit.

`receipt-reuse.json` preserves original source/producer/config/dependency
identities. Actual 1009 publisher bytes and the original successful host package
can be reused as source. Changed producer/build root/installation identities
require a new normal distribution-copy receipt; the old host receipt is not
relabeled. Runtime/compiler/AST/schema/std require real new producer receipts.
The old 7ed/native qualification and old successful std remain historical.

The sharedbuild adapter emits its actual request at the computed directory's
`sharedbuild-request.json` from frozen options and dependency receipts
(`sdk-producers.mjs:84-108`). Its schema-required `producer.recipe` field is a
future declarative path, not a consumed pre-existing request or a receipt.
No successful request/input artifact has been fabricated at that path.

## Non-build evidence and stop

Evidence: `/root/sym_cjcj_918_implement_r6085769397/evidence/` on kkk2;
local retained copies:
`/root/cj_build/agent_scratch/sym_cjcj_918_implement_r6085769397/keep/`.
`execution-record.json` records actual child results, including preparation
failures. A data-only copy adding the old 7ed dylib is rejected precisely by
`LLVM_SOURCE`, rc=1; the unchanged complete frozen plan's dry-run returned 0.
This proves the input guard, with no claim about built product behavior.

A first freeze exposed an old source locator containing only 7ed. It was
corrected to actual existing 53ce objects, then those exact objects were retained
in this lane's private bare input repository and the final plan was frozen.
No old lane source or receipt was rewritten. All validation ran through the
existing wf sh slot and box transport with core soft/hard zero. No resolve,
assembly, product package, CI, push, main operation, shared SDK change, general
tool change, test change, ABI/STD_CJC/stage33 or release/latest clearance occurred.
The new combination's production peak is unknown; the old 30GiB estimate is not
an admission claim. Full input review and new production authorization remain.
