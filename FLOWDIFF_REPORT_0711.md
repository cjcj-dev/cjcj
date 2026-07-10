# symdiff + flowdiff 全量刷新（2026-07-11）

## 结论

在 `master 74d4fe37` / `fix/symflow` 上纯静态扫描得到：发明候选 **5772**、缺失候选 **3919**、漏分支候选 **723**。完整逐项清单见 `FLOWDIFF_DETAILS_0711.tsv`；本报告按包、严重度汇总并列出优先审计项。

扫描器是 bare-name 启发式审计器：重载聚合、仓颉惯用 API、平台/FFI 范围都会产生误报；这里的 P0–P3 是派 lane 优先级，不是已证实缺陷。发明项按定义不存在 C++ 对应，故 TSV 的 `cpp_anchor` 明确写为 `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN`，并提供可复核的 selfhost 锚；缺失与 flow 项均提供 C++ `file:line`。

## 扫描命令与原始输出

```text
python3 /root/cj_build/audit_persist/symdiff.py /root/cj_build/wt/fix_symflow/packages
C++ symbols: 10511  selfhost symbols: 13973  shared-by-name: 6592
MISSING (C++ only): 3919   INVENTED-candidates (selfhost only): 7381 (hard: 5772)
wrote /tmp/audit/symdiff.json
missing by C++ top dir: {'Sema': 1651, 'CHIR': 838, 'CodeGen': 453, 'Modules': 202, 'Parse': 144, 'Macro': 130, 'AST': 129, 'Utils': 77, 'Basic': 52, 'IncrementalCompilation': 47, 'Frontend': 40, 'Option': 36}

/root/cj_build/tsenv/bin/python /root/cj_build/audit_persist/flowdiff.py /root/cj_build/wt/fix_symflow/packages
/root/cj_build/audit_persist/flowdiff.py:24: DeprecationWarning: int argument support is deprecated
  CJ = Language(lib.tree_sitter_cangjie()); CPP = Language(tree_sitter_cpp.language())
cpp files=723 fns=10244
cj files=570 fns=13973
shared fns: 6530  flow-deficit candidates: 723
wrote /tmp/audit/FLOWDIFF_REPORT.md
 188 PrintNode                                cppbr= 11 cjbr=  5 misscall=91
 162 BuildSymbolTable                         cppbr=101 cjbr= 27 misscall=33
 105 Synthesize                               cppbr= 75 cjbr= 55 misscall=43
  80 ChkCallExpr                              cppbr= 23 cjbr=  1 misscall=29
  64 TraverseAndLink                          cppbr= 35 cjbr=  2 misscall=12
  62 CreateDIType                             cppbr= 34 cjbr=  0 misscall=14
  57 GenTypeInfo                              cppbr=  7 cjbr=  4 misscall=27
  55 HandleTerminatorExpression               cppbr= 17 cjbr= 19 misscall=28
  52 CreateGenericOverrideMethodInAutoEnvImplDef cppbr=  6 cjbr=  1 misscall=22
  50 GetReturnValue                           cppbr=  9 cjbr=  1 misscall=21
  49 HandleStoreExpr                          cppbr= 10 cjbr=  3 misscall=21
  47 ChkRefExpr                               cppbr= 18 cjbr=  6 misscall=17
  47 HandleStoreElementRef                    cppbr= 11 cjbr=  8 misscall=22
  44 LoadCachedTypeForPackage                 cppbr= 13 cjbr=  4 misscall=18
  44 DesugarCallExpr                          cppbr= 10 cjbr=  2 misscall=18
```

系统 `python3` 首次启动 flowdiff 时缺 `tree_sitter`；随后改用脚本既有 venv。未安装或编译依赖。`cjcj`/`mangle` 前缀未导致解析失效，审计脚本零修改。

## 与旧 FLOWDIFF_REPORT.md 的差分

旧 **745**，新 **723**：已消除 **72**，新增 **50**，存量 **673**。

