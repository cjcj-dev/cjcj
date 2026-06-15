# Cangjie Compiler Self-Hosting Porting Plan

This plan is for a complete, production-grade, behavior-faithful rewrite of the
compiler code that lives in `/root/cj_build/cangjie_compiler` from C++ to
Cangjie. The reference repository is read-only for this work. Runtime, stdx,
tools, and other sibling repositories are out of scope.

The current C++ compiler was inspected from `README.md`, `build.py`,
`CMakeLists.txt`, `src/CMakeLists.txt`, `src/*/CMakeLists.txt`,
`include/cangjie/**`, and `src/**`. Cangjie 1.1 `cjpm` syntax was validated
against the installed `cjpm init --workspace`, `cjpm init --type=static`, local
`cangjie_stdx` and `cangjie_tools` manifests, and local path dependency
examples such as `gatelib = { path = "../gatelib" }`.

## Scope And Rules

- Port only the compiler modules under `/root/cj_build/cangjie_compiler/src`
  and `/root/cj_build/cangjie_compiler/include/cangjie`.
- Keep LLVM, the patched cjnative LLVM tree, libffi, libboundscheck, `dl`,
  platform linkers, and other external native libraries external. Bind them
  from Cangjie with C FFI declarations and thin C-compatible adapter libraries
  where LLVM exposes only C++ APIs.
- Do not reimplement LLVM, flatbuffers, libffi, libboundscheck, platform
  process APIs, or system linkers.
- Everything else in the compiler repository must become real Cangjie code.
- Self-hosting TODO markers are temporary scaffolding only. A module is not
  complete until every marker named for that module is replaced by working,
  tested logic faithful to the C++ behavior.
- Implemented modules must mirror C++ file decomposition. A C++ component such
  as `SourceManager.h/.cpp` becomes `SourceManager.cj`; `DiagnosticEngine*`
  becomes `DiagnosticEngine.cj` plus comparable implementation files where the
  C++ split is large. Do not collapse a module into one giant file.

## C++ Architecture And Pipeline

The C++ compiler produces the `cjc` executable plus related frontend/tooling
artifacts. CMake builds the compiler from object libraries such as
`CangjieBasic`, `CangjieLex`, `CangjieParse`, `CangjieSema`, `CangjieCHIRBase`,
`CangjieCHIRExtra`, `CangjieCodeGen`, `CangjieDriver`, and
`CangjieFrontendTool`. The driver and code generation targets link LLVM, `dl`,
`boundscheck-static`, and `ffi`.

The production pipeline is:

1. Driver and option parsing
   - `Driver` owns command-line orchestration, toolchain selection, temp files,
     frontend/backend jobs, platform behavior, and external tool invocation.
   - `Option` defines option IDs, parsing tables, global options, warning
     options, target triples, optimization modes, output modes, sanitizer
     options, CHIR dump modes, and C/Java/ObjC interop switches.

2. Frontend setup
   - `Frontend` creates `CompilerInvocation`, `CompilerInstance`,
     `FrontendOptions`, observers, source caches, and compile strategies.
   - `FrontendTool` provides default, CJD, and incremental compiler instances
     used by `cjc`, `cjc-frontend`, IDE/LSP sharing, and the frontend shared
     library.
   - `Basic` and `Utils` provide source management, diagnostics, file helpers,
     Unicode, profiling, concurrency, signal handling, hashing, persistent data
     structures, and platform support used by all later stages.

3. Source ingestion and conditional compilation
   - `SourceManager` loads and indexes source buffers, assigns file IDs, tracks
     comments, computes line offsets, and maps positions to source text.
   - `ConditionalCompilation` evaluates conditional feature and target gates
     before the parser and semantic pipeline consume the filtered program.

4. Lexing
   - `Lex` converts source text or macro-provided tokens into `Token` streams.
     It handles token kinds from `Tokens.inc`, contextual keywords, string
     parts, raw string delimiters, comments, lookahead, quote mode, and token
     collection for parser/macro consumers.

5. Parsing
   - `Parse` builds the AST from tokens. The parser is split by grammar area:
     atoms, declarations, expressions, patterns, types, imports, modifiers,
     macros, quotes, annotations, features, and native FFI parsers for Java and
     ObjC interop.
   - `ASTChecker` and `ASTHasher` support validity checking and cache keys.

6. AST and modules
   - `AST` owns the syntax and semantic tree model: declarations, expressions,
     types, patterns, comments, attributes, identifiers, source ranges, scopes,
     symbols, walkers, cloning, search, and query support.
   - `Modules` loads and writes `.cjo`/serialized AST data through flatbuffers,
     manages package/import state, dependency graphs, external libraries, and
     incremental import contexts.

7. Macro expansion
   - `Macro` serializes AST nodes/tokens, resolves macro calls, invokes macro
     processes or macro servers, evaluates results, reconstructs AST fragments,
     handles test entry construction, and has cjnative-specific invocation
     support. It depends on flatbuffers, libffi/runtime invocation, boundscheck,
     and LLVM/cjnative-linked artifacts in the current build.

