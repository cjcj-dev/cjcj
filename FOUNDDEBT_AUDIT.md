# 奠基期债务与 FEATURE_DEBT 全量核销审计

审计日期：2026-07-11

审计基线：`master` / `74d4fe37507022550934ab515bd0b50c5e99bdf4`

原台账：`/root/cj_build/audit_persist/FEATURE_DEBT.md`（231 行，未修改）

## 口径

- `CLEARED`：目标在当前 `master` 有可追溯提交，且当前源码存在对应实现或旧缺口已消失。
- `LIVE`：当前源码仍有缺失实现、门控注释、空壳、文本 fallback，或只完成了原目标的一部分。
- `STALE`：原文是过程快照、已被后续根因替代，或原断言已不再能描述当前树；不把它作为独立可派债。
- 本次严格执行零构建：未运行 `cjpm build`、difftest、bcgate 或 self-compile；证据仅来自 `git`、当前 `packages/` grep 与 C++ 对照。
- `PROJECT_HANDBOOK.md` 是进入任务前已有的未跟踪文件，本次未改。

## 结论摘要

| 范围 | CLEARED | LIVE | STALE | 结论 |
|---|---:|---:|---:|---|
| 奠基期四债 | 2 | 2 | 0 | MTABLE、重复函数校验已清；Join/Meet 与 cjo 均为“主路径已落、尾契约仍活” |
| FEATURE_DEBT 可派目标 | — | 20 | — | 过程层已大量被 7 月 10–11 日战役覆盖；逐目标状态见下文，净化后的 20 个 LIVE 目标见 `FEATURE_DEBT_LIVE.md` |

当前机械盘点：`rg -n "GAP_TODO" packages --glob '*.cj'` 为 **83** 处；其中 `TypeCheckCall call-path parity` 为 **59** 处、分布于 **13** 个文件。旧台账的“89 处/66 同根”是历史快照，不可继续当当前计数。

## 奠基期四债

### F1 JoinAndMeet stub — LIVE（主算法已清，错误契约未清）

当前 `packages/sema/src/JoinAndMeet.cj:22-445` 已有函数/元组协逆变、union/intersection、可见性过滤、约束快照恢复、`JoinAsVisibleTy`/`MeetAsVisibleTy`，所以“仍是 stub”这一描述已经失效。主算法提交证据：`dbeb13d6`、`bd96c12e`、`df966d86`。

但不能整体记 CLEARED：selfhost 仍只有返回 `Ty` 的自由函数；C++ `src/Sema/JoinAndMeet.h:31-89` 的 `JoinAndMeet` 类、`ErrOrTy`、`Join(bool sprsErr)`、`Meet(bool sprsErr)`、`CombineErrMsg`、`SetJoinedType`、`SetMetType`、`AddFinalErrMsgs` 均无对应物。C++ 实现在 `src/Sema/JoinAndMeet.cpp:89-118,258-287,334-343,390-430`。这会丢失 join/meet 失败诊断与“失败时如何更新既有类型”的调用契约。

- 影响面：sema 返回类型合并、局部类型参数推断、if/try/match 分支类型；挡诊断严格性/validation 战役线。
- 建议 lane：M（先移植错误载荷与类/状态契约，再逐调用点替换直接 `Ty` 返回；不可只补字符串）。

### F2 cjo text-scrape — LIVE（前端 FlatBuffer 已清，modules 路径仍活）

主前端路径已结构化：`packages/frontend/src/FrontendModel.cj:705-850` 的 `CjoSignatureMaterializer` 以 `CjoFlatBuffer` 验证并分阶段加载，writer 位于 `packages/frontend/src/CjoFlatBufferWriter.cj:18+`。提交证据：`c4ecef0f`（writer/loader fidelity）、`1e7869aa`（buffer verify）、`0d02b18c`（loader stages）、`8241811a`（LoadRefs）。

