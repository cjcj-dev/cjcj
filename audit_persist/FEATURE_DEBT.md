# Feature debt ledger

| Key | Scope | Deferred C++ body | Reopen condition |
|---|---|---|---|
| `JAVA_AFTERTYPECHECK_BODY` | Java after-type-check diagnostics, type checks, and desugaring reached only by Java mirror/impl/CJMapping declarations or `--target-interop-language=Java` | `src/Sema/NativeFFI/Java/AfterTypeCheck/DiagsInterop.cpp:33-154`; `TypeCheckJavaInterop.cpp:289-349,367-370,400-459`; `DesugarPackage.cpp:83-111` and their Java-only callees | Java after-type-check support is unsealed; resume at every `FEATURE_DEBT(JAVA_AFTERTYPECHECK_BODY)` marker in `packages/sema/src/NativeFFI/Java/JavaInteropManager.cj`. |
| `JAVA_AFTERTYPECHECK_BODY` | Objective-C AST factory and handler chain reached only when `objc.internal` is imported | `src/Sema/NativeFFI/ObjC/Utils/ASTFactory.h:49-278`; `ASTFactory.cpp:42-1538`; `AfterTypeCheck/Desugar.cpp:22-74` and the named handlers selected there | Objective-C after-type-check support is unsealed; resume at every `FEATURE_DEBT(JAVA_AFTERTYPECHECK_BODY)` marker in `packages/sema/src/NativeFFI/ObjC/AfterTypeCheck.cj`. |

The shared key name is mandated by `ops/design/DESUGAR_PHASE_RULING.md` section 2; it covers both
sealed after-type-check interop domains. Ordinary packages retain the complete constructor,
iteration, predicate, and first-early-return paths preceding these debts.