8. Semantic analysis
   - `Sema` performs prechecks, name lookup, scope management, type checking,
     type inference, generic instantiation, inheritance checks, desugaring
     before/during/after type checking, FFI legality, CJMP checks, Java/ObjC
     interop checking/desugaring/code generation, mock/test support, and plugin
     annotations.

9. Mangle
   - `Mangle` produces stable ABI/linkage names for AST and CHIR entities,
     including standard package names, compression, CHIR type mangling, and
     mangle utilities. CodeGen and incremental caches consume this output.

10. CHIR
    - `CHIR` converts typed AST packages to Cangjie High-level IR, builds and
      owns the IR graph, checks invariants, serializes/deserializes CHIR,
      interprets bytecode for constant evaluation, computes analyses, and runs
      transformations and optimizations before native lowering.
    - Major subareas: `AST2CHIR`, `IR`, `Analysis`, `Checker`,
      `Interpreter`, `Optimization`, `Serializer`, `Transformation`, and
      `Utils`.

11. CodeGen
    - `CodeGen` lowers CHIR to LLVM IR. It owns Cangjie-specific codegen types,
      package and module contexts, expression dispatchers, intrinsic lowering,
      overflow lowering, debug info, metadata, type info, incremental IR
      generation, cjnative-specific lowering, and post-generation IR cleanup.
    - LLVM remains external. Cangjie code owns the compiler logic and calls
      LLVM through C FFI handles.

12. Incremental compilation
    - `IncrementalCompilation` computes AST and semantic cache data, diff data,
      pollution maps, dependency serialization, cached mangle maps, incremental
      scope analysis, and logging. It feeds `Frontend`, `Modules`, `Sema`,
      `CHIR`, and `CodeGen`.

## Module Dependency Graph

This is the include-level dependency graph derived from `#include
"cangjie/<module>/..."` across public headers and source files. It is not a
pure DAG because the C++ public surface has cycles, especially around AST,
Parse, Sema, Frontend, and tooling.

| Module | Direct include dependencies |
| --- | --- |
| Basic | AST, Lex, Utils |
| Utils | AST, Basic, Driver, Frontend, Lex, Macro, Modules, Parse |
| Option | Basic, Utils |
| Lex | Basic, Utils |
| AST | Basic, Parse, Utils |
| Parse | AST, Basic, IncrementalCompilation, Lex, Utils |
| ConditionalCompilation | AST, Basic, Frontend, Option, Utils |
| Modules | AST, Basic, Frontend, IncrementalCompilation, Lex, Mangle, Option, Utils |
| Macro | AST, Basic, ConditionalCompilation, Frontend, Lex, Modules, Parse, Utils |
| MetaTransformation | none at include level |
| Mangle | AST, Basic, CHIR, Parse, Utils |
| Sema | AST, Basic, Driver, Frontend, IncrementalCompilation, Macro, Mangle, Modules, Option, Parse, Utils |
| CHIR | AST, Basic, Driver, Mangle, MetaTransformation, Modules, Option, Utils |
| CodeGen | Basic, CHIR, Frontend, FrontendTool, IncrementalCompilation, Mangle, Option, Utils |
| IncrementalCompilation | AST, Basic, Mangle, Modules, Parse, Sema, Utils |
| Frontend | AST, Basic, CHIR, ConditionalCompilation, Driver, IncrementalCompilation, Macro, Mangle, Modules, Parse, Sema, Utils |
| FrontendTool | AST, Basic, CHIR, CodeGen, Driver, Frontend, IncrementalCompilation, Macro, Mangle, Modules, Parse, Sema, Utils |
| Driver | Basic, FrontendTool, Option, Utils |

Build/package layering should therefore be staged by stable public APIs rather
than by assuming acyclic source imports:

1. Foundation packages: `basic`, `utils`, `option`, `lex`.
2. Tree packages: `ast`, `parse`, `conditional_compilation`.
3. Package and macro packages: `modules`, `macro`, `meta_transformation`.
4. Name and semantic packages: `mangle`, `sema`.
5. IR packages: `chir`, `incremental_compilation`.
6. Native emission packages: `codegen`.
7. Orchestration packages: `frontend`, `frontend_tool`, `driver`.

Cycles must be broken with Cangjie interfaces, lightweight IDs, and package
private implementation files, not by weakening behavior. For example, AST
should not import the parser implementation; it should keep only the query or
kind contracts required by the C++ public API. Frontend/Driver cycles should be
kept at orchestration boundaries.

## Public Header And Type Inventory

Counts are from `include/cangjie/<Module>` and `src/<Module>`.

