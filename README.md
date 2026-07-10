# cjcj

A self-hosting rewrite of the Cangjie compiler (`cjcj`, originally C++)
into the **Cangjie** language itself.

- **Source of truth (do not modify):** `/root/cj_build/cangjie_compiler` (C++).
- **Goal:** reimplement the compiler in Cangjie (`.cj`), targeting eventual self-hosting
  (the Cangjie compiler compiling its own source).
- **Toolchain:** `cjc` / `cjpm` (Cangjie 1.1.x).

## Porting strategy

The C++ compiler is ported module-by-module in dependency order:

`Basic → Utils → Option → Lex → AST → Parse → ConditionalCompilation → Modules →
Macro → MetaTransformation → Mangle → Sema → CHIR → CodeGen → IncrementalCompilation →
Frontend → FrontendTool → Driver/main`

Each module is implemented as a Cangjie package under `src/`, mirroring the structure
and public interfaces of its C++ counterpart, with the project kept compilable at each step.

See `docs/PORTING_PLAN.md` for the detailed architecture map and per-module status.

## Status

Work in progress — generated incrementally by an orchestrated Codex pipeline.
Per-module completeness and remaining work are tracked in `docs/STATUS.md`.
