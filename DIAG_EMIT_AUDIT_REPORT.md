# Diagnostic emission audit (diagnode Task3)

基线：`master@74d4fe37507022550934ab515bd0b50c5e99bdf4`。本报告是纯盘点；未修改任何 `.cj` 或编译器业务源码。

## 口径与方法

- 枚举 `packages/**/*.cj` 中对 basic 引擎原语 `Diagnose` / `DiagnoseRefactor`，以及 node 适配通道和 builder 的 `AddHint` / `AddNote` 的实际调用表达式。
- 排除 API 定义内的转发调用，并按接收者核对后排除 `VarInitCheck.cj` 中 2 个同名但并非 `DiagnosticBuilder` 的 `checkResult.AddNote`。
- C++ 对照优先级是“同名诊断枚举 + 同名文件 + 同名函数 + 函数内序号”；builder 无诊断枚举时使用“同名文件 + 同名函数 + 同 API 的函数内序号”。
- 重载判定严格分开：
  - 旧式 `Diagnose`：node 位于 `DiagKind` **之前**；同时识别 `Diagnose(node, pos, kind, ...)`。
  - `DiagnoseRefactor`：node 位于 kind **之后**。
- `mapping` 列保留证据强度：`exact` / `probable` / `ambiguous-N` / `function-ordinal` / `unmapped`。没有 C++ 直接调用的点明确记 `unmapped`，未猜造出处。
- 每个调用点的完整证据在 [DIAG_EMIT_AUDIT.tsv](DIAG_EMIT_AUDIT.tsv)：selfhost file:line、函数、API、当前重载、C++ file:line、C++ 重载、迁移结论、b5657 标记、两侧调用文本。

## 汇总

| 项目 | 数量 |
|---|---:|
| 有效调用点 | 810 |
| `DiagnoseRefactor` | 386 |
| `Diagnose` | 159 |
| `AddHint` | 108 |
| `AddNote` | 157 |
| 已定位 C++ 直接对应点 | 596 |
| 无直接对应（明确 `unmapped`） | 214 |
| 当前已走 node 通道 | 68 |
| 建议迁移到 node | 277 |
| 保留当前通道 | 533 |

277 个候选的 API 分布：`DiagnoseRefactor` 142、旧式 `Diagnose` 98、`AddHint` 20、`AddNote` 17。按包分布：sema 244、parse 19、macro 8、modules 5、frontend 1。

这 277 个点是本次发现的确定对齐债务：C++ 对应调用解析为 node/node+position 重载，而 selfhost 当前调用解析为 range/position/text-only 等非 node 重载。本任务按要求只记账、不修复。带 `ambiguous-N` 的行仍是候选，但迁移前应先人工复核 TSV 中保存的 C++ 调用文本；因此批次风险标为 medium。

## b5657 五件套

- ① node 版 `DiagnoseRefactor`：Task2 已迁移的 50 个主发射点标为 `Task2-node-main`。
- ② `MakeRealRange(Node,...)` 与 ③ node 版 `AddMacroCallNote`：由上述 node 主通道调用覆盖；含 `ASTTypeValidator.cj:193` 的 node+range 点。
- ④ `Diagnostic.node` stored pointer：按 spec §5 属 LSP-only 延后项，不是调用点；本 TSV 不把它伪装成已落地。
- ⑤ node builder `AddHint/AddNote`：11 个实际调用 node builder 重载的点标为 `Task2-node-builder`；同文件中的单参数文本 `AddNote(note)` 不计入。
- 合计 61 个 b5657/Task2 相关调用点，均可用 `b5657_five_set != NO` 机械筛出。

## 迁移批次

批次按“风险 → 包/文件 → 行号”聚合，每批最多 20 点。low 共 36 批/133 点；medium 共 37 批/144 点。精确成员由 TSV 的 `batch` 列给出。