- 已消除：`AST2CHIRCheck`、`AddZeroInitForStructWithRefField`、`AnalysisDependency`、`CallArrayInit`、`CheckAnnotation`、`CheckAttrTokens`、`CheckAttributesForPropAndFuncDeclInClass`、`CheckExtendDecl`、`CheckInheritanceAttributes`、`CheckType`、`ChkVariadicCallExpr`、`CloneExpr`、`CollectMethods`、`CreateChildMacroCall`、`CreateDILoc`、`CreateFuncType`、`CreateOuterTypeInfo`、`CreateRefType`、`GenerateApply`、`GenerateInstantiatedClassType`、`GenerateTypeMappingByInference`、`GenericMemberAccessInstantiate`、`GenericRefExprInstantiate`、`GetAllGenericTys`、`GetChildMessagesFromMacroContext`、`GetDerefedValue`、`GetGeneralDecl`、`GetMethodType`、`GetName`、`GetOrInsertGlobalVariable`、`GetSelectorType`、`GetSingleParamFunc`、`GetSuffix`、`GetThisType`、`GetVirtualMethodOffset`、`HandleBranchTerminator`、`HasSuperTy`、`HashDeclBody`、`IsBuiltinUnaryExpr`、`IsCurFile`、`IsSubtype`、`IsValidFormat`、`LineToString`、`ManglePrefix`、`MapPos`、`MoveTo`、`NeedCheck`、`NeedOuterTypeInfo`、`NeedVarLiteralInitFunc`、`ParseTopLevel`、`ParseTopLevelDecls`、`ProcessDigits`、`ProcessNumberFloatSuffix`、`ReadUTF8Char`、`RecordUsedExtendDecl`、`RecursionEntity`、`RefreshNewTokensPos`、`ScanBase`、`ScanMultiLineComment`、`ScanMultiLineString`、`ScanNumber`、`ScanStringOrJString`、`ScanUnicodeIdentifierStart`、`SerializeFile`、`SerializeVarDecl`、`SetFuncDeclConstructorCall`、`SortGlobalVarDep`、`SpanningDefaultParamFuncDeclTree`、`SynLamExpr`、`TranslateExprArg`、`TrimPackagePath`、`VirtualHash`

- 新增：`AddMemberFunctionGenericInstantiations`、`AddMemberMethodToCustomTypeDef`、`CallArrayIntrinsicInitWithContent`、`CallAtomicIntrinsics`、`CallAtomicPrimitiveIntrinsics`、`CallIntrinsicFunction`、`CallMathIntrinsics`、`CheckBox`、`CheckFunc`、`CheckGetRTTI`、`CheckGetRTTIStatic`、`CheckInstanceOf`、`CheckUnBox`、`ClearOrCreateVarInitFunc`、`CloneEnumDecl`、`CloneExtendDecl`、`CloneFuncBody`、`CloneFuncDecl`、`CloneImportSpec`、`CountBlockSize`、`CreateCopyTo`、`CreateDIType`、`CreateRefStore`、`CreateTupleType`、`GenTypeTemplate`、`GenerateConstExpr`、`GetFieldOfType`、`GetInstParentCustomTyOfCallee`、`GetOuterType`、`GetTypeQualifiedNameForReflect`、`ImplementConsumeStrategy`、`InitArrayData`、`IsConsideredInBodyHash`、`IsConsideredInSignatureHash`、`IsTyAccessible`、`IsTypeAccessible`、`ModifyTypeMismatchInExpr`、`NeedCreateDebugForFirstParam`、`RecordEffectMap`、`RecoverCallArgs`、`RemoveInitializerForVarDecl`、`RewriteTerminator`、`RewriteToConstExpr`、`RunFunctionInline`、`SetSubprogram`、`TranslateVarInit`、`TrySimplifyingBinaryExpr`、`UnreachableBlockElimination`、`VisitFunc`、`VisitSubValue`

- 存量：完整 673 项见 TSV 中 `category=flow,status=retained`；避免在 Markdown 重复机器明细。

旧报告只保存了 flow 标题和指纹，没有保存旧 symdiff JSON，因此发明/缺失无法做可靠逐项历史差分；本轮不以不完整的 `SYMDIFF_BUCKETS.md` 猜测集合。

## 按包 × 严重度

