package cangjie_compiler::compiler_unittest

// PORT-DEFERRED: Basic/ErrorMessageTest.MassageTest requires C++ ParserImpl::ParseExpressionOrDeclarations recovery and ParserImpl::DiagForBlock from /root/cj_build/cangjie_compiler/src/Parse/Parser.cpp:581 and /root/cj_build/cangjie_compiler/src/Parse/Parser.cpp:630; the selfhost parser recovery/diagnostic block facility is not ported, and packages/parse/src is out of this task scope.
// PORT-DEFERRED: Basic/EngineTest.apiTest requires C++ DiagnosticEmitterImpl collected multi-line source layout from /root/cj_build/cangjie_compiler/src/Basic/DiagnosticEmitter.cpp:384, :591, and :846 plus CollectedInfo from /root/cj_build/cangjie_compiler/src/Basic/DiagnosticEmitterImpl.h:35; selfhost DiagnosticEmitter lacks that faithful combined-source emitter.
// PORT-DEFERRED: Basic/EngineTest.apiTest2 requires C++ DiagnosticEmitterImpl collected same-line hint layout from /root/cj_build/cangjie_compiler/src/Basic/DiagnosticEmitter.cpp:384, :591, and :846 plus CollectedInfo from /root/cj_build/cangjie_compiler/src/Basic/DiagnosticEmitterImpl.h:35; selfhost DiagnosticEmitter lacks that faithful combined-source emitter.
// PORT-DEFERRED: Basic/EngineTest.apiTest4 requires C++ DiagnosticEngine AST::Node overloads from /root/cj_build/cangjie_compiler/include/cangjie/Basic/DiagnosticEngine.h:850, :866, :939, :951, :965, and :978; package basic has no selfhost AST::Node diagnostic overload surface without depending on ast.
// PORT-DEFERRED: Basic/EngineTest.ShowColorTest Windows branch requires C++ Utils::GetOSVersion from /root/cj_build/cangjie_compiler/src/Basic/Utils.cpp:137 and /root/cj_build/cangjie_compiler/include/cangjie/Basic/Utils.h:52; package basic cannot depend on selfhost package utils without a dependency cycle.
// PORT-DEFERRED: Utils/CastASTTests.VerifyCastingCount, VerifyMonoCasting, VerifyIntermediateCasting, TryAddNewType, and VerifyStaticCasting require C++ ASTCasting template/RTTI facilities from /root/cj_build/cangjie_compiler/include/cangjie/AST/ASTCasting.h:24 and :57; package utils cannot depend on downstream package ast to construct the tested AST nodes.
// PORT-DEFERRED: Utils/CastTyTests.VerifyCastingCount, VerifyMonoCasting, and VerifyIntermediateCasting require C++ AST Ty casting template facilities from /root/cj_build/cangjie_compiler/include/cangjie/AST/ASTCasting.h:31 and :65; package utils cannot depend on downstream package ast/sema type owners.
// PORT-DEFERRED: Utils/SignalTests main/parser signal and stack-overflow cases require C++ ExecuteProcess fork/exec and CreateProcessA harnesses from /root/cj_build/cangjie_compiler/unittests/Utils/SignalTests.cpp:154 and :189 plus callback wiring in /root/cj_build/cangjie_compiler/unittests/Utils/SignalTestCJC.cpp:82; selfhost std.unittest cannot faithfully run crashing compiler subprocess signal scenarios.
// PORT-DEFERRED: Utils/UtilsTest.RemoveDirectoryWithSymlinkChild and RemoveDirectoryTargetIsSymlink require C++ CreateSymlinkCrossPlatform from /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:71; no selfhost utility API exposes symlink creation for the faithful setup.
// PORT-DEFERRED: Utils/UtilsTest.ReadBinaryFileToBuffer sparse 4GB+ branch requires C++ std::ofstream seekp/write setup from /root/cj_build/cangjie_compiler/unittests/Utils/UtilsTests.cpp:670 and :673; no selfhost file API in package utils exposes sparse seek/write construction.
// PORT-DEFERRED: Utils/UtilsTest.SipHash std::bitset assertions require C++ SipHash::GetHashValue(const std::bitset<N>&) from /root/cj_build/cangjie_compiler/include/cangjie/Utils/SipHash.h:18; no selfhost SipHash bitset overload exists.
// PORT-DEFERRED: Utils/UnicodeTest.GeneratedNFCTests requires C++ NORMALISATION_TEST_DATA from /root/cj_build/cangjie_compiler/src/Utils/UnicodeTables/NormalisationTestData.generated.inc:22; that generated fixture is not present as selfhost Cangjie test data.