但是 `packages/modules/src/ASTSerialization.cj:148-180` 的公开 `ASTLoader.LoadPackageDependencies` 仍执行 `String.fromUtf8(data)` 后调用 `ParseSerializedPackage`；后者在 `:316-340` 依赖 `SplitRawLines`/字段切分。该 loader 仍由 `packages/modules/src/CjoManagerImpl.cj:280-333` 创建。因此“cjo 已不靠文本刮取”不能成立，只能判部分清、整体 LIVE。

C++ 锚：`src/Modules/ASTSerialization/ASTLoader.cpp` 的 `ASTLoader`/FlatBuffer package load 族，以及 `src/Modules/ASTSerialization/ASTLoaderImpl.h`；当前 selfhost 前端结构化 materializer 证明迁移方向，不能用新文本协议替代。

- 影响面：ImportManager/CjoManager、common/specific cjo、跨包增量与宏包；挡 cjo/importmgr 与严格跨包战役线。
- 建议 lane：L（统一两套 loader 所有权，完整迁移 modules 活路径并删除文本 fallback；需先列出所有 `CreateASTLoader` 调用点）。

### F3 CGTypeInfo MTABLE — CLEARED

当前 `packages/codegen/src/CGTypeInfo.cj:1621-1668` 有 `GenerateMTableOfTypeInfo`、inline bitmap/外置表两路；`packages/codegen/src/InterfaceExtensionDef.cj:120+` 生成接口表，`:577` 添加 `CJED_FUNC_TABLE_ATTR`，`:642` 添加 `GC_MTABLE_ATTR`。对应 C++ 锚为 `src/CodeGen/Base/CGTypes/CGType.cpp:708-743` 与 `src/CodeGen/CJNative/CGTypes/CJNativeCGExtensionDef.cpp`。

master 证据：`0490f369`（vtable subsystem body）、`f01845c5`（activation）、`190d6bde`（extension func table）、`b102df71`（IR attributes）、`1b808ddc`（static invoke through vtable）。原“MTABLE 字段未完整”可核销。

### F4 sema validation gaps — CLEARED（原始清单唯一具名项：重复函数/重载冲突）

奠基文档 `docs/ROADMAP.md:116` 唯一明确列出的 validation gap 是“同签名重复函数静默接受”。`packages/sema/src/PreCheck.cj` 现已包含函数重定义/overload conflict 检查；提交 `ee95697d` 移植 `PreCheckFuncRedefinition`，`7ab75f26` 补齐 precheck function redefinition。C++ 锚：`src/Sema/PreCheck.cpp` 的 `PreCheckFuncRedefinition`/函数重定义检查族。

此结论不等于“所有 sema 诊断均清”：台账另列的 59 个 `TypeCheckCall parity` 发射门控仍是 LIVE，见净化版 L08。

## FEATURE_DEBT 逐目标核销

下表覆盖原文件所有可派目标；纯基线数字、排队状态、审稿事故与“某 lane 在飞”合并为 STALE 过程项，不伪装成独立功能债。