| 类别 | 包 | P0 | P1 | P2 | P3 | 合计 |
|---|---:|---:|---:|---:|---:|---:|
| invented | `ast` | 0 | 395 | 0 | 0 | 395 |
| invented | `basic` | 0 | 0 | 176 | 0 | 176 |
| invented | `chir` | 2 | 1347 | 0 | 0 | 1349 |
| invented | `codegen` | 0 | 538 | 0 | 0 | 538 |
| invented | `compiler_unittest` | 0 | 0 | 7 | 0 | 7 |
| invented | `conditional_compilation` | 0 | 0 | 11 | 0 | 11 |
| invented | `driver` | 0 | 0 | 157 | 0 | 157 |
| invented | `frontend` | 0 | 0 | 412 | 0 | 412 |
| invented | `frontend_tool` | 0 | 0 | 55 | 0 | 55 |
| invented | `incremental_compilation` | 0 | 0 | 128 | 0 | 128 |
| invented | `lex` | 0 | 0 | 37 | 0 | 37 |
| invented | `macro` | 0 | 0 | 296 | 0 | 296 |
| invented | `mangle` | 0 | 192 | 0 | 0 | 192 |
| invented | `meta_transformation` | 0 | 0 | 15 | 0 | 15 |
| invented | `modules` | 0 | 122 | 0 | 0 | 122 |
| invented | `option` | 0 | 0 | 115 | 0 | 115 |
| invented | `parse` | 0 | 148 | 0 | 0 | 148 |
| invented | `sema` | 0 | 1495 | 0 | 0 | 1495 |
| invented | `utils` | 0 | 0 | 124 | 0 | 124 |
| missing | `ast` | 0 | 0 | 139 | 0 | 139 |
| missing | `basic` | 0 | 0 | 0 | 53 | 53 |
| missing | `chir` | 0 | 847 | 0 | 0 | 847 |
| missing | `codegen` | 0 | 454 | 0 | 0 | 454 |
| missing | `conditional_compilation` | 0 | 0 | 0 | 4 | 4 |
| missing | `driver` | 0 | 0 | 0 | 38 | 38 |
| missing | `frontend` | 0 | 0 | 0 | 41 | 41 |
| missing | `frontend_tool` | 0 | 0 | 0 | 17 | 17 |
| missing | `incremental_compilation` | 0 | 0 | 45 | 0 | 45 |
| missing | `lex` | 0 | 0 | 0 | 18 | 18 |
| missing | `macro` | 0 | 0 | 128 | 0 | 128 |
| missing | `mangle` | 0 | 0 | 29 | 0 | 29 |
| missing | `modules` | 0 | 201 | 0 | 0 | 201 |
| missing | `option` | 0 | 0 | 0 | 36 | 36 |
| missing | `parse` | 0 | 0 | 137 | 5 | 142 |
| missing | `root` | 0 | 0 | 0 | 12 | 12 |
| missing | `sema` | 0 | 735 | 0 | 909 | 1644 |
| missing | `utils` | 0 | 0 | 0 | 71 | 71 |
| flow | `ast` | 1 | 2 | 7 | 17 | 27 |
| flow | `basic` | 0 | 0 | 0 | 4 | 4 |
| flow | `chir` | 9 | 34 | 55 | 106 | 204 |
| flow | `codegen` | 4 | 11 | 28 | 33 | 76 |
| flow | `conditional_compilation` | 0 | 0 | 0 | 1 | 1 |
| flow | `driver` | 1 | 2 | 2 | 11 | 16 |
| flow | `frontend` | 0 | 3 | 4 | 21 | 28 |
| flow | `frontend_tool` | 0 | 2 | 0 | 2 | 4 |
| flow | `incremental_compilation` | 0 | 3 | 5 | 12 | 20 |
| flow | `lex` | 0 | 0 | 1 | 4 | 5 |
| flow | `macro` | 0 | 7 | 8 | 19 | 34 |
| flow | `mangle` | 0 | 0 | 6 | 12 | 18 |
| flow | `modules` | 1 | 2 | 1 | 5 | 9 |
| flow | `option` | 0 | 0 | 0 | 3 | 3 |
| flow | `parse` | 0 | 26 | 27 | 37 | 90 |
| flow | `sema` | 5 | 23 | 49 | 104 | 181 |
| flow | `utils` | 0 | 1 | 1 | 1 | 3 |

严重度规则：flow 按 score（P0≥40、P1≥20、P2≥10、其余 P3）；missing 的核心 CHIR/Sema/CodeGen/Modules 为 P1，AST/Parse/Macro/Incremental/Mangle 为 P2，NativeFFI/Test/工具范围为 P3；invented 的禁用自创前缀为 P0，核心包为 P1，其余 P2。

## TOP-20 可直接开 lane 的根