| Module | Public headers | Source files | Primary public surface |
| --- | ---: | ---: | --- |
| Basic | 16 | 15 | `Position`, `Source`, `SourceManager`, `DiagnosticEngine`, `Diagnostic`, `DiagnosticBuilder`, `DiagnosticEmitter`, `DiagnosticJsonFormatter`, `Range`, `DiagKind`, `DiagSeverity`, `DiagCategory`, `DiagKindRefactor`, `MacroCallDiagInfo`, `InteropCJPackageConfigReader`, `PackageConfig`, `DiagColor`, `Linkage`, `StringConvertor`, `UGTypeKind` |
| Utils | 19 | 26 | casting helpers, `FileUtil`, `Directory`, `FileMode`, `AccessResultType`, Unicode conversion types, `UnicodeCharRange`, `UnicodeCharSet`, `ProfileRecorder`, `TaskQueue`, `Semaphore`, `SipHash`, `SafePointer`, `PData`, `PSet`, `ParallelUtil`, `TriggerPointSetter`, profile/user timing and memory helpers |
| Option | 3 | 3 | `Option`, `GlobalOptions`, `WarningOptionMgr`, `OptionTable`, `ArgList`, `ArgInstance`, `OptionArgInstance`, `InputArgInstance`, option `ID`, `Kind`, `Backend`, `Group`, `WarnGroup`, target/optimization/output enums |
| Lex | 5 | 4 | `Lexer`, `Token`, `TokenKind`, `StringPart`, `TokenVecMap`, token arrays from `Tokens.inc`, annotation tokens from `AnnotationTokens.inc`, contextual keyword helpers |
| AST | 25 | 19 | AST node hierarchy from `Node.h`, `ASTKind`, `ExprKind`, `BuiltInType`, `TypeKind`, `Ty` hierarchy, `Identifier`, `SrcIdentifier`, `ASTContext`, `AttributePack`, `Symbol`, `SymbolApi`, `Comment`, `CommentGroup`, `Walker`, `ASTCloner`, `IntLiteral`, search/query/print/create/recover/desugar utilities |
| Parse | 4 | 30 | `Parser`, `ParserImpl` pimpl contract, parser scope/expr enums, `ASTChecker`, `ASTHasher`, modifier conflict rules, native FFI parsers |
| ConditionalCompilation | 1 | 2 | `ConditionalCompilation` and its implementation object |
| Modules | 6 | 20 | `ASTWriter`, `ASTLoader`, `CjoManager`, `PackageManager`, `ImportManager`, `PackageInfo`, `ExternalLibCfg`, `DepType`, `PackageRelation`, flatbuffer typedefs and `ExportConfig` |
| Macro | 10 | 17 | `MacroCall`, `MacroExpansion`, `MacroEvaluation`, `MacroEvalMsgSerializer`, `MacroCollector`, `MacroFormatter`, `NodeWriter`, token/node serialization aliases, `RuntimeInit`, `MacroProcMsger`, `TestEntryConstructor`, runtime invoke config |
| MetaTransformation | 1 | 2 | `MetaTransformKind`, `MetaTransformConcept`, `MetaTransformPluginManager`, `MetaTransformPluginBuilder`, `MetaTransformPluginInfo`, `CHIRPluginManager` |
| Mangle | 7 | 7 | `ASTMangler`, `BaseMangler`, `ManglerContext`, `CHIRMangler`, CHIR and CHIR type mangling utilities, standard package table, compression |
| Sema | 7 | 261 | `TypeChecker`, `TypeManager`, `GenericInstantiationManager`, `TestManager`, type compatibility, common type aliases, blame/substitution/constraint structures, incremental utilities, desugar entrypoints |
| CHIR | 121 | 147 | `ToCHIR`, `AST2CHIR`, IR `Package`, `CHIRContext`, `CHIRBuilder`, `Base`, `Type`, `CHIRType`, custom type defs, `Value`, `Function`, `Block`, `Expression`, terminators, literal values, annotations, analysis domains, optimization passes, interpreter bytecode/value/result types, serializers, transformations, visitor/printer utilities |
| CodeGen | 1 | 118 | public `EmitPackageIR` plus implementation surfaces for `CGContext`, `CGModule`, `CGFunction`, `CGPkgContext`, `CGType` hierarchy, `IRBuilder`, `DIBuilder`, dispatchers, cjnative metadata/type info, incremental generation, and LLVM IR utility functions |
| IncrementalCompilation | 6 | 11 | `ASTCacheCalculator`, `CachedMangleMap`, `CompilationCache`, `IncrementalCompilationLogger`, `IncrementalScopeAnalysis`, cache/diff/dependency/pollution utilities |
| Frontend | 5 | 8 | `CompilerInvocation`, `CompilerInstance`, `CHIRData`, `CompileStage`, `CompileStrategy`, `FullCompileStrategy`, `FrontendOptions`, `FrontendObserver`, `MultiFrontendObserver` |
| FrontendTool | 4 | 3 | `DefaultCompilerInstance`, `IncrementalCompilerInstance`, `CjdCompilerInstance`, frontend tool entry API |
| Driver | 15 | 31 | `Driver`, `DriverOptions`, `Backend`, `CJNATIVEBackend`, `Tool`, `ToolID`, `ToolInfo`, `ToolFuture`, platform futures, `ToolChain`, `GCCPathScanner`, `TempFileManager`, temp-file models, tool options and standard-library maps |

Public header inventory by module:

- Basic: `Color.h`, `DiagnosticEmitter.h`, `DiagnosticEngine.h`,
  `DiagnosticJsonFormatter.h`, `Display.h`, `InteropCJPackageConfigReader.h`,
  `Linkage.h`, `MacroCallDiagInfo.h`, `Match.h`, `Position.h`, `Print.h`,
  `SourceManager.h`, `StringConvertor.h`, `UGTypeKind.h`, `Utils.h`,
  `Version.h`.
