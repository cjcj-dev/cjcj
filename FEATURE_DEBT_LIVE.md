# FEATURE_DEBT — LIVE only

净化日期：2026-07-11

基线：`master@74d4fe37507022550934ab515bd0b50c5e99bdf4`

状态依据：`FOUNDDEBT_AUDIT.md`。本文件只保留可派 LIVE 债，不保留历史门数、在飞状态、已清依赖层或审稿事故。

lane 规模：S = 单点/单文件；M = 一簇 named API 或多调用点；L = 子系统级；XL = 跨 pass/平台的大型设计与分批移植。

| ID | LIVE 债 | 当前 grep 证据 | 影响面 / 挡住战役线 | 建议 lane | C++ 锚 |
|---|---|---|---|---|---|
| L01 | JoinAndMeet 错误载荷与调用契约 | `JoinAndMeet.cj` 只有返回 `Ty` 的自由函数；无 `ErrOrTy/CombineErrMsg/SetJoinedType/SetMetType/AddFinalErrMsgs` | sema 分支类型、返回类型、局部类型推断；挡 validation/诊断严格性 | M | `Sema/JoinAndMeet.h:31-89`; `JoinAndMeet.cpp:89-118,258-287,334-343,390-430` |
| L02 | modules cjo loader 仍文本刮取 | `ASTSerialization.cj:174-180` 把 bytes 转 UTF-8；`:316-340` 按 `SplitRawLines`/字段解析；`CjoManagerImpl.cj:280-333` 仍创建它 | ImportManager/CjoManager、common/specific、跨包与宏包；挡 cjo/importmgr | L | `Modules/ASTSerialization/ASTLoader.cpp`; `ASTLoaderImpl.h` FlatBuffer load 族 |
| L03 | `-g` 完整 DI lowering | `DIBuilder.cj:135,378` 两处 BLOCKED throw；`CGCustomType.cj:145` anonymous generic type GAP | 完整调试类型、member scope、参数 debug-load；挡 debug 战役 | XL | `CodeGen/DIBuilder.cpp:223-334,645+`; `EmitExpressionIR.cpp:64-66` |
| L04 | `--coverage` 完整路径 | coverage option 存在但依赖 L03；DIBuilder full path 仍缺 | coverage instrumentation、debug metadata、优化保留规则 | L（接 L03 后） | `DIBuilder.cpp:21,112`; `Option.h:884`; `MergeBlocks.cpp:157,183` |
| L05 | CHIR 优化尾簇 | `ClosureConversion.cj:61-64` 缺 InlineLambda；`CodeGenBridge.cj:174,186,190-191` 缺 ArrayListConstStartOpt/RangePropagation/Devirtualization/ArrayLambdaOpt | O2 性能与优化后 IR 忠实性；挡 opt parity | L（建议拆 4 个独立 commit） | `LambdaInline.cpp:59`; `ClosureConversion.cpp:1259-1320,3162`; `CHIR.cpp:353-372,572-580,648-649` |
| L06 | C07/debug location 发射尾簇 | `TerminatorExprDispatcher.cj:116`、`DIBuilder.cj:19` 仍有 GAP；dispatcher 与 IRBuilder 发射面未全核 | 行号精度、断点/栈回溯；挡 debug-loc | M | `ApplyImpl.cpp:346`; `TupleExprImpl.cpp:199,236`; `IRBuilder.cpp:217,264,492`; `TerminatorExprDispatcher.cpp:45` |
| L07 | ComputeAnnotations / ClosureConversion / ConstEval 顺序 | `FaithfulAST2CHIR.cj:1099-1102` 的 ConstEval 早于 `CodeGenBridge.cj:115-119` 的 CC | 注解 const 值、closure 后清理；挡 annotation/const parity | M | `CHIR.cpp:1061-1094,1168-1175` |
| L08 | sema 诊断发射门控 | 精确 grep 为 59 处、13 文件，注释均为 `emission blocked on sema TypeCheckCall call-path parity` | 错误输入被宽松接受；挡 sema validation/diagnostics | L（按诊断族分批，不能机械删注释） | `DiagnosticEngine.cpp:314` + 每个发射点对应 C++ checker |
| L09 | `OptEffectCHIRMap` 与 `ActiveStatePool` | `ConstPropagation.cj:291`; `ConstAnalysisWrapper.cj:62` | const propagation、增量 effect、分析精度；挡 valanalysis | M | `ConstPropagation.cpp:324-371`; `ConstPropagation.h:137-143`; `ActiveStatePool.h:169+` |
| L10 | CHIR 二进制 serializer/deserializer 顶层闭环 | `CHIRSerializer.cj` 为空类；`CHIRDeserializer.cj` 只有 private init；文本 `CHIRSerializerImpl/CHIRDeserializerImpl` 仍在 | `.chir`、增量编译、deserializedVals；挡 chirser/varinit incremental | XL | `CHIRSerializer.cpp:31`; `CHIRDeserializer.cpp:42`; `CompilerInstance.cpp:1288`; `CHIR.cpp:1041-1057` |
| L11 | CHIR Attribute runtime 扩展域审计 | `Enums.cj:112-116` 的 `FAST_NATIVE/NO_HEAP_ALLOC/NO_WRITE_BARRIER_REC/NO_STACK_GROW` 明示 selfhost-only extension | CHIR 属性 wire/ABI 与 runtime 约束；挡 attr-domain 完全对齐 | M（先审通道，后决定迁移或保留） | C++ `include/cangjie/CHIR/IR/AttributeInfo.h` 属性终点；各 runtime constraint producer/consumer |
| L12 | ASAN CPointer read/write instrumentation | selfhost codegen 无 `InsertAsanInstrument` 或 `CJ_MCC_AsanRead` 命中 | sanitizer 可用性；挡 ASAN/runtime safety | M | `IntrinsicsDispatcher.cpp:359-378,470,478,504,512` |
| L13 | CHIRChecker vtable 校验 | `CHIRChecker.cj:562` 明示未移植 `CheckVTable` | 错误 CHIR 被放行；挡 WFC/checker 严格性 | S–M | `CHIRChecker.h:137`; `CHIRChecker.cpp:1150-1203` |
| L14 | annotation factory metadata 尾点 | `FaithfulAST2CHIR.cj:4017` 仍标记 annotated-decl factory metadata 未移植 | 注解构造器签名/参数 metadata；挡 annotation 完整性 | S–M | `TranslateAnnotation.cpp:175-244`; `AST2CHIR.cpp:215,227`; `ASTPackage2CHIR.cpp:1021` |
| L15 | SaveUsedMacros 调用链尾点 | `MacroEvaluation.cj` 已有实现，但 `CompilerInstance.cj:535` 仍标记 C++ 到达路径缺失 | unused-import 与宏依赖保存；挡 macro/import diagnostics | S | `MacroEvaluation.cpp:737-746,793` |
| L16 | ParallelUtil / AST2CHIR 并行编排 | `CHIRContext.cj:125` 仍指向 `ParallelUtil` 缺口 | 多线程 CHIR 构建与上下文管理；挡 parallel parity | M | `Utils/ParallelUtil.h:26+`; `AST2CHIR.cpp:456` |
| L17 | pointer print 仍用 objectId 代理地址 | `PrintNode.cj:282,322` 两处 GAP，明确非进程地址 | dump/诊断输出忠实性；属于 pointer-identity 系统根，不能局部伪造 | BLOCKED/设计 | 对应 C++ AST printer 的原始节点指针输出点 |
| L18 | SDK version 编译期注入 | `EmitPackageIR.cj:23` 仍写明缺 `CJ_SDK_VERSION` 注入机制 | SDK metadata、运行时/产物版本；挡 release parity | S（需构建配置 API 已存在后） | `EmitPackageIR.cpp:48-49` |
| L19 | NativeFFI 触发的 TySet transaction apply | `CommonTypeAlias.cj:209-218` 仍以自建数组 version + debug assert 后索引，自初版未变 | sema.NativeFFI 单包与约束回滚稳定性；挡 sema standalone | M | `Sema/Utils.cpp:615-640` 的 `CstVersionID`/`PData::Apply` |
| L20 | 断言契约逐簇核销 | 当前已有大量 CJC_ASSERT，但不存在覆盖原“系统性省略”的全量审计；L01/L19 已有具体缺口 | 非法状态 fail-fast；挡 validation hardening | XL（按 C++ 文件分簇） | 分散于对应 C++ named functions；不得无锚批量补 |

## 派发顺序建议

1. S/M 独立尾点：L13 → L14 → L15 → L18。
2. sema 严格性：L01 → L19 → L08；每批保留诊断调用路径证据。
3. CHIR 分析/顺序：L09 → L07 → L05。
4. 大系统：L02（cjo）与 L10（chirser）分开设计、分开落地。
5. debug 家族：L06 先收位置，再以 L03 为主线、L04 为后继。
6. L17 必须按 pointer-identity 系统根 BLOCKED 流程处理；L20 只作为逐文件审计计划，不能开无边界“批量补 assert”散弹 lane。