1. **PrintNode**（ast，P0，score=188）— C++ br/lp/ret=11/0/4，selfhost=5/0/2；缺调用示例：`PrintArrayExpr`、`PrintArrayLit`、`PrintAsExpr`。C++ `AST/PrintNode.cpp:1492;AST/PrintNode.cpp:1503;AST/PrintNode.cpp:1625`；CJ `ast/src/PrintNode.cj:6;frontend/src/PrintSymbolTable.cj:95`。同名多定义时锚以分号列出，指纹是 bare-name 聚合值。
2. **BuildSymbolTable**（sema，P0，score=162）— C++ br/lp/ret=101/24/2，selfhost=27/2/9；缺调用示例：`BuildSymbolTable`、`CalcScopeGateName`、`CollectAnnotations`。C++ `Sema/Collector.cpp:646;Sema/Collector.h:39`；CJ `sema/src/Collector.cj:24`。同名多定义时锚以分号列出，指纹是 bare-name 聚合值。
3. **Synthesize**（sema，P0，score=105）— C++ br/lp/ret=75/0/2，selfhost=55/1/38；缺调用示例：`CheckAnnotations`、`CheckClassDecl`、`CheckEnumDecl`。C++ `Sema/TypeChecker.cpp:1386;Sema/TypeChecker.cpp:1418;Sema/TypeChecker.cpp:1471`；CJ `sema/src/TypeCheckExpr/TypeChecker.cj:5290;sema/src/TypeCheckExpr/TypeChecker.cj:5294`。同名多定义时锚以分号列出，指纹是 bare-name 聚合值。
4. **ChkCallExpr**（sema，P0，score=80）— C++ br/lp/ret=23/1/17，selfhost=1/1/3；缺调用示例：`CheckCallKind`、`CheckNonNormalCall`、`CheckToTokensImpCallExpr`。C++ `Sema/ConstEvaluationChecker.cpp:537;Sema/ConstEvaluationChecker.cpp:670;Sema/TypeCheckCall.cpp:3148`；CJ `sema/src/ConstEvaluationChecker.cj:696;sema/src/TypeCheckCall.cj:4304`。同名多定义时锚以分号列出，指纹是 bare-name 聚合值。
5. **TraverseAndLink**（chir，P0，score=64）— C++ br/lp/ret=35/8/0，selfhost=2/1/0；缺调用示例：`AddMangledName`、`AddPosition`、`AddToMName2FuncBodyIdxPlaceHolder`。C++ `CHIR/Interpreter/BCHIRLinker.cpp:336`；CJ `chir/src/BCHIRLinker.cj:195`。同名多定义时锚以分号列出，指纹是 bare-name 聚合值。
6. **CreateDIType**（codegen，P0，score=62）— C++ br/lp/ret=34/0/15，selfhost=0/0/0；缺调用示例：`CreateArrayType`、`CreateCPointerType`、`CreateCStringType`。C++ `CodeGen/DIBuilder.cpp:645;CodeGen/DIBuilder.h:84`；CJ `codegen/src/DIBuilder.cj:374`。同名多定义时锚以分号列出，指纹是 bare-name 聚合值。
7. **GenTypeInfo**（codegen，P0，score=57）— C++ br/lp/ret=7/1/3，selfhost=4/1/0；缺调用示例：`AddLinkageTypeMetadata`、`CHIRLinkage2LLVMLinkage`、`GenAlignOfTypeInfo`。C++ `CodeGen/Base/CGTypes/CGType.cpp:616;CodeGen/CGModule.cpp:124;CodeGen/Base/CGTypes/CGType.h:241`；CJ `codegen/src/CGModule.cj:156;codegen/src/CGType.cj:360`。同名多定义时锚以分号列出，指纹是 bare-name 聚合值。
8. **HandleTerminatorExpression**（codegen，P0，score=55）— C++ br/lp/ret=17/1/15，selfhost=19/0/22；缺调用示例：`CHIRAllocateWrapper`、`CHIRApplyWrapper`、`CHIRBinaryExprWrapper`。C++ `CodeGen/Base/ExprDispatcher/TerminatorExprDispatcher.cpp:104;CodeGen/Base/ExprDispatcher/ExprDispatcher.h:23`；CJ `codegen/src/TerminatorExprDispatcher.cj:17`。同名多定义时锚以分号列出，指纹是 bare-name 聚合值。
9. **CreateGenericOverrideMethodInAutoEnvImplDef**（chir，P0，score=52）— C++ br/lp/ret=6/4/0，selfhost=1/1/1；缺调用示例：`AppendExpression`、`CreateBlock`、`CreateBlockGroup`。C++ `CHIR/Transformation/ClosureConversion.cpp:1559`；CJ `chir/src/ClosureConversion.cj:620`。同名多定义时锚以分号列出，指纹是 bare-name 聚合值。
10. **GetReturnValue**（chir，P0，score=50）— C++ br/lp/ret=9/0/6，selfhost=1/0/4；缺调用示例：`CallIntrinsicAllocaGeneric`、`CallIntrinsicAssignGeneric`、`CreateBitCast`。C++ `CHIR/IR/Expression/Expression.cpp:2185;CHIR/IR/Value/Value.cpp:1327;CHIR/Utils/Utils.cpp:1139`；CJ `chir/src/Expression.cj:2093;chir/src/Utils.cj:257;chir/src/Value.cj:1272`。同名多定义时锚以分号列出，指纹是 bare-name 聚合值。
11. **HandleStoreExpr**（chir，P0，score=49）— C++ br/lp/ret=10/0/4，selfhost=3/0/0；缺调用示例：`CGValue`、`CHIRExprWrapper`、`CreateStore`。C++ `CHIR/Analysis/MaybeInitAnalysis.cpp:106;CHIR/Analysis/MaybeInitAnalysis.cpp:82;CHIR/Analysis/MaybeUninitAnalysis.cpp:134`；CJ `chir/src/MaybeInitAnalysis.cj:116;chir/src/MaybeUninitAnalysis.cj:181;chir/src/ReachingDefinitionAnalysis.cj:317`。同名多定义时锚以分号列出，指纹是 bare-name 聚合值。
12. **ChkRefExpr**（sema，P0，score=47）— C++ br/lp/ret=18/1/9，selfhost=6/0/6；缺调用示例：`CheckNonFunctionReference`、`CollectValidFuncTys`、`DiagExpectConstExpr`。C++ `Sema/ConstEvaluationChecker.cpp:635;Sema/TypeCheckExpr/NameReferenceExpr.cpp:332;Sema/TypeCheckerImpl.h:1229`；CJ `sema/src/ConstEvaluationChecker.cj:671`。同名多定义时锚以分号列出，指纹是 bare-name 聚合值。
13. **HandleStoreElementRef**（chir，P0，score=47）— C++ br/lp/ret=11/0/4，selfhost=8/0/4；缺调用示例：`CHIRExprWrapper`、`CallClassIntrinsicAlloc`、`CallGCWriteAgg`。C++ `CHIR/Analysis/ConstMemberVarCollector.cpp:96;CodeGen/Base/ExprDispatcher/MemoryExprDispatcher.cpp:232`；CJ `chir/src/ConstMemberVarCollector.cj:83`。同名多定义时锚以分号列出，指纹是 bare-name 聚合值。
14. **CreateParameter**（chir，P0，score=44）— C++ br/lp/ret=8/0/3，selfhost=0/0/2；缺调用示例：`CreatePointerType`、`DeRef`、`GenerateLocalId`。C++ `CHIR/IR/CHIRBuilder.cpp:101;CHIR/IR/CHIRBuilder.cpp:91;CodeGen/DIBuilder.cpp:379`；CJ `chir/src/CHIRBuilder.cj:119;chir/src/CHIRBuilder.cj:127`。同名多定义时锚以分号列出，指纹是 bare-name 聚合值。
15. **DesugarCallExpr**（sema，P0，score=44）— C++ br/lp/ret=10/0/9，selfhost=2/0/1；缺调用示例：`Clone`、`CreateGetSuperClassExpr`、`CreateMethodCallViaMsgSendSuper`。C++ `Sema/Desugar/DesugarInTypeCheck.cpp:485;Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/DesugarImpls.cpp:224;Sema/Desugar/DesugarInTypeCheck.h:27`；CJ `sema/src/Desugar/DesugarInTypeCheck.cj:580`。同名多定义时锚以分号列出，指纹是 bare-name 聚合值。
16. **LoadCachedTypeForPackage**（modules，P0，score=44）— C++ br/lp/ret=13/1/4，selfhost=4/2/4；缺调用示例：`ClearInstantiatedCache`、`CollectRemovedDecls`、`CollectRemovedDefaultImpl`。C++ `Modules/ASTSerialization/IncrementalLoader.cpp:266;Modules/ASTSerialization/IncrementalLoader.cpp:43;Modules/ImportManager.cpp:365`；CJ `modules/src/ASTSerialization.cj:187;modules/src/ImportManager.cj:616`。同名多定义时锚以分号列出，指纹是 bare-name 聚合值。
17. **CreateInstOverrideMethodInAutoEnvImplDef**（chir，P0，score=43）— C++ br/lp/ret=6/2/1，selfhost=2/1/2；缺调用示例：`CreateBlock`、`CreateBlockGroup`、`CreateFunction`。C++ `CHIR/Transformation/ClosureConversion.cpp:1711`；CJ `chir/src/ClosureConversion.cj:643`。同名多定义时锚以分号列出，指纹是 bare-name 聚合值。
18. **HandleLiteralValue**（codegen，P0，score=43）— C++ br/lp/ret=9/0/2，selfhost=0/0/1；缺调用示例：`CreateDILoc`、`CreateNullValue`、`CreateStringLiteral`。C++ `CodeGen/Base/ExprDispatcher/ConstantExprDispatcher.cpp:17;CodeGen/Base/ExprDispatcher/ConstantExprDispatcher.cpp:20;CodeGen/Base/ExprDispatcher/ExprDispatcher.h:22`；CJ `codegen/src/ConstantExprDispatcher.cj:13`。同名多定义时锚以分号列出，指纹是 bare-name 聚合值。
19. **CreateFuncSignatureAndSetGlobalCache**（chir，P0，score=41）— C++ br/lp/ret=16/0/2，selfhost=5/0/0；缺调用示例：`CreateAnnoFactoryFuncsForFuncDecl`、`CreatePseudoImportedFuncSignatureAndSetGlobalCache`、`CreateTranslator`。C++ `CHIR/AST2CHIR/ASTPackage2CHIR.cpp:665`；CJ `chir/src/FaithfulAST2CHIR.cj:3949`。同名多定义时锚以分号列出，指纹是 bare-name 聚合值。
20. **GetVisiableGenericTypes**（chir，P0，score=41）— C++ br/lp/ret=10/1/1，selfhost=0/0/1；缺调用示例：`GetExpr`、`GetGenericTypeParams`、`GetOwnerExpression`。C++ `CHIR/Utils/Utils.cpp:1050;CHIR/Utils/Utils.cpp:1061;CHIR/Utils/Utils.cpp:1087`；CJ `chir/src/ClosureConversion.cj:1394`。同名多定义时锚以分号列出，指纹是 bare-name 聚合值。