- Utils: `Casting.h`, `CastingTemplate.h`, `CheckUtils.h`,
  `ConstantsUtils.h`, `FileUtil.h`, `FloatFormat.h`, `ICEUtil.h`,
  `Macros.h`, `ParallelUtil.h`, `PartiallyPersistent.h`,
  `ProfileRecorder.h`, `SafePointer.h`, `Semaphore.h`, `Signal.h`,
  `SipHash.h`, `StdUtils.h`, `TaskQueue.h`, `Unicode.h`, `Utils.h`.
- Option: `Option.h`, `OptionTable.h`, `Options.inc`.
- Lex: `AnnotationToken.h`, `AnnotationTokens.inc`, `Lexer.h`, `Token.h`,
  `Tokens.inc`.
- AST: `ASTCasting.h`, `ASTContext.h`, `ASTKind.inc`,
  `ASTTypeValidator.h`, `AttributePack.h`, `Cache.h`, `Clone.h`,
  `Comment.h`, `Create.h`, `Identifier.h`, `IntLiteral.h`, `Match.h`,
  `Node.h`, `NodeX.h`, `PrintNode.h`, `Query.h`, `RecoverDesugar.h`,
  `ReferenceType.h`, `ScopeManagerApi.h`, `Searcher.h`, `Symbol.h`,
  `TypeKind.inc`, `Types.h`, `Utils.h`, `Walker.h`.
- Parse: `ASTChecker.h`, `ASTHasher.h`, `ParseModifiersRules.h`,
  `Parser.h`.
- ConditionalCompilation: `ConditionalCompilation.h`.
- Modules: `ASTSerialization.h`, `ASTSerializationTypeDef.h`,
  `CjoManager.h`, `ImportManager.h`, `ModulesUtils.h`, `PackageManager.h`.
- Macro: `InvokeConfig.h`, `InvokeUtil.h`, `MacroCall.h`,
  `MacroCommon.h`, `MacroEvalMsgSerializer.h`, `MacroEvaluation.h`,
  `MacroExpansion.h`, `NodeSerialization.h`, `TestEntryConstructor.h`,
  `TokenSerialization.h`.
- MetaTransformation: `MetaTransform.h`.
- Mangle: `ASTMangler.h`, `BaseMangler.h`, `CHIRMangler.h`,
  `CHIRManglingUtils.h`, `CHIRTypeManglingUtils.h`, `MangleUtils.h`,
  `StdPkg.inc`.
- Sema: `CommonTypeAlias.h`, `Desugar.h`,
  `GenericInstantiationManager.h`, `IncrementalUtils.h`, `TestManager.h`,
  `TypeChecker.h`, `TypeManager.h`.
- IncrementalCompilation: `ASTCacheCalculator.h`, `CachedMangleMap.h`,
  `CompilationCache.h`, `IncrementalCompilationLogger.h`,
  `IncrementalScopeAnalysis.h`, `Utils.h`.
- Frontend: `CompileStrategy.h`, `CompilerInstance.h`,
  `CompilerInvocation.h`, `FrontendObserver.h`, `FrontendOptions.h`.
- FrontendTool: `CjdCompilerInstance.h`, `DefaultCompilerInstance.h`,
  `FrontendTool.h`, `IncrementalCompilerInstance.h`.
- Driver: `Backend/Backend.h`, `Backend/CJNATIVEBackend.h`, `Driver.h`,
  `DriverOptions.h`, `Stdlib.inc`, `StdlibMap.h`, `TempFileInfo.h`,
  `TempFileManager.h`, `Tool.h`, `ToolFuture.h`, `ToolOptions.h`,
  `Toolchains/GCCPathScanner.h`, `Toolchains/ToolChain.h`, `Tools.inc`,
  `Utils.h`.
- CodeGen: `EmitPackageIR.h`. The rest of CodeGen's public-to-module surface
  is currently in `src/CodeGen/**/*.h` and must be mirrored under
  `packages/codegen/src/` because the C++ module intentionally exposes most
  implementation contracts only inside the module.