| Batch | Risk | File | Points | Lines |
|---|---|---|---:|---|
| B001 | low | `packages/frontend/src/CjoFlatBufferWriter.cj` | 1 | 936–936 |
| B002 | low | `packages/macro/src/MacroExpansion.cj` | 1 | 133–133 |
| B003 | low | `packages/modules/src/ImportManager.cj` | 1 | 1104–1104 |
| B004 | low | `packages/modules/src/ModulesDiag.cj` | 4 | 21–107 |
| B005 | low | `packages/parse/src/ParserDiag.cj` | 19 | 495–1356 |
| B006 | low | `packages/sema/src/CalcConstExpr.cj` | 1 | 81–81 |
| B007 | low | `packages/sema/src/DeclAttributeChecker.cj` | 1 | 221–221 |
| B008 | low | `packages/sema/src/Diags.cj` | 8 | 50–277 |
| B009 | low | `packages/sema/src/EnumSugarChecker.cj` | 1 | 78–78 |
| B010 | low | `packages/sema/src/InheritanceChecker/GenericInheritanceChecker.cj` | 1 | 190–190 |
| B011 | low | `packages/sema/src/InheritanceChecker/InstantiatedChecker.cj` | 1 | 592–592 |
| B012 | low | `packages/sema/src/InheritanceChecker/NativeFFIInheritanceChecker.cj` | 5 | 32–262 |
| B013 | low | `packages/sema/src/InheritanceChecker/StructInheritanceChecker.cj` | 19 | 186–2330 |
| B014 | low | `packages/sema/src/LegalityOfUsage/EmitLegalityOfUsage.cj` | 3 | 56–145 |
| B015 | low | `packages/sema/src/LegalityOfUsage/LegalityOfUsage.cj` | 1 | 572–572 |
| B016 | low | `packages/sema/src/PatternUsefulness.cj` | 3 | 809–952 |
| B017 | low | `packages/sema/src/Plugin/PluginCustomAnnoChecker.cj` | 3 | 914–944 |
| B018 | low | `packages/sema/src/PreCheck.cj` | 3 | 509–797 |
| B019 | low | `packages/sema/src/Test/TestManager.cj` | 4 | 292–365 |
| B020 | low | `packages/sema/src/TypeCheckAccess.cj` | 3 | 553–673 |
| B021 | low | `packages/sema/src/TypeCheckAnnotation.cj` | 1 | 102–102 |
| B022 | low | `packages/sema/src/TypeCheckBuiltinExpr.cj` | 2 | 561–715 |
| B023 | low | `packages/sema/src/TypeCheckCall.cj` | 3 | 2730–4799 |
| B024 | low | `packages/sema/src/TypeCheckClassLike.cj` | 2 | 168–183 |
| B025 | low | `packages/sema/src/TypeCheckDecl.cj` | 5 | 184–824 |
| B026 | low | `packages/sema/src/TypeCheckExpr/Block.cj` | 1 | 91–91 |
| B027 | low | `packages/sema/src/TypeCheckExpr/LitConstExpr.cj` | 1 | 246–246 |
| B028 | low | `packages/sema/src/TypeCheckExpr/ResumeExpr.cj` | 3 | 27–73 |
| B029 | low | `packages/sema/src/TypeCheckExpr/SpawnExpr.cj` | 1 | 66–66 |
| B030 | low | `packages/sema/src/TypeCheckExpr/SynchronizedExpr.cj` | 1 | 40–40 |
| B031 | low | `packages/sema/src/TypeCheckExpr/TryExpr.cj` | 2 | 195–304 |
| B032 | low | `packages/sema/src/TypeCheckExpr/TypeChecker.cj` | 6 | 1720–4539 |
| B033 | low | `packages/sema/src/TypeCheckExtend.cj` | 9 | 217–1090 |
| B034 | low | `packages/sema/src/TypeCheckPattern.cj` | 1 | 630–630 |
| B035 | low | `packages/sema/src/TypeCheckReference.cj` | 8 | 504–1307 |
| B036 | low | `packages/sema/src/TypeCheckType.cj` | 4 | 237–618 |
| B037 | medium | `packages/macro/src/TestEntryConstructor.cj` | 7 | 382–414 |
| B038 | medium | `packages/sema/src/CJMP/Parameters.cj` | 1 | 93–93 |
| B039 | medium | `packages/sema/src/CalcConstExpr.cj` | 4 | 14–56 |
| B040 | medium | `packages/sema/src/Diags.cj` | 2 | 214–233 |
| B041 | medium | `packages/sema/src/EnumSugarChecker.cj` | 2 | 65–128 |
| B042 | medium | `packages/sema/src/InheritanceChecker/BuiltInInheritanceHelper.cj` | 2 | 126–143 |
| B043 | medium | `packages/sema/src/InheritanceChecker/GenericInheritanceChecker.cj` | 1 | 111–111 |
| B044 | medium | `packages/sema/src/InheritanceChecker/InstantiatedChecker.cj` | 6 | 300–555 |
| B045 | medium | `packages/sema/src/InheritanceChecker/NativeFFIInheritanceChecker.cj` | 1 | 127–127 |
| B046 | medium | `packages/sema/src/InheritanceChecker/StructInheritanceChecker.cj` | 17 | 1139–2358 |
| B047 | medium | `packages/sema/src/LegalityOfUsage/EmitLegalityOfUsage.cj` | 3 | 134–173 |
| B048 | medium | `packages/sema/src/PreCheck.cj` | 4 | 125–861 |
| B049 | medium | `packages/sema/src/TypeCheck.cj` | 1 | 128–128 |
| B050 | medium | `packages/sema/src/TypeCheckAccess.cj` | 6 | 456–714 |
| B051 | medium | `packages/sema/src/TypeCheckAnnotation.cj` | 1 | 30–30 |
| B052 | medium | `packages/sema/src/TypeCheckBuiltinExpr.cj` | 2 | 588–628 |
| B053 | medium | `packages/sema/src/TypeCheckCall.cj` | 1 | 2633–2633 |
| B054 | medium | `packages/sema/src/TypeCheckDecl.cj` | 2 | 413–840 |
| B055 | medium | `packages/sema/src/TypeCheckExpr/BinaryExpr.cj` | 1 | 679–679 |
| B056 | medium | `packages/sema/src/TypeCheckExpr/IsAsExprs.cj` | 1 | 108–108 |
| B057 | medium | `packages/sema/src/TypeCheckExpr/LitConstExpr.cj` | 1 | 237–237 |
| B058 | medium | `packages/sema/src/TypeCheckExpr/LoopExprs.cj` | 4 | 136–203 |
| B059 | medium | `packages/sema/src/TypeCheckExpr/NameReferenceExpr.cj` | 1 | 883–883 |
| B060 | medium | `packages/sema/src/TypeCheckExpr/OptionalChainExpr.cj` | 1 | 47–47 |
| B061 | medium | `packages/sema/src/TypeCheckExpr/RangeExpr.cj` | 4 | 89–156 |
| B062 | medium | `packages/sema/src/TypeCheckExpr/SpawnExpr.cj` | 3 | 22–108 |
| B063 | medium | `packages/sema/src/TypeCheckExpr/ThrowExpr.cj` | 1 | 88–88 |
| B064 | medium | `packages/sema/src/TypeCheckExpr/TryExpr.cj` | 6 | 73–185 |
| B065 | medium | `packages/sema/src/TypeCheckExpr/TupleLit.cj` | 1 | 52–52 |
| B066 | medium | `packages/sema/src/TypeCheckExpr/TypeChecker.cj` | 20 | 1725–5059 |
| B067 | medium | `packages/sema/src/TypeCheckExpr/TypeChecker.cj` | 1 | 5077–5077 |
| B068 | medium | `packages/sema/src/TypeCheckExpr/TypeConvExpr.cj` | 1 | 32–32 |
| B069 | medium | `packages/sema/src/TypeCheckExtend.cj` | 4 | 151–934 |
| B070 | medium | `packages/sema/src/TypeCheckGeneric.cj` | 4 | 228–579 |
| B071 | medium | `packages/sema/src/TypeCheckReference.cj` | 20 | 247–1242 |
| B072 | medium | `packages/sema/src/TypeCheckReference.cj` | 6 | 1259–1390 |
| B073 | medium | `packages/sema/src/TypeCheckType.cj` | 1 | 50–50 |

## 已知审计边界

- 214 个 `unmapped` 点不是缺省映射：其中包括 basic 测试、selfhost 包装函数、动态 kind 调用及 C++ 无同构 builder 调用的路径。它们的建议为 `manual-review-no-direct-cpp` 或保留当前通道，不进入迁移批次。
- 此清单是调用点审计，不审计 `Diagnostic.node` / `SubDiagnostic.node` 字段本身；字段决策遵循 spec §5。
- TSV 中的行号绑定本任务基线；后续源码变更后应重新枚举。

## 合规与验证

- 本任务没有新增或修改任何函数/helper/业务符号，因此无“新增符号的 C++ 贴源”项；逐调用点 C++ 证据已写入 TSV。
- 未改 C++ 源，平台分支检查不适用；没有 `@When` 对齐面。
- 本任务不移植 C++ 函数，因此“全分支覆盖 N”不适用。
- 无任何 grep 不到 C++ 出处的新代码符号。
- 未改业务源码绕过、未加 band-aid 吞 bug。
- 未撞到系统根；无自行替代。