## 发明清单（selfhost 有、C++ 无同名）

全量 5,772 项位于 TSV（先按 package，再按 severity、symbol 排序）。以下展示最高优先级前 80 项；`NO_MATCH` 本身就是全量 C++ 扫描结论。

| 严重度 | 包 | 符号 | selfhost 锚 | C++ 锚 |
|---|---|---|---|---|
| P0 | `chir` | `CustomDefKindIndex` | `chir/src/Enums.cj:283` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P0 | `chir` | `CustomTypeDefIdentifierForQualifiedName` | `chir/src/CHIRMangling.cj:162` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `ASTKindIndex` | `ast/src/ASTKind.cj:120` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `ASTKindName` | `ast/src/ASTKind.cj:366` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `AccessLevelRank` | `ast/src/Utils.cj:474` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `AddAllUnique` | `ast/src/Searcher.cj:841` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `AddDependentStdPkg` | `ast/src/ImportPackageNodes.cj:454` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `AddFileHash` | `ast/src/Query.cj:103` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `AddFileHashes` | `ast/src/Query.cj:107` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `AddMemDecl` | `ast/src/ASTContext.cj:454` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `AddUnique` | `ast/src/Searcher.cj:847` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `AddUniqueString` | `ast/src/Searcher.cj:865` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `AllLiveSymbols` | `ast/src/Searcher.cj:755` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `AnnotationKindIndex` | `ast/src/Node.cj:533` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `AnnotationTargetIndex` | `ast/src/Node.cj:590` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `AnnotationTargetMask` | `ast/src/Node.cj:605` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `Append` | `ast/src/Identifier.cj:93` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `AreTysCorrect` | `ast/src/Types.cj:882` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `As` | `ast/src/Match.cj:125` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `Assign` | `ast/src/IntLiteral.cj:205` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `AttributeBitMask` | `ast/src/AttributePack.cj:315` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `AttributeIndex` | `ast/src/AttributePack.cj:102` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `AttributeName` | `ast/src/AttributePack.cj:319` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `AttributeWordIndex` | `ast/src/AttributePack.cj:311` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `BuiltInTypeIndex` | `ast/src/DeclNodes.cj:436` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `CallKindIndex` | `ast/src/ExprNodes.cj:1090` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `CanBeSrcExported` | `ast/src/Utils.cj:644` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `Children` | `ast/src/ExprNodes.cj:1047` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `ClearAllDependentStdPkgs` | `ast/src/ImportPackageNodes.cj:458` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `CloneAttrs` | `ast/src/Node.cj:126` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `ComparePosition` | `ast/src/Query.cj:307` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `ContainsSymbol` | `ast/src/Searcher.cj:856` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `CopyAttrs` | `ast/src/Node.cj:122` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `CreateResumeExpr` | `ast/src/Create.cj:763` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `Diagnose` | `ast/src/NodeDiagnostics.cj:34` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `EnableAllTargets` | `ast/src/Node.cj:648` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `EnableTarget` | `ast/src/Node.cj:644` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `ExprKindIndex` | `ast/src/Common.cj:87` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `FilterByMatcher` | `ast/src/Searcher.cj:745` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `FilterCachedSearchResult` | `ast/src/Searcher.cj:504` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `FindPositionByUInt64Key` | `ast/src/Node.cj:42` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `GetAllDependentStdPkgs` | `ast/src/ImportPackageNodes.cj:462` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `GetAttrs` | `ast/src/Node.cj:118` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `GetMemberDecls` | `ast/src/DeclNodes.cj:570` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `HasConstOrFrozenInit` | `ast/src/DeclNodes.cj:817` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `HasFtrDirective` | `ast/src/ImportPackageNodes.cj:445` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `Identifier` | `ast/src/PatternNodes.cj:106` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `ImportKindIndex` | `ast/src/ImportPackageNodes.cj:56` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `InsertJavaSyntheticClassDecl` | `ast/src/Utils.cj:1056` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `InsertObjCSyntheticClassDecl` | `ast/src/Utils.cj:1094` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `InsideAtJavaDecl` | `ast/src/Utils.cj:628` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `InvalidateCache` | `ast/src/Searcher.cj:447` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `IsClassLikeDecl` | `ast/src/Node.cj:185` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `IsClassOrEnumConstructor` | `ast/src/Utils.cj:92` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `IsCommonWithoutDefault` | `ast/src/Utils.cj:668` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `IsDecl` | `ast/src/Node.cj:214` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `IsImportAlias` | `ast/src/ImportPackageNodes.cj:256` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `IsImportAll` | `ast/src/ImportPackageNodes.cj:254` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `IsImportMulti` | `ast/src/ImportPackageNodes.cj:257` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `IsImportSingle` | `ast/src/ImportPackageNodes.cj:255` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `IsInstanceMember` | `ast/src/Utils.cj:101` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `IsNominalDecl` | `ast/src/Node.cj:175` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `IsPrivateImport` | `ast/src/ImportPackageNodes.cj:259` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `IsReExport` | `ast/src/ImportPackageNodes.cj:244` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `IsStaticOrGlobal` | `ast/src/Node.cj:232` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `IsStaticVar` | `ast/src/Utils.cj:728` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `IsStructOrClassDecl` | `ast/src/Node.cj:171` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `IsVArrayTy` | `ast/src/ASTCasting.cj:61` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `IterateToplevelDecls` | `ast/src/Utils.cj:377` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `JoinScopeName` | `ast/src/ScopeManagerApi.cj:85` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `Length` | `ast/src/Identifier.cj:44` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `LitConstKindIndex` | `ast/src/ExprNodes.cj:856` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `LitKindToString` | `ast/src/ExprNodes.cj:916` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `MakeDeclScopeName` | `ast/src/ScopeManagerApi.cj:95` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `MapSpecificImplementation` | `ast/src/Types.cj:837` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `Match` | `ast/src/Query.cj:117` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `MatchKindIndex` | `ast/src/Query.cj:49` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `NextHashID` | `ast/src/Symbol.cj:85` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `NodeKind` | `ast/src/Match.cj:6` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |
| P1 | `ast` | `ParseQuery` | `ast/src/Query.cj:656` | `NO_MATCH_IN_FULL_CPP_SYMBOL_SCAN` |