- CHIR: `CHIR.h`; `AST2CHIR/AST2CHIR.h`,
  `AST2CHIR/AST2CHIRChecker.h`, `AST2CHIR/AST2CHIRNodeMap.h`,
  `AST2CHIR/GlobalDeclAnalysis.h`, `AST2CHIR/GlobalVarInitializer.h`,
  `AST2CHIR/ImplicitImportedFuncMgr.h`, `AST2CHIR/Utils.h`,
  `AST2CHIR/CollectLocalConstDecl/CollectLocalConstDecl.h`,
  `AST2CHIR/TranslateASTNode/ExceptionTypeMapping.h`,
  `AST2CHIR/TranslateASTNode/Translator.h`; `Analysis/ActiveStatePool.h`,
  `Analysis/Analysis.h`, `Analysis/AnalysisWrapper.h`,
  `Analysis/Arithmetic.h`, `Analysis/BoolDomain.h`,
  `Analysis/CallGraphAnalysis.h`, `Analysis/ConstAnalysis.h`,
  `Analysis/ConstAnalysisWrapper.h`, `Analysis/ConstMemberVarCollector.h`,
  `Analysis/ConstantRange.h`, `Analysis/DevirtualizationInfo.h`,
  `Analysis/Engine.h`, `Analysis/FlatSet.h`, `Analysis/GenKillAnalysis.h`,
  `Analysis/GetOrThrowResultAnalysis.h`, `Analysis/MaybeInitAnalysis.h`,
  `Analysis/MaybeUninitAnalysis.h`,
  `Analysis/ReachingDefinitionAnalysis.h`, `Analysis/Results.h`,
  `Analysis/SInt.h`, `Analysis/SIntDomain.h`, `Analysis/TypeAnalysis.h`,
  `Analysis/Utils.h`, `Analysis/ValueAnalysis.h`,
  `Analysis/ValueDomain.h`, `Analysis/ValueRangeAnalysis.h`;
  `Checker/AnnotationChecker.h`, `Checker/CHIRChecker.h`,
  `Checker/ComputeAnnotations.h`, `Checker/OverflowChecking.h`,
  `Checker/UnreachableBranchCheck.h`, `Checker/VarInitCheck.h`;
  `IR/AnnoInfo.h`, `IR/Annotation.h`, `IR/AttributeInfo.h`, `IR/Base.h`,
  `IR/CHIRBuilder.h`, `IR/CHIRContext.h`, `IR/DebugLocation.h`,
  `IR/IntrinsicKind.h`, `IR/Package.h`,
  `IR/Expression/Expression.h`, `IR/Expression/ExpressionWrapper.h`,
  `IR/Expression/ExprKind.inc`, `IR/Expression/Terminator.h`,
  `IR/Type/CHIRType.h`, `IR/Type/ClassDef.h`,
  `IR/Type/CustomTypeDef.h`, `IR/Type/EnumDef.h`,
  `IR/Type/ExtendDef.h`, `IR/Type/PrivateTypeConverter.h`,
  `IR/Type/StructDef.h`, `IR/Type/Type.h`,
  `IR/Value/LiteralValue.h`, `IR/Value/Value.h`;
  `Interpreter/BCHIR.h`, `Interpreter/BCHIRInterpreter.h`,
  `Interpreter/BCHIRLinker.h`, `Interpreter/BCHIRPrinter.h`,
  `Interpreter/BCHIRResult.h`, `Interpreter/CHIR2BCHIR.h`,
  `Interpreter/ConstEval.h`, `Interpreter/InterpreterArena.h`,
  `Interpreter/InterpreterEnv.h`, `Interpreter/InterpreterStack.h`,
  `Interpreter/InterpreterValue.h`, `Interpreter/InterpreterValueUtils.h`,
  `Interpreter/OpCodes.h`, `Interpreter/OpCodes.inc`, `Interpreter/Utils.h`;
  `Optimization/ArrayLambdaOpt.h`, `Optimization/ArrayListConstStartOpt.h`,
  `Optimization/BlockGroupCopyHelper.h`, `Optimization/ConstPropagation.h`,
  `Optimization/DeadCodeElimination.h`, `Optimization/Devirtualization.h`,
  `Optimization/FunctionInline.h`, `Optimization/GetRefToArrayElem.h`,
  `Optimization/LambdaInline.h`, `Optimization/MergeBlocks.h`,
  `Optimization/OptFuncRetType.h`, `Optimization/RangePropagation.h`,
  `Optimization/RedundantFutureRemoval.h`,
  `Optimization/RedundantGetOrThrowElimination.h`,
  `Optimization/RedundantLoadElimination.h`, `Optimization/UnitUnify.h`,
  `Optimization/UselessAllocateElimination.h`; `Serializer/CHIRDeserializer.h`,
  `Serializer/CHIRSerializer.h`; `Transformation/BoxRecursionValueType.h`,
  `Transformation/ClosureConversion.h`, `Transformation/FlatForInExpr.h`,
  `Transformation/MarkClassHasInited.h`, `Transformation/NoSideEffectMarker.h`,
  `Transformation/ReplaceSrcCodeImportedVal.h`,
  `Transformation/SanitizerCoverage.h`,
  `Transformation/UpdateMemberVarPath.h`,
  `Transformation/GenerateVTable/GenerateVTable.h`,
  `Transformation/GenerateVTable/UpdateOperatorVTable.h`,
  `Transformation/GenerateVTable/VTableGenerator.h`,
  `Transformation/GenerateVTable/WrapMutFunc.h`,
  `Transformation/GenerateVTable/WrapVirtualFunc.h`; `Utils/CHIRCasting.h`,
  `Utils/CHIRPrinter.h`, `Utils/ConstantUtils.h`, `Utils/ToStringUtils.h`,
  `Utils/UserDefinedType.h`, `Utils/Utils.h`,
  `Utils/Visitor/SimpleIterator.h`, `Utils/Visitor/Visitor.h`.

## Cangjie Workspace And Package Layout

Root `cjpm.toml` should be a workspace once implementation starts:

```toml
[workspace]
  members = [
    "packages/basic",
    "packages/utils",
    "packages/option",
    "packages/lex",
    "packages/ast",
    "packages/parse",
    "packages/conditional_compilation",
    "packages/modules",
    "packages/macro",
    "packages/meta_transformation",
    "packages/mangle",
    "packages/sema",
    "packages/chir",
    "packages/codegen",
    "packages/incremental_compilation",
    "packages/frontend",
    "packages/frontend_tool",
    "packages/driver"
  ]
  build-members = [
    "packages/driver"
  ]
  test-members = [
    "packages/basic",
    "packages/utils",
    "packages/option",
    "packages/lex",
    "packages/ast",
    "packages/parse",
    "packages/conditional_compilation",
    "packages/modules",
    "packages/macro",
    "packages/meta_transformation",
    "packages/mangle",
    "packages/sema",
    "packages/chir",
    "packages/codegen",
    "packages/incremental_compilation",
    "packages/frontend",
    "packages/frontend_tool",
    "packages/driver"
  ]
  compile-option = ""
  override-compile-option = ""
  link-option = ""
  target-dir = ""
  script-dir = ""

[dependencies]
```

Each package uses current `cjpm` package syntax:

```toml
[package]
  cjc-version = "1.1.0"
  name = "cangjie_compiler_basic"
  organization = ""
  description = "Self-hosted Cangjie compiler Basic module"
  version = "0.1.0"
  target-dir = ""
  script-dir = ""
  src-dir = "src"
  output-type = "static"
  compile-option = ""
  override-compile-option = ""
  link-option = ""
  package-configuration = {}

[dependencies]
```

Path dependencies use local package entries:

```toml
[dependencies]
  cangjie_compiler_basic = { path = "../basic" }
  cangjie_compiler_utils = { path = "../utils" }
```

Package mapping:

| C++ module | Package path | Package name | Cangjie package declaration | Output |
| --- | --- | --- | --- | --- |
| Basic | `packages/basic` | `cangjie_compiler_basic` | `package cangjie_compiler::basic` | static |
| Utils | `packages/utils` | `cangjie_compiler_utils` | `package cangjie_compiler::utils` | static |
| Option | `packages/option` | `cangjie_compiler_option` | `package cangjie_compiler::option` | static |
| Lex | `packages/lex` | `cangjie_compiler_lex` | `package cangjie_compiler::lex` | static |
| AST | `packages/ast` | `cangjie_compiler_ast` | `package cangjie_compiler::ast` | static |
| Parse | `packages/parse` | `cangjie_compiler_parse` | `package cangjie_compiler::parse` | static |
| ConditionalCompilation | `packages/conditional_compilation` | `cangjie_compiler_conditional_compilation` | `package cangjie_compiler::conditional_compilation` | static |
| Modules | `packages/modules` | `cangjie_compiler_modules` | `package cangjie_compiler::modules` | static |
| Macro | `packages/macro` | `cangjie_compiler_macro` | `package cangjie_compiler::macro` | static |
| MetaTransformation | `packages/meta_transformation` | `cangjie_compiler_meta_transformation` | `package cangjie_compiler::meta_transformation` | static |
| Mangle | `packages/mangle` | `cangjie_compiler_mangle` | `package cangjie_compiler::mangle` | static |
| Sema | `packages/sema` | `cangjie_compiler_sema` | `package cangjie_compiler::sema` | static |
| CHIR | `packages/chir` | `cangjie_compiler_chir` | `package cangjie_compiler::chir` | static |
| CodeGen | `packages/codegen` | `cangjie_compiler_codegen` | `package cangjie_compiler::codegen` | static |
| IncrementalCompilation | `packages/incremental_compilation` | `cangjie_compiler_incremental_compilation` | `package cangjie_compiler::incremental_compilation` | static |
| Frontend | `packages/frontend` | `cangjie_compiler_frontend` | `package cangjie_compiler::frontend` | static |
| FrontendTool | `packages/frontend_tool` | `cangjie_compiler_frontend_tool` | `package cangjie_compiler::frontend_tool` | static |
| Driver | `packages/driver` | `cangjie_compiler_driver` | `package cangjie_compiler::driver` | executable |

Per-package file layout:

```text
packages/<module>/
  cjpm.toml
  src/
    <C++ component name>.cj
    ...
  tests/
    ...
```

Examples:

```text
packages/basic/src/Position.cj
packages/basic/src/SourceManager.cj
packages/basic/src/DiagnosticEngine.cj
packages/basic/src/DiagnosticEmitter.cj
packages/lex/src/Token.cj
packages/lex/src/Lexer.cj
packages/parse/src/Parser.cj
packages/parse/src/ParseExpr.cj
packages/sema/src/TypeChecker.cj
packages/sema/src/TypeCheckExpr/AssignExpr.cj
packages/chir/src/IR/Value/Value.cj
packages/chir/src/AST2CHIR/TranslateASTNode/TranslateCallExpr.cj
packages/codegen/src/Base/CGTypes/CGType.cj
packages/codegen/src/CJNative/EmitPackageIR.cj
```

