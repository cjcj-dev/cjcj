# Self-Hosting Port Status

Date: 2026-06-16

This is the refreshed aggregate status for the Cangjie self-hosting compiler
port. It combines the module narratives in `docs/status/*.md` with a source
scan of the current Cangjie tree under `packages/*/src` and the read-only C++
reference tree under `/root/cj_build/cangjie_compiler/src`.

## Aggregate Totals

| Metric | Value |
| --- | ---: |
| Overall behavior-faithful self-host estimate | 24% |
| Remaining source self-host markers | 69 |
| Modules with remaining source markers | Sema, Driver |
| Cangjie `.cj` files | 496 |
| Cangjie source lines | about 119.5K |
| C++ reference source-like files | 733 |
| C++ reference source lines | about 281.9K |
| Required build command | `cjpm build` |
| Build result | pass |
| Build notes | 35 warnings printed across Parse, Sema, and CodeGen |

The build result proves the workspace is syntactically and package-wise
buildable. It does not prove self-hosting readiness: Frontend still writes
summary artifacts, Driver still has a native bitcode-output gate, Sema has many
placeholder components, and multiple packages still use local compatibility
models instead of the real sibling package APIs.

## Module Aggregate

Completeness is a behavior estimate, not a line-count ratio. Reference counts
exclude `CMakeLists.txt` and include source-like files under the C++ `src`
module directory. Cangjie counts include `.cj` files under the package `src`
directory.

| Module | Package path | Ref files | Ref lines | Cangjie files | Cangjie lines | Markers | Estimate | Status |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Basic | `packages/basic` | 15 | 5.3K | 18 | 11.2K | 0 | 65% | Substantial diagnostic/source implementation; exact diagnostic formatting and platform encoding parity remain. |
| Utils | `packages/utils` | 26 | 11.6K | 30 | 7.3K | 0 | 55% | Broad utility surface exists; platform and downstream CHIR/Driver edge cases remain. |
| Option | `packages/option` | 3 | 3.2K | 8 | 3.4K | 0 | 70% | Option table and global options are relatively mature; diagnostics and some filesystem permission behavior remain approximate. |
| Lex | `packages/lex` | 4 | 3.0K | 9 | 10.7K | 0 | 55% | Token/lexer package builds with generated tables; still needs full parser/frontend parity validation. |
| AST | `packages/ast` | 19 | 12.0K | 32 | 12.2K | 0 | 55% | Broad AST/type/node surface exists, but Basic/Lex compatibility copies must be replaced by real dependencies. |
| Parse | `packages/parse` | 31 | 18.3K | 35 | 6.7K | 0 | 40% | Real grammar work exists, but it is not wired to real AST/Lex/Basic and needs full C++ parser corpus parity. |
| ConditionalCompilation | `packages/conditional_compilation` | 2 | 1.0K | 5 | 1.0K | 0 | 50% | Useful conditional pass exists; depends on AST compatibility cleanup and broader frontend integration. |
| Modules | `packages/modules` | 20 | 9.8K | 20 | 4.7K | 0 | 30% | Dependency/package models exist; production CJO, AST serialization, flatbuffer, and real package APIs remain. |
| Macro | `packages/macro` | 17 | 7.9K | 19 | 7.8K | 0 | 40% | Macro flow and FFI loading are represented; local AST/Parse codecs and non-production serialization block parity. |
| MetaTransformation | `packages/meta_transformation` | 2 | 0.0K | 3 | 0.2K | 0 | 20% | Very small package; current work is narrow and CHIR-dependent. |
| Mangle | `packages/mangle` | 7 | 4.2K | 10 | 5.6K | 0 | 45% | Broad naming support exists; CHIR and generic/descriptor parity still depend on downstream completeness. |
| Sema | `packages/sema` | 265 | 96.7K | 136 | 11.9K | 68 | 12% | Critical blocker: many placeholders and missing type inference, overloads, generics, inheritance, legality, FFI, and desugaring. |
| CHIR | `packages/chir` | 147 | 62.9K | 61 | 13.0K | 0 | 25% | IR model and several analyses exist; real typed AST lowering and many IR/optimizer/serializer paths are missing. |
| CodeGen | `packages/codegen` | 118 | 30.8K | 54 | 5.2K | 0 | 15% | LLVM FFI boundary is correct and subset lowering exists; many LLVM lowering surfaces and frontend integration remain. |
| IncrementalCompilation | `packages/incremental_compilation` | 11 | 4.6K | 12 | 5.3K | 0 | 30% | Cache/diff structures exist; production AST/CJO/CHIR integration remains. |
| Frontend | `packages/frontend` | 8 | 3.0K | 9 | 6.1K | 0 | 25% | Stage orchestration exists, but it uses local models and summary outputs instead of real compiler-stage artifacts. |
| FrontendTool | `packages/frontend_tool` | 3 | 1.2K | 4 | 1.0K | 0 | 35% | CLI bridge exists; production behavior depends on Frontend/CodeGen completion. |
| Driver | `packages/driver` | 31 | 5.6K | 30 | 6.1K | 1 | 55% | Native tool orchestration is substantial; one gate remains for missing self-host bitcode output. |

Top-level C++ entry files (`main.cpp`, `main-frontend.cpp`,
`main-macrosrv.cpp`, and `main-chir-dis.cpp`) are only lightly represented by
the `packages/cjc` wrapper and Driver/FrontendTool entrypoints. They should be
tracked explicitly before declaring Driver and executable packaging complete.

## Current Critical Path

1. Wire packages through real dependencies and remove compatibility islands.
2. Finish Sema until the compiler port can be type-checked with production
   semantics.
3. Replace summary CHIR generation with real typed AST-to-CHIR lowering.
4. Complete LLVM CodeGen and connect Frontend/FrontendTool to bitcode output.
5. Replace local CJO, macro, and module serialization with production-compatible
   formats and protocols.
6. Bootstrap: build the port with the C++ compiler, rebuild with the produced
   compiler, then compare stage outputs and run the C++ test corpus.

See `docs/ROADMAP.md` for milestone detail.