// PORT-DEFERRED: Sema/TypeCheckerTest.DISABLED_TypecheckTest requires the old C++ TestCompilerInstance fixture.
// PORT-DEFERRED: Sema/TypeCheckerTest.DISABLED_MacroDeclTest requires macro fixture setup not exposed by the selfhost harness.
// PORT-DEFERRED: Sema/TypeCheckerTest.DISABLED_MacroCallInLSPTest requires LSP macro-call fixture state not exposed by the selfhost harness.
// PORT-DEFERRED: Sema/TypeCheckerTest.DISABLED_MacroDiagInLSPTest requires LSP macro diagnostic fixture state not exposed by the selfhost harness.
// PORT-DEFERRED: Sema/TypeCheckerTest.DISABLED_NoDiagInLSPMacroCallTest requires LSP macro diagnostic fixture state not exposed by the selfhost harness.
// PORT-DEFERRED: Sema/TypeCheckerTest.DISABLED_NoDiagInLSPMacroCallForTest requires LSP macro diagnostic fixture state not exposed by the selfhost harness.
// PORT-DEFERRED: Sema/TypeCheckerTest.DISABLED_MacroCallOfTopLevelInLSPTest requires LSP macro-call fixture state not exposed by the selfhost harness.
// PORT-DEFERRED: Sema/TypeCheckerTest.DISABLED_AssumptionTest depends on old fixture-only assumption APIs.
// PORT-DEFERRED: Sema/TypeCheckerTest.DISABLED_SpawnTest depends on old fixture setup and disabled C++ coverage.
// PORT-DEFERRED: Sema/TypeCheckerTest.DiagnosticNodeTest requires direct C++ diagnostic node fixture access not exposed by the selfhost harness.
// PORT-DEFERRED: Sema/CommentsTest.DISABLED_MacroDesugarFuncCommentsTest depends on disabled C++ macro desugar fixtures.
// PORT-DEFERRED: Sema/CommentsTest.DISABLED_MainDesugarFuncCommentsTest depends on disabled C++ desugar fixture internals.
// PORT-DEFERRED: Sema/CommentsTest.DISABLED_CustomAnnotionCommentsTest depends on disabled C++ custom annotation fixtures.
// PORT-DEFERRED: Sema/CommentsTest.DISABLED_MacroCommentsTest depends on disabled C++ macro comment fixtures.

// PORT-DEFERRED: Frontend/CompilerInstanceTest.DISABLED_FullCompile requires the old C++ full-compile fixture; current harness covers string compilation through selected stages.
// PORT-DEFERRED: Frontend/CompilerInstanceTest.DISABLED_GetAllVisibleExtendMembers01 requires direct CompilerInstance fixture internals not exposed by the selfhost harness.
// PORT-DEFERRED: Frontend/CompilerInstanceTest.Comments requires C++ fixture comment source setup not exposed as a selfhost helper.
// PORT-DEFERRED: Frontend/CompilerInstanceTest.DISABLED_TrailingClosure requires disabled C++ fixture setup not exposed by the selfhost harness.

// PORT-DEFERRED: IncrCompile/IncrementalCompilationLoggerTest.InvidPath expects writable ".log" to leave logging disabled; current selfhost logger enables writable .log paths.