The file count should stay in the same order of magnitude as C++:
Basic about 15 files, Utils about 26, Lex about 4, AST about 19 plus public
model splits, Parse about 30, Modules about 20, Macro about 17, Sema about
261, CHIR about 147, CodeGen about 118, Driver about 31.

## External Native Library And FFI Plan

Cangjie foreign declarations use `foreign func` and C pointer types such as
`CPointer<T>`, `CString`, and `CFunc<...>`. The self-hosted compiler should keep
all unsafe pointer ownership localized in `packages/*/src/ffi/` or
`packages/codegen/src/llvm_ffi/` wrappers, then expose safe Cangjie handle
types to the rest of the module.

External libraries to keep native:

- LLVM/cjnative patched tree and LLVM tools/libraries.
- libffi, used for macro/native invocation.
- libboundscheck, currently linked for LLVMCore and interrupt/safe function
  support.
- flatbuffers runtime and generated schema support for `.cjo`, AST, macro, and
  CHIR serialization.
- `dl`, pthread/process APIs, platform SDK libraries, system linkers, and other
  toolchain dependencies currently invoked by Driver.

The direct LLVM C API surface to bind first:

- Core IR: `llvm-c/Core.h` for contexts, modules, types, values, constants,
  functions, basic blocks, instructions, attributes where available, metadata
  handles where available, and IR builder operations.
- Analysis and verification: `llvm-c/Analysis.h` for module/function
  verification.
- Bitcode: `llvm-c/BitWriter.h` and `llvm-c/BitReader.h` for `.bc` emission and
  loading.
- IR reader: `llvm-c/IRReader.h` for reading textual LLVM IR in incremental
  and split-codegen paths.
- Target setup and emission: `llvm-c/Target.h`,
  `llvm-c/TargetMachine.h`, `llvm-c/Initialization.h`, and
  `llvm-c/Support.h`.
- Debug info: `llvm-c/DebugInfo.h` for DIBuilder-equivalent metadata where the
  C API is sufficient.
- Passes/transforms: `llvm-c/Transforms/PassBuilder.h`,
  `llvm-c/Transforms/PassManagerBuilder.h`, `llvm-c/Transforms/Scalar.h`,
  `llvm-c/Transforms/IPO.h`, `llvm-c/Transforms/Vectorize.h`,
  `llvm-c/Transforms/InstCombine.h`, `llvm-c/Transforms/Utils.h`, and
  `llvm-c/Transforms/AggressiveInstCombine.h`.
- Link/object support as needed by Driver and incremental CodeGen:
  `llvm-c/Linker.h`, `llvm-c/Object.h`, `llvm-c/Error.h`.

The C++ CodeGen currently uses LLVM APIs that are not fully covered by the C
API: `llvm::IRBuilder`, `DIBuilder` convenience calls, `SmallVector`,
`DataLayout`, `DominatorTree`, `LoopInfo`, cloning/value mapping,
`removeUnreachableBlocks`, `MergeBlockIntoPredecessor`, bitcode lazy loading,
`CommonBitmap`, `CJStructTypeGCInfo`, custom cjnative metadata, and numerous
C++ casts (`isa`, `cast`, `dyn_cast`). For those cases, add a small native
adapter library under this repository, for example:

```text
native/llvm_shim/
  cj_llvm_shim.h
  cj_llvm_shim.cpp
```

The shim must expose only stable `extern "C"` functions over opaque handles,
for example `CJLLVMContextRef`, `CJLLVMModuleRef`, `CJLLVMTypeRef`,
`CJLLVMValueRef`, `CJLLVMBasicBlockRef`, `CJLLVMBuilderRef`, and
`CJLLVMDIBuilderRef`. Its implementation may call LLVM C++ APIs, but no C++
compiler logic may live there. All semantic lowering, layout decisions,
mangling decisions, metadata policy, optimization decisions, and incremental
rules remain in Cangjie.

CodeGen binding phases:

1. Opaque handle layer and ownership: create/dispose contexts, modules,
   builders, target machines, messages, and memory buffers. Add leak tests.
2. Type/value construction: integer, float, pointer, array, struct, function,
   vector, constant, null/undef, globals, functions, parameters, attributes.
3. Basic blocks and instructions: alloca, load/store, GEP, call, invoke,
   branch, switch/multibranch lowering, return, throw/landingpad equivalents,
   arithmetic, comparisons, casts, atomics, intrinsics.
4. Metadata/debug info: DI files, compile units, subprograms, local variables,
   derived/composite types, locations, named metadata, Cangjie type metadata.
5. Module operations: verification, bitcode write/read, IR text dump/load,
   linkage/visibility, data layout, target triple, object emission.
6. Transform helpers: local cleanup, unreachable block removal, merge block
   into predecessor, cloning, value mapping, LICM-related helpers, call graph
   helpers, and custom cjnative metadata shims.
7. Driver integration: link with the same LLVM libraries as C++ CMake does:
   `${LLVM_LIBS}`, platform `-lLLVM`/`-lLLVM-15` variants for
   `cangjie-frontend`, `boundscheck-static`, `${ffi}`, and platform system
   libraries.

## Port Order

