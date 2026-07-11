# L15 SaveUsedMacros 调用链尾点 REPORT

## 结论

L15 已按 C++ 调用路径补齐。普通宏展开路径在 `ResolveMacroCall` 成功后调用
`SaveUsedMacros`；child-process/LSP 服务端仅在 `enableParallelMacro` 分支调用
完整的 `SaveUsedMacros`。服务端串行分支与 C++ 一致，只调用
`SaveUsedMacroPkgs`。同时删除数据源缺失期间的 frontend 回写和 unused-import
空表全放行补偿。

## 逐符号 C++ 对照

- 阶段入口：`bool CompileStrategy::MacroExpand() const`，
  `/root/cj_build/cangjie_compiler/src/Frontend/CompileStrategy.cpp:555-570`。
  关键路径为 `MacroExpansion me(ci); me.Execute(ci->srcPkgs);`。selfhost 对应
  `packages/frontend/src/CompileStrategy.cj:85-95`。
- 普通首轮求值：
  `bool MacroEvaluation::NeedCreateMacroCallTreeForFirstEval(MacroCall&, AST::MacroInvocation*)`，
  `/root/cj_build/cangjie_compiler/src/Macro/MacroEvaluation.cpp:790-804`。
  `if (macCall.ResolveMacroCall(ci))` 成功分支在 `:793` 调
  `SaveUsedMacros(macCall)`；selfhost 对应
  `packages/macro/src/MacroEvaluation.cj:1100-1112`。
- 本次修改的服务端调用：
  `bool MacroEvaluation::EvalMacroCallsAndWaitResult()`，
  `/root/cj_build/cangjie_compiler/src/Macro/MacroEvaluationSrv.cpp:219-240`。
  仅处理 `status == INIT` 的调用；`FindMacroDefMethod(ci)` 失败时诊断并
  `continue`，成功时在 `:233` 调 `SaveUsedMacros(*mc)`。该函数只由
  `EvalMacroCall` 的 `enableParallelMacro` 分支调用（`:315-317`）；串行分支
  在 `:319-332` 调 `SaveUsedMacroPkgs(macCall->packageName)`。selfhost 共享
  `evalServerCalls`，因此在 `packages/macro/src/MacroEvaluationSrv.cj:65-69`
  以同一个 `enableParallelMacro` 条件选择这两个 named 调用。
- 被调实体：`void MacroEvaluation::SaveUsedMacros(MacroCall& macCall)`，
  `/root/cj_build/cangjie_compiler/src/Macro/MacroEvaluation.cpp:737-746`。
  它先调 `SaveUsedMacroPkgs(macCall.packageName)`；随后取得 `GetNode()` 和
  `GetDefinition()`，若 node/curFile/decl 任一缺失则返回，否则调用
  `ci->importManager->AddUsedMacroDecls(curFile, decl)`。selfhost 对应
  `packages/macro/src/MacroEvaluation.cj:775-784`，字段与条件一致。
- unused-import 消费端：
  `bool CheckUnusedImportImpl::IsImportContentUsedInMacro(AST::ImportSpec&)`，
  `/root/cj_build/cangjie_compiler/src/Sema/CheckUnusedImportImpl.cpp:195-228`。
  C++ 在 `GetUsedMacroDecls` 后直接按 wildcard/package/named-decl 分支查询，
  没有“map 为空即 used”的返回；selfhost 已删除该补偿，保持同分支。
- frontend faithful-sema seed 现在只把已有 `GetUsedMacroDecls(file)` 数据传给
  `AddResolvedUsedMacroDecls`。删除的 `AddUsedMacroDecls` 回写循环在 C++ 中无对应
  调用，且仅把同一数据写回同一 manager。

没有新增函数、类型、字段或 helper；唯一新增调用符号 `SaveUsedMacros` 对应上述
C++ named 实体。

## 分支完整性

- `SaveUsedMacros`：全部 1 个 early-return guard（3 个空值子条件）及 1 个成功写入
  路径均已覆盖，来源为 `MacroEvaluation.cpp:742-745`。
- 普通调用点：`ResolveMacroCall` 成功/失败 2 个结果均保持；只在成功结果保存，来源为
  `MacroEvaluation.cpp:792-804`。
- 服务端调用点：全部并行/串行 2 个分支均保持。并行分支覆盖非 INIT、方法查找失败、
  结果序列化失败 3 个 `if` 和成功 `SaveUsedMacros` 路径，来源为
  `MacroEvaluationSrv.cpp:223-233`；串行分支只调 `SaveUsedMacroPkgs`，来源为
  `MacroEvaluationSrv.cpp:315-332`。
- `IsImportContentUsedInMacro`：全部 wildcard/package 与 named-decl 两大分支、3 个
  used-success return 和最终 false return 均保持，来源为
  `CheckUnusedImportImpl.cpp:203-227`；不存在 selfhost-only 空表成功分支。

## 平台分支检查

执行：

```text
rg -n "_WIN32|__APPLE__|__OHOS__|__linux__|#ifdef|#elif" \
  src/Macro/MacroEvaluation.cpp src/Macro/MacroEvaluationSrv.cpp \
  src/Frontend/CompileStrategy.cpp src/Sema/CheckUnusedImportImpl.cpp
```

相关函数范围 `MacroEvaluation.cpp:737-804`、`MacroEvaluationSrv.cpp:219-240`、
`CompileStrategy.cpp:555-570`、`CheckUnusedImportImpl.cpp:195-228` 均无平台分支。
整文件命中均在这些范围外（MacroEvaluation.cpp:1101/1134/1147；
MacroEvaluationSrv.cpp:14/20/60/75/138/156/160/163/178/354；
CompileStrategy.cpp:243/253/579），故本 diff 不需新增 `@When`。

## 验证原始输出

复审 fixup 后权威 delta gate（manifest fail-closed 到完整 114+15）：

```text
cjpm build success
difftest: TOTAL=114  PASS=114  MISMATCH=0  FAIL=0
smoke15: PASS=15 FAIL=0
bcgate: shared functions: 2490  |  byte-identical: 2490 (100.0%)  |  differing: 0 | fully-identical samples: 114/114  |  compile-errors: 0
VERIFY-EXIT=0
DELTA: skipped=0 ran=129
SELFHOST_BINARY=target/release/bin/cjcj::cjc SIZE=66170640
```

build log 中 `error:` 检索为空。

宏专门 smoke：

```text
selfhost COMPARISON: PASS=0 FAIL=5
```

五个 fixture 的 macro-definition 均 `rc=0`；五个 user compile 均在已登记的上游
动态方法查找前沿失败：`Cannot find method from dynamic libs for macro call ...`，即
`MacroCallResolve.cpp:228` 对应的 READY 诊断债，尚未进入本次
`FindMacroDefMethod == true -> SaveUsedMacros` 路径。`f5_unused_import` 控制组仍
`rc=0` 并报告 `warning: unused import 'std.collection.*'`。因此宏 gate 保持仓库已知
pre-integration 失败状态，无新增失败类型；不能把正例宣称为已通过。

## 忠实性声明

1. 无任何 grep 不到 C++ 出处的新符号。
2. 未改业务源码绕过、未加 band-aid 吞 bug。
3. 未撞到需自行替代的系统根；没有自行替代任何缺失设施。

===END===