// PORT-DEFERRED: Modules/PackageTest.SingleFile_Package requires old package-cache fixture directories and direct module manager setup.
// PORT-DEFERRED: Modules/PackageTest.SingleFile_LoadCache_Package requires old package-cache fixture directories and direct module manager setup.
// PORT-DEFERRED: Modules/PackageTest.MultiFile_Package requires old multi-file fixture directories and direct module manager setup.
// PORT-DEFERRED: Modules/PackageTest.ImportPackage requires old import fixture directories and serialized package artifacts.
// PORT-DEFERRED: Modules/PackageTest.LSPBasicCompileCost requires LSP performance fixture plumbing.
// PORT-DEFERRED: Modules/PackageTest.DISABLED_LSPImportLotPkgsCompileCost is disabled C++ performance coverage.
// PORT-DEFERRED: Modules/PackageTest.LSPCompileComposition requires LSP package composition fixtures.
// PORT-DEFERRED: Modules/PackageTest.LSPCompileWithConstraint requires LSP package composition fixtures.
// PORT-DEFERRED: Modules/PackageTest.LSPImportFunctionWithNamedParam requires LSP import fixtures.
// PORT-DEFERRED: Modules/PackageTest.ExportVisibleMembersForLSP requires LSP export fixture internals.
// PORT-DEFERRED: Modules/PackageTest.ConstNotExportInitializerForLSP requires LSP export fixture internals.
// PORT-DEFERRED: Modules/PackageTest.ForbiddenRunInstantiation requires direct module manager fixture setup.
// PORT-DEFERRED: Modules/PackageTest.LoadBuiltInDecl requires direct builtin loader fixture setup.
// PORT-DEFERRED: Modules/PackageTest.MangleEnumExportId requires serialized CJO fixture artifacts.
// PORT-DEFERRED: Modules/PackageTest.LSPExportInterfaceFuncFromMacro requires macro-generated LSP export fixtures.
// PORT-DEFERRED: Modules/PackageTest.ImportManager_API requires direct ImportManager internals not exposed through the harness.
// PORT-DEFERRED: Modules/PackageTest.LSPExportInvalidVpd requires LSP export fixture internals.
// PORT-DEFERRED: Modules/PackageTest.LSPExportInvisibleMembers requires LSP export fixture internals.
// PORT-DEFERRED: Modules/PackageTest.CheckCjoPathLegality requires direct module path legality fixture setup.
// PORT-DEFERRED: Modules/PackageTest.CollectStdDependency_PackageSearchError requires direct package search error fixture setup.
// PORT-DEFERRED: Modules/PackageTest.SemanticUsage requires serialized semantic usage fixture artifacts.
// PORT-DEFERRED: Modules/PackageTest.IncrementalMergedSemanticUsage requires incremental serialized semantic usage fixtures.
// PORT-DEFERRED: Modules/PackageTest.UsageOfTypeAlias requires serialized package fixture artifacts.
// PORT-DEFERRED: Modules/PackageTest.UsageOfOnTheLeftOfPipeline requires serialized package fixture artifacts.
// PORT-DEFERRED: Modules/PackageTest.LoadAnnotationTarget requires serialized package fixture artifacts.
// PORT-DEFERRED: Modules/PackageTest.LoadPackageFromCjo requires generated CJO fixture artifacts.
// PORT-DEFERRED: Modules/PackageTest.ImportOptFlag requires generated CJO fixture artifacts with optimization flags.
// PORT-DEFERRED: Modules/PackageTest.TypeAliasRefExport requires serialized package fixture artifacts.
// PORT-DEFERRED: Modules/ImportIncrTest.ImportIncrTest requires old incremental import fixture directories and artifacts.