The port order optimizes for bootstrapping, testability, and dependency
stability. Every phase must keep `cjpm build` and focused tests passing before
the next phase starts.

1. Workspace and scaffolding
   - Add root workspace and package manifests.
   - Add minimal package placeholders with module-named self-hosting TODO
     markers only where needed to keep the build graph alive.
   - Add build scripts to locate external native libraries without touching the
     C++ reference repository.

2. Basic
   - Implement `Position`, ranges, source manager, diagnostics, colors, string
     conversion, version, and interop package config reading.
   - Golden tests: source offsets, diagnostic formatting, JSON diagnostics.

3. Utils
   - File/path utilities, Unicode, checks/assertions, hashing, profiles,
     semaphore/task queue, persistent sets, signals, platform helpers.
   - Golden tests: Unicode normalization/width, path normalization, hash
     compatibility.

4. Option
   - Port option tables and `Options.inc` generation strategy, global options,
     warnings, target info, serialized option behavior.
   - Golden tests: every visible C++ option parses and serializes identically.

5. Lex
   - Tokens, annotation tokens, lexer state machine, comments, string parts,
     quote mode, lookahead/reset behavior, contextual keywords.
   - Golden tests: token streams against C++ for full syntax corpus.

6. AST
   - Node/type hierarchies, attributes, comments, identifiers, context, symbol
     and scope APIs, clone/create/walk/search/query/print utilities.
   - Tests: structural equality, source positions, walker behavior, AST dumps.

7. Parse
   - Parser component by component: imports, declarations, expressions,
     patterns, types, annotations, features, macros, quotes, native FFI parsers.
   - Tests: parse trees and diagnostics matched to C++.

8. ConditionalCompilation
   - Feature/target condition evaluation and source filtering.
   - Tests: cfg matrix across target triples and feature flags.

9. Modules
   - Package manager, import manager, `.cjo` manager, dependency graph,
     flatbuffer AST serialization/deserialization through external bindings.
   - Tests: module graph, import visibility, cache read/write compatibility.

10. Macro
    - Node/token serialization, macro call resolution, runtime/server/client
      invocation, macro expansion, test entry construction, cjnative-specific
      invocation.
    - Tests: macro expansion byte-for-byte AST/token compatibility and process
      failure diagnostics.

11. MetaTransformation
    - Plugin builder/manager and CHIR plugin registration surface.
    - Tests: plugin discovery, ordering, and failure propagation.

12. Mangle
    - AST and CHIR manglers, compression, standard package table, CHIR type
      mangling.
    - Tests: mangle corpus against C++ output.

13. Sema
    - Precheck, scope, lookup, type manager, type checker, inference,
      desugaring, inheritance, generic instantiation, FFI, CJMP, Java/ObjC
      interop, plugins, test/mock support.
    - Tests: type diagnostics, desugared AST, interop generated declarations,
      generic instantiation, incremental semantic data.

14. CHIR
    - IR model, AST2CHIR, checker, analyses, interpreter/const eval,
      optimizations, transformations, serializer/deserializer.
    - Tests: CHIR dumps per phase, invariants, const eval, serialized CHIR,
      optimization fixed points.

15. IncrementalCompilation
    - AST diff/cache, semantic cache, dependency serialization, pollution
      analysis, incremental scope analysis, logs.
    - Tests: edit matrix with no-change/increment/rollback/invalid paths.

16. CodeGen
    - LLVM FFI/shim, CG type model, IR builder, expression dispatchers,
      cjnative metadata/type info, debug info, bitcode/object emission,
      incremental generation.
    - Tests: LLVM IR and bitcode golden tests, runtime execution smoke tests,
      debug info checks, target matrix.

17. Frontend
    - Invocation, compiler instance, compile strategy, observers, source cache,
      full pipeline wiring.
    - Tests: full frontend compile modes, dumps, diagnostic phases.

18. FrontendTool
    - Default, CJD, and incremental compiler instances plus frontend tool entry.
    - Tests: `cjc-frontend` behavior and IDE/LSP-facing library behavior.

19. Driver
    - CLI entry, toolchain selection, backend jobs, process futures, temp files,
      platform link commands, frontend/backend orchestration.
    - Tests: command-line compatibility, target triples, cross compile command
      generation, temp cleanup, process failures.

20. Self-host closure
    - Build the Cangjie compiler with the C++ compiler.
    - Use the resulting self-hosted compiler to rebuild itself.
    - Compare generated artifacts, diagnostics, CHIR/LLVM dumps, option output,
      and test suite results with the C++ compiler.

## Completion Criteria

A module is complete only when:

- Its Cangjie package mirrors the C++ file decomposition with comparable
  component files.
- Public behavior, diagnostics, serialization, and target-specific behavior
  match the C++ compiler for the covered surface.
- No module-named self-hosting TODO markers remain in that module.
- `cjpm build` succeeds for the workspace.
- Focused unit/golden tests for that module pass.
- Downstream modules that already exist still build and pass their tests.

The complete rewrite is self-hosting only when the Cangjie compiler can compile
the full self-hosted compiler, the generated compiler can compile itself again,
and the resulting behavior remains faithful to the C++ reference across the
accepted test corpus.