| 原文位置/目标 | 状态 | 当前证据 / master commit | C++ 锚或说明 |
|---|---|---|---|
| L4 `-g` 完整调试信息 | LIVE | `DIBuilder.cj:135,378` 仍显式抛 BLOCKED | `CodeGen/DIBuilder.cpp:223-334,645+`; `EmitExpressionIR.cpp:64-66` |
| L5 `--coverage` | LIVE | 与未完整 DIBuilder 共用 enable 条件；不能因 option 存在判清 | `DIBuilder.cpp:21,112`; `Option.h:884` |
| L6 O2 优化对 | LIVE（部分清） | FunctionInline/LICM 已由 `565bac9e`,`8e45f60e` 清；`ClosureConversion.cj:61-64`、`CodeGenBridge.cj:190-191` 仍缺 InlineLambda/Devirtualization/ArrayLambdaOpt | `LambdaInline.cpp:59`; `ClosureConversion.cpp:1259-1320,3162`; `CHIR.cpp:353-372,572-580,648-649` |
| L7 宏展开 host-ABI 桥 | CLEARED | `a75fc488`,`99224a4b`,`83275862`,`d1afc837`；当前不再传空 MacroCall 指针 | `MacroEvaluationCJNative.cpp:56+`; runtime `ast_api.cpp:459+` |
| L8 C07b 行号精度 | LIVE | `TerminatorExprDispatcher.cj:116`、`DIBuilder.cj:19` 仍有定位 GAP | `ApplyImpl.cpp:346`; `TupleExprImpl.cpp:199,236`; `IRBuilder.cpp:217,264,492`; dispatcher `EmitLocation` sites |
| L9 “Apple 全 throw/Windows 部分” | STALE | 当前已有大量 macOS/Windows `@When`，且 grep 不再得到原称的 Apple BLOCKED throw；是否目标可用需另做平台矩阵，原断言不能继续派 | 不把笼统平台口号当单一实现目标 |
| L10 注解/const 顺序 | LIVE | `FaithfulAST2CHIR.cj:1099-1102` 在 frontend closure conversion (`CodeGenBridge.cj:115-119`) 之前跑 ConstEval；独立 ComputeAnnotations 流程仍不完整 | `CHIR.cpp:1061-1094,1168-1175`（CC 后 ConstEval） |
| L11 CJC_ASSERT 系统性省略 | LIVE | 当前虽已有 897 个 `CJC_ASSERT/CJC_ABORT/assert` 命中，但 JoinAndMeet 错误路径等仍缺 C++ 断言契约；原目标未有全量核销提交 | 分散锚；应按 C++ 文件逐簇核对，禁止“批量猜补” |
| L12 存量四债 | MIXED | F1/F2 LIVE，F3/F4 CLEARED | 见上节 |
| L12 “TOPO_ORDER 741 gap 未清部分” | STALE | 是滚动总账/数量性引用，不是稳定具名目标；当前机械口径已变为 83 GAP_TODO | 应以本审计净化版重新派发 |
| L15 66× TypeCheckCall 发射门控 | LIVE（当前 59） | 精确 grep：59 处/13 文件 | `DiagnosticEngine.cpp:314` 及各对应 sema 诊断发射点；需逐点 C++ 对照 |
| L16 O2 四项 | LIVE（部分清） | LICM 已清；其余并入 O2 行 | 同 L6 |
| L17 debug 三项 | LIVE | 并入 `-g`/C07 行 | `TerminatorExprDispatcher.cpp:45`; DIBuilder anchors |
| L18 valanalysis 两项 | LIVE | `ConstPropagation.cj:291` 缺 `OptEffectCHIRMap`; `ConstAnalysisWrapper.cj:62` 跳过 ActiveStatePool | `ConstPropagation.cpp:324-371`; `ActiveStatePool.h:169+` |
| L19 杂项约 14 | LIVE（拆账） | 当前仍见 CHIRChecker vtable、anno factory、ParallelUtil、ptr-print、SDK injection、SaveUsedMacros 接线等；已拆入净化版 L12-L18 | 各项不再以“~14”模糊派发 |
| L23-24 CollectGenericParam / GetSingleParamFunc / default-param diag | CLEARED | `e0c6ca06`,`af1f08d0`,`3405d988` | `TypeChecker.cpp:2386-2557`; `Diags.cpp:453-467` |
| L25 NativeFFI TySet::apply 越界 | LIVE | `CommonTypeAlias.cj:209-218` 仍用自建 version 数组，仅 debug assert 后索引；自 6/29 初版未变 | C++ `Sema/Utils.cpp:615-640` 用 `CstVersionID` map + `PData::Apply` |
| L29 sigstack NOTE-A GetDerefedValue | CLEARED | 当前 `Translator.cj:8010-8035` 已收窄为 `IsClassOrArray()` | C++ `Translator.cpp:125-140` |
| L30 sigstack NOTE-B debug loc | CLEARED | 当前 Translator 的有 loc 重载会 `SetDebugLocation(loc)`，调用面已有 loc 转发 | C++ `Translator.cpp:120-140` |
| L31 ASAN instrumentation | LIVE | selfhost codegen 无 `InsertAsanInstrument`/`CJ_MCC_AsanRead` 命中 | `IntrinsicsDispatcher.cpp:359-378,470,478,504,512` |
| L32 “六项混一提交不利 bisect” | STALE | 流程说明，不是功能目标 | 不进入 LIVE 台账 |
| L36 GAP-A LICM outer type | CLEARED | `811a463d`,`961f259e`,`37526216`,`7fd8e870`,`8e45f60e` | `InvokeImpl.cpp:49-90`; `CJNativeIRBuilder.cpp:255-312` |
| L37 GAP-B subtype map | CLEARED | `7536a218`,`d90140cd`,`6810c3fc` | `CGPkgContext.cpp:30,93-133` |
| L39-42 var-init 生产端 | CLEARED | `8dea665a` 到 `9ebbd3c9` 完成生产、extend 与 late schedule | `TranslateClassDecl.cpp:145+`; `ASTPackage2CHIR.cpp:1751` |
| L44-45 CHIR Attribute 64-75 | CLEARED/重定义 | 旧 64-75 已由 attrdom 提交删除/改道；当前只剩 `FAST_NATIVE` 与 runtime-spec 3 位扩展，形成新的 LIVE 边界审计 | C++ `include/cangjie/CHIR/IR/AttributeInfo.h` 当前止于 38；见净化版 L11 |
| L47-49 MacroCall 句柄 | CLEARED | 同宏 ABI commits | `MacroEvaluationCJNative.cpp:56+` |
| L51-55 P1/P2/P3 | CLEARED | P1 `90961c91`,`2069faf8`; P2 `eb758fa5`; P3 `c9fe4ec0`..`565bac9e`，后续 O2 114/114 commit `6bd5865c` | ledger 所列 `PartialInstantiation.cpp`, `ASTPackage2CHIR.cpp`, `CommonTypeAlias.h` |
| L57-61 P1 deeper gap | CLEARED | `932e163d`,`f84b07c6` 移植 instantiated member target 并移除平行查找 | `GenericInstantiationManagerImpl.cpp:856,879,919-923` |
| L63-75 O-level 基线/pkgcycle | STALE（目标已清） | 历史矩阵与包环设计已被 GIM facade/接线覆盖：`1846dcc6`,`eb758fa5` | 过程快照不保留 |
| L77-85 varinit 七依赖 | CLEARED | `f1d14193`,`1c743998`,`c227277e`,`7837016f`,`1657721f`,`f7ae79b4`,`99076c13` | 原行列出的七个 C++ named entities |
| L88 CHIR 二进制反序列化 | LIVE（部分落地） | FlatBuffer runtime/bindings 与 typed annotations 已落，但 `CHIRSerializer.cj` 仍空类，`CHIRDeserializer.cj` 仍只有 private init，文本 impl 仍在 | `CHIRSerializer.cpp:31`; `CHIRDeserializer.cpp:42`; `CompilerInstance.cpp:1288` |
| L89 PreCheck declMap 清空 | CLEARED | `3405d988` | `PreCheck.cpp:2001+` |
| L90-100 tccparity/diagnostic node adapter | MIXED | Import map与 adapter 已由 `0a94247c`,`697a3d89`,`7434e393` 清；59 个发射门控仍 LIVE | 分拆为 L08，不重复记债 |
| L101 attrdom report | CLEARED/重定义 | 旧 11 属性迁移已落；只保留当前 runtime extension domain 审计 | `afa8ce0a`..`80020d7b`,`3c6b64dd` |
| L103-117 diagnode/b58/a2mangle/CollectMainDecl | CLEARED | `697a3d89`,`f22b4998`,`e0c6ca06`,`3405d988` 等 | 原列 C++ anchors |
| L119-121 CFunc export / localCache | CLEARED | CFunc/driver/instantiation链后续落地；P1 与 `.so` target 均已清 | `157e931e`,`6b57f878`,`90961c91`,`2069faf8` |
| L123-135 varinit orchestration/PrivateTypeConverter/consume/GAP-A/B/Dump | CLEARED | varinit、private converter、parser recovery、LICM/subtype、DumpCHIR 均已有实现/提交 | `c9fe4ec0`, varinit chain, `67de6d03`, LICM/subtype commits；`CodeGenBridge.cj:127-168` |
| L137-157 macroprop/GIM pollution/ExprArg/call hierarchy/attrdom/rtw4/b60 | CLEARED | `227bc011`,`9fe23898`,`ccb4bab5`,`e8990f46`,`f002004b`,`f7dbd368`,`3c6b64dd`,`7434e393`,`4e45c31e` | 原列 named anchors |
| L154-176 InstantiateWithRearrange/Visitor | CLEARED | `90961c91`,`2069faf8`,`57e69feb`,`c5168ca5` | `PartialInstantiation.cpp:1563-1763`; `Visitor.h:1-362` |
| L163-165 CHIR serialization 重确认 | LIVE | 并入 CHIR binary serialization 行 | 同上 |
| L179 conformance 基线 | STALE | 测量快照，不是实现目标；本任务禁止构建，未刷新 | 不入 LIVE |
| L181-183 p3/chirser 层 | MIXED | P3 清；chirser runtime/bindings部分清，顶层 serializer/deserializer仍 LIVE | `f4de81b3`..`fb9c523a`; current empty top-level classes |
| L185 shared-object target | CLEARED | `157e931e`,`6b57f878` | driver compile-target path |
| L187 cliflags 前提反转 | STALE | 原文自身已证明 MISSING=0；不是功能债 | 不入 LIVE |
| L190-193 p3/属性消费 | CLEARED | p3 chain + `f529269d`,`3087deeb` | `CJNativeIRBuilder.cpp:1283`; `CGGenericType.cpp:48` |
| L195-203 typed load/store/GetSize/attrwire | CLEARED | `cbb5647e`,`691be364`,`0fcd3fd6`,`3087deeb` | `IRBuilder.cpp:144-172`; `CJNativeIRBuilder.cpp:1847` |
| L205-218 shared target/VArray/O2 mangle/chirser | CLEARED 或并入 chirser LIVE | shared target、VArray、O2 mangle已清；chirser只保留顶层缺口 | `0fcd3fd6`,`6bd5865c`; serialization anchors above |
| L220-226 o2mangleT/数组初始化 | CLEARED | `9775ba6d`,`932e163d`,`f84b07c6`,`6bd5865c` | ledger named GIM/array init anchors |
| L228-231 typed AnnotationMap | CLEARED | `1fefac60` 已移植 typed `AnnotationMap`/`Base.Set<T>`；CHIR binary deserialize 的剩余接线归 L10，不把未合分支当清账证据 | `Base.h:22`; `Annotation.h:360-439` |

## 静态审计自检

- 只新增两份 Markdown；未修改 `packages/`、脚本、shim 或原台账。
- 未运行任何构建或 gate；因此没有伪造 gate 输出。
- 所有 CLEARED commit 均以 `git merge-base --is-ancestor <sha> HEAD` 验证可达。
- 无任何 grep 不到 C++ 出处的新编译器符号。
- 未改业务源码绕过、未加 band-aid 吞 bug。
- 本任务是核账，不移植缺失系统根；pointer identity、ImportManager、CHIR LinkTypeInfo 等均未自行替代。
- 本次未移植 C++ 函数，故“平台分支完整性/全分支覆盖计数”不适用；LIVE 项均给出 C++ named anchor 供后续 lane 逐分支移植。