## 缺失清单（C++ 有、selfhost 无同名）

全量 3,919 项位于 TSV（按 package × severity 排序）。以下展示最高优先级前 80 项。

| 严重度 | 包 | 符号 | C++ 锚 | selfhost |
|---|---|---|---|---|
| P1 | `chir` | `AShrInPlace` | `CHIR/Analysis/SInt.cpp:455` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `AddAnnotations` | `CHIR/Interpreter/CHIR2BCHIR.cpp:581` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `AddExpressionsToGlobalInitFunc` | `CHIR/Utils/Utils.cpp:286` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `AddImportedPackageInit` | `CHIR/AST2CHIR/GlobalVarInitializer.cpp:598` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `AddMangledName` | `CHIR/Interpreter/BCHIRLinker.cpp:327` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `AddMemberPropDecl` | `CHIR/AST2CHIR/TranslateASTNode/TranslateClassDecl.cpp:412` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `AddPosition` | `CHIR/Interpreter/BCHIRLinker.cpp:316` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `AddToImplicitFuncs` | `CHIR/AST2CHIR/ASTPackage2CHIR.cpp:99` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `AddToMName2FuncBodyIdxPlaceHolder` | `CHIR/Interpreter/BCHIRLinker.cpp:564` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `AllUsersIsExprKind` | `CHIR/Optimization/DeadCodeElimination.cpp:50` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `AllocateValue` | `CHIR/Interpreter/BCHIRInterpreter.cpp:1653` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `AnnoInfo` | `CHIR/Serializer/CHIRDeserializer.cpp:221` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `AppendFrozenFuncState` | `CHIR/Optimization/Devirtualization.cpp:278` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `AppendSuccessor` | `CHIR/IR/Expression/Terminator.cpp:142` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `Ashr` | `CHIR/Analysis/SInt.cpp:480` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `AttributeInfo` | `CHIR/Serializer/CHIRDeserializer.cpp:151` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `BinExpOpInt` | `CHIR/Interpreter/BCHIRInterpreter.cpp:1125` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `BinExprKind2OpCode` | `CHIR/Interpreter/Utils.cpp:72` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `BinExprKindWitException2OpCode` | `CHIR/Interpreter/Utils.cpp:120` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `BinOp` | `CHIR/Interpreter/BCHIRInterpreter.cpp:1425` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `BinOpBool` | `CHIR/Interpreter/BCHIRInterpreter.cpp:1460` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `BinOpCompare` | `CHIR/Interpreter/BCHIRInterpreter.cpp:1497` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `BinOpFixedBool` | `CHIR/Interpreter/BCHIRInterpreter.cpp:1453` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `BinOpFloat` | `CHIR/Interpreter/BCHIRInterpreter.cpp:1316` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `BinOpInt` | `CHIR/Interpreter/BCHIRInterpreter.cpp:1119` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `BinOpRune` | `CHIR/Interpreter/BCHIRInterpreter.cpp:1482` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `BinOpTyKindAndOverflowStrat` | `CHIR/Interpreter/BCHIRInterpreter.cpp:1364` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `BinOpUnit` | `CHIR/Interpreter/BCHIRInterpreter.cpp:1529` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `BinRegOpInt` | `CHIR/Interpreter/BCHIRInterpreter.cpp:1189` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `BinShiftOpInt` | `CHIR/Interpreter/BCHIRInterpreter.cpp:1276` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `BinShiftOpIntCase` | `CHIR/Interpreter/BCHIRInterpreter.cpp:1244` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `BindingFuncParam` | `CHIR/AST2CHIR/TranslateASTNode/TranslateFuncDecl.cpp:19` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `Bool` | `CHIR/Checker/ComputeAnnotations.cpp:248` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `BoxStoreElementRefSrcValueIfNeed` | `CHIR/Transformation/BoxRecursionValueType.cpp:111` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `BoxTupleOpIfNeed` | `CHIR/Transformation/BoxRecursionValueType.cpp:156` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `BuildDeserializedTable` | `CHIR/AST2CHIR/ASTPackage2CHIR.cpp:1673` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `BuildOrphanTypeReplaceTable` | `CHIR/Optimization/Devirtualization.cpp:373` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `Builder` | `CHIR/AST2CHIR/TranslateASTNode/TranslateIfExpr.cpp:356` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `BuiltinOpCreateNewApply` | `CHIR/Optimization/Devirtualization.cpp:132` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `BuiltinOpCreateNewBinary` | `CHIR/Optimization/Devirtualization.cpp:144` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `ByteCodeToIval` | `CHIR/Interpreter/Utils.cpp:148` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CHIRDeserializerImpl` | `CHIR/Serializer/CHIRDeserializerImpl.h:58` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CHIRExprKindToExprKind` | `CHIR/Serializer/CHIRDeserializer.cpp:654` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CHIRPos2BCHIRPos` | `CHIR/Interpreter/CHIR2BCHIR.cpp:566` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CHIRSerializerImpl` | `CHIR/Serializer/CHIRSerializerImpl.h:36` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CacheSomeDeclsToGlobalSymbolTable` | `CHIR/AST2CHIR/AST2CHIR.cpp:319` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CalculateAllUpperBounds` | `CHIR/Checker/CHIRChecker.cpp:186` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CalculateCurDefInstantiatedMemberTys` | `CHIR/IR/Type/Type.cpp:457` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CalculateInstFuncType` | `CHIR/Checker/CHIRChecker.cpp:2207` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CanActualFuncBeMovedInSpecific` | `CHIR/AST2CHIR/TranslateASTNode/TranslateCallExpr.cpp:810` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CanAnalyse` | `CHIR/Analysis/ValueRangeAnalysis.cpp:120` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CanOptimizeToSwitch` | `CHIR/AST2CHIR/TranslateASTNode/TranslateIfExpr.cpp:12` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `Canonicalization` | `CHIR/CHIR.cpp:1248` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CastArrayListToArray` | `CHIR/Transformation/SanitizerCoverage.cpp:631` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CastEnumTypeToTupleWithBoxArg` | `CHIR/Transformation/BoxRecursionValueType.cpp:203` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CastOrRaiseExceptionForFloat` | `CHIR/Interpreter/BCHIRInterpreter.cpp:842` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CheckAllGenericTypeVisible` | `CHIR/Optimization/Devirtualization.cpp:636` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CheckAllocate` | `CHIR/Checker/CHIRChecker.cpp:4165` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CheckAllocateBase` | `CHIR/Checker/CHIRChecker.cpp:3233` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CheckAllocateWithException` | `CHIR/Checker/CHIRChecker.cpp:3213` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CheckApplyBase` | `CHIR/Checker/CHIRChecker.cpp:2029` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CheckApplyFuncRetValue` | `CHIR/Checker/CHIRChecker.cpp:2244` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CheckApplyWithException` | `CHIR/Checker/CHIRChecker.cpp:2009` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CheckBinaryExprBase` | `CHIR/Checker/CHIRChecker.cpp:2824` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CheckCanRewriteLambda` | `CHIR/Optimization/ArrayLambdaOpt.cpp:51` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CheckCanRewriteZeroValue` | `CHIR/Optimization/ArrayLambdaOpt.cpp:133` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CheckDebug` | `CHIR/Checker/CHIRChecker.cpp:3482` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CheckDivZero` | `CHIR/Analysis/ValueRangeAnalysis.cpp:314` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CheckField` | `CHIR/Checker/CHIRChecker.cpp:3670` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CheckFuncActiveResult` | `CHIR/Analysis/ConstAnalysisWrapper.cpp:61` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CheckFuncHasInvoke` | `CHIR/Analysis/TypeAnalysis.cpp:134` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CheckGetElementByName` | `CHIR/Checker/CHIRChecker.cpp:4284` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CheckGetElementRef` | `CHIR/Checker/CHIRChecker.cpp:4231` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CheckGetException` | `CHIR/Checker/CHIRChecker.cpp:3767` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CheckIfLambdaReturnConst` | `CHIR/Optimization/ArrayLambdaOpt.cpp:75` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CheckIntOpWithException` | `CHIR/Checker/CHIRChecker.cpp:2762` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CheckIntrinsicBase` | `CHIR/Checker/CHIRChecker.cpp:3196` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CheckIntrinsicWithException` | `CHIR/Checker/CHIRChecker.cpp:3042` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CheckInvokeBase` | `CHIR/Checker/CHIRChecker.cpp:2275` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |
| P1 | `chir` | `CheckInvokeStaticBase` | `CHIR/Checker/CHIRChecker.cpp:2713` | `NO_MATCH_IN_FULL_SELFHOST_SYMBOL_SCAN` |

## 漏分支清单（同名函数流指纹差）

全量 723 项位于 TSV，含 score、两侧 br/lp/ret、missing-calls、两侧锚及 new/retained 状态；TOP-20 已在上节单列。

## 合规与产物

- 仅运行 Python 静态扫描与文本整形；未运行 `cjpm build`，未编译任何内容。
- `packages/` 与 C++ `src/` 均零修改；扫描器零修改。
- 产物：`FLOWDIFF_REPORT_0711.md`、`FLOWDIFF_DETAILS_0711.tsv`。