// PORT-DEFERRED: Macro/NodeSerializationTest.BinaryExpr_Serialization requires direct macro node construction fixtures.
// PORT-DEFERRED: Macro/NodeSerializationTest.UnaryExpr_Serialization requires direct macro node construction fixtures.
// PORT-DEFERRED: Macro/NodeSerializationTest.VarDecl_Serialization requires direct macro node construction fixtures.
// PORT-DEFERRED: Macro/NodeSerializationTest.FuncDecl_Serialization requires direct macro node construction fixtures.
// PORT-DEFERRED: Macro/NodeSerializationTest.ClassDecl_Serialization requires direct macro node construction fixtures.
// PORT-DEFERRED: Macro/NodeSerializationTest.InterfaceDecl_Serialization requires direct macro node construction fixtures.
// PORT-DEFERRED: Macro/NodeSerializationTest.IfExpr_Serialization requires direct macro node construction fixtures.
// PORT-DEFERRED: Macro/NodeSerializationTest.LambdaExpr_Serialization requires direct macro node construction fixtures.
// PORT-DEFERRED: Macro/MacroTest.MacroProcess_Curfile requires macro evaluation server fixture setup.
// PORT-DEFERRED: Macro/MacroTest.MacroCall_GetNewPos requires LSP macro-call state not exposed through the harness.
// PORT-DEFERRED: Macro/MacroTest.MacroCall_GetEndPos requires LSP macro-call state not exposed through the harness.
// PORT-DEFERRED: Macro/MacroTest.MacroCall_Complementatcion_For_LSP requires LSP macro-call state not exposed through the harness.
// PORT-DEFERRED: Macro/MacroTest.MacroCall_Check_For_LSP requires LSP macro-call state not exposed through the harness.
// PORT-DEFERRED: Macro/MacroTest.MacroCall_Check_For_LSP_Paralle requires parallel LSP macro-call state not exposed through the harness.
// PORT-DEFERRED: Macro/MacroTest.IfAvailable_In_LSP requires LSP macro fixture state.
// PORT-DEFERRED: Macro/MacroTest.MacroCall_Check_For_LSP_context requires LSP macro-call context state.
// PORT-DEFERRED: Macro/MacroTest.MacroDiagReportForLsp requires LSP macro diagnostic fixture state.
// PORT-DEFERRED: Macro/MacroTest.NoErrorInLSPMacro requires LSP macro diagnostic fixture state.
// PORT-DEFERRED: Macro/MacroTest.NoErrorInDeriveEnum requires derive macro fixture setup.
// PORT-DEFERRED: Macro/MacroTest.MacroCall_HighLight_LSP requires LSP macro highlight fixture state.
// PORT-DEFERRED: Macro/MacroTest.ExpandDecl_WithMacroCall_ExpandsSuccessfully01 requires old macro expansion fixtures.
// PORT-DEFERRED: Macro/MacroTest.ExpandDecl_WithMacroCall_ExpandsSuccessfully02 requires old macro expansion fixtures.
// PORT-DEFERRED: Macro/MacroTest.ExpandDecl_WithMacroCall_ExpandsSuccessfully03 requires old macro expansion fixtures.
// PORT-DEFERRED: Macro/MacroTest.ExpandDecl_WithMacroCall_ExpandsSuccessfully04 requires old macro expansion fixtures.
// PORT-DEFERRED: Macro/MacroTest.ExpandDecl_WithMacroCall_ExpandsSuccessfully05 requires old macro expansion fixtures.
// PORT-DEFERRED: Macro/MacroTest.ExpandDecl_WithMacroCall_ExpandsSuccessfully06 requires old macro expansion fixtures.
// PORT-DEFERRED: Macro/MacroTest.ExpandDecl_WithMacroCall_ExpandsSuccessfully07 requires old macro expansion fixtures.
// PORT-DEFERRED: Macro/MacroTest.ExpandDecl_WithMacroCall_ExpandsSuccessfully08 requires old macro expansion fixtures.
// PORT-DEFERRED: Macro/MacroTest.ExpandDecl_WithMacroCall_ExpandsSuccessfully09 requires old macro expansion fixtures.
// PORT-DEFERRED: Macro/MacroTest.ExpandDecl_WithMacroCall_ExpandsSuccessfully10 requires old macro expansion fixtures.
// PORT-DEFERRED: Macro/MacroTest.ExpandDecl_WithMacroCall_ExpandsSuccessfully11 requires old macro expansion fixtures.
// PORT-DEFERRED: Macro/MacroTest.ExpandDecl_WithMacroCall_ExpandsSuccessfully12 requires old macro expansion fixtures.
// PORT-DEFERRED: Macro/MacroTest.ExpandDecl_WithVarMacroCall_ExpandsSuccessfully requires old macro expansion fixtures.
// PORT-DEFERRED: Macro/MacroTest.ExpandDecl_WithNoMacroCall_ReturnsSameDecl requires direct macro expansion API fixture setup.
// PORT-DEFERRED: Macro/MacroTest.ExpandDecl_WithNullDecl_ReturnsEmpty requires direct macro expansion API fixture setup.
// PORT-DEFERRED: Macro/MacroTest.ExpandDecl_WithMemberDecl_ReturnsEmpty requires direct macro expansion API fixture setup.
// PORT-DEFERRED: Macro/MacroTest.ExpandDecl_WithFailedMacroCall_HandlesError01 requires old macro expansion error fixtures.
// PORT-DEFERRED: Macro/MacroTest.ExpandDecl_WithFailedMacroCall_HandlesError02 requires old macro expansion error fixtures.
// PORT-DEFERRED: Macro/MacroTest.ExpandDecl_WithFailedMacroCall_HandlesError03 requires old macro expansion error fixtures.
