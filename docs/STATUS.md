# Self-Hosting Port Status

Last updated: 2026-07-08 · master @ `2a93e66f`

This is the single aggregate status for the Cangjie self-hosting compiler port
(a faithful 1:1 rewrite of the C++ compiler at `/root/cj_build/cangjie_compiler`,
read-only reference). It supersedes the June-era `STATUS.md`, `ROADMAP.md`,
`PORTING_PLAN.md`, and the per-package `status/*.md` narratives, all of which
predated self-compilation and are now obsolete.

## Governing directive (faithful port)

Faithfully mirror the C++ compiler. No lazy shortcuts: no hand-special-casing per
construct, no facade, no fallback, no "keep a working subset" crutch. Fidelity to
C++ source is the priority — never merge a port that silently omits a C++ rule;
complete every rule/helper or report the gap. The old facade/bridge and the
`parse`-local isolated AST copies have both been removed; there is one source of
truth (`cangjie_compiler::ast`), and the real packages compose into the same
pipeline shape as C++.

## Current milestones (achieved)

- **Self-compile: 18/18 packages compile to staticlib.** The port is
  self-hosting through the real pipeline (parse → sema → CHIR → codegen), no
  facade.
- **bcgate byte-identical: 2368/2490 (95.1%)** against C++ output; 122 differing;
  **0 compile-errors.**
- **difftest: 114/114** passing.
- **smoke15: 15/15** (real multi-package import smoke tests).

## Remaining work

- **bcgate differing 122 → 0**: close the residual byte-identity gaps (mostly
  cosmetic block-label numbering plus a small number of functional roots; see the
  audit manifest under `/tmp/audit/`).
- **A2 stage2 SEGV**: deferred; stage-2 self-compilation crash under
  investigation.
- **for-in CFG root**: for-in delay/exit machinery lowering + CHIR cleanup-pass
  parity (C++ emits the machinery unconditionally and folds via cleanup passes;
  the skip-emission shortcut is rejected as unfaithful).

## Merge / faithfulness gate

A change is mergeable only when: difftest stays green, bcgate does not regress,
the real multi-package self-compile smoke passes, and the change is confirmed to
mirror C++ source. Note that difftest and the bcgate corpus are single-file and
BLIND to import-path regressions — re-verify multi-package self-compile
independently.

## Subsystem → C++ correspondence

Each `packages/<name>` is a faithful port of the same-named C++ component under
`/root/cj_build/cangjie_compiler/src/<Name>` (and its public headers under
`include/cangjie/<Name>`). The mapping is 1:1 by name unless noted.

| selfhost package | C++ component | notes / reference inventory |
|---|---|---|
| `basic` | `src/Basic` | positions, source manager, diagnostic engine |
| `utils` | `src/Utils` | file/path, SipHash, Unicode tables, casting, platform FFI |
| `option` | `src/Option` | compiler options / configuration |
| `lex` | `src/Lex` | tokenizer; token inventory ported from `Tokens.inc` |
| `parse` | `src/Parse` | parser split; consumes real ast/lex/basic |
| `ast` | `src/AST` | AST nodes, types (`ast.Ty`, 23 subclasses), walkers — the shared source of truth |
| `sema` | `src/Sema` | 261 C++ files, ~96.5K lines; TypeChecker/TypeManager |
| `chir` | `src/CHIR` | 269 files, ~90K lines; IR model, AST2CHIR, checker, transforms, serialize |
| `codegen` | `src/CodeGen` | 118 files, ~31K lines; `EmitPackageIR`, CG* context/module, LLVM FFI |
| `mangle` | `src/Mangle` | name mangling |
| `macro` | `src/Macro` | macro engine / runtime |
| `meta_transformation` | `src/MetaTransformation` | |
| `modules` | `src/Modules` | import manager, package graph, cjo serialization |
| `conditional_compilation` | `src/ConditionalCompilation` | |
| `incremental_compilation` | `src/IncrementalCompilation` | |
| `driver` | `src/Driver` | driver orchestration |
| `frontend` | `src/Frontend` | `CompilerInstance`, `CompileStrategy` pipeline driver |
| `frontend_tool` | `src/FrontendTool` | |
| `cjc` | `src/main.cpp` / driver entry | selfhost compiler binary target |
| `compiler_unittest` | (C++ unittests) | ported unit tests as `std.unittest` |

External native dependencies are kept external and bound via C FFI / thin C
adapters (LLVM incl. the patched cjnative tree, flatbuffers, libffi,
libboundscheck, `dl`, platform linkers); these are not reimplemented in Cangjie.

## Related references

- `docs/CODEX_DELEGATION_PLAYBOOK.md` — the Codex-delegated, worktree-parallel
  workflow used to advance the port.
- `/tmp/audit/` — live gap/bcgate audit manifest and status anchor.
