# 2026-07-11 gap 台账全量对账

## 结论

本次对 `/root/cj_build/audit_persist/gapscan_items.tsv` 的全部 8,391 条原始记录做了逐行机械对账。审计时可定位的 master 基线为 `47ce9cbcb19264bc02bd6d2b5f122a7f754f7777`（2026-07-04 16:13 +08:00），当前基线为 `74d4fe37507022550934ab515bd0b50c5e99bdf4`。

| status | 行数 | 判据 |
|---|---:|---|
| FIXED | 615 | 审计基线不存在、当前存在精确 identifier，或审计时的 selfhost-only identifier 已被删除；证据附首次相关提交 |
| PARTIAL | 485 | 原 PARTIAL identifier 仍在，且审计后无该 identifier 的直接 token 修改，故保守维持部分实现 |
| REMAINING | 5,635 | named C++ identifier 当前仍不存在，或原 selfhost-only identifier 仍在原扫描文件 |
| OBSOLETE | 624 | 聚合元数据/明确 no-gap 行、审计基线即存在的误报，或重构后无当前映射 |
| UNSURE | 1,032 | identifier 同名歧义、文件/签名映射不唯一，或审计后改过但 grep 无法证明全部 branch parity |
| **总计** | **8,391** | 与原 TSV 物理行数一致 |

“尚未清账”按 `PARTIAL + REMAINING + UNSURE` 计为 7,152 条原始 bullet；这个数不能直接视为 7,152 个真实 gap。2026-07-04 聚合报告已经说明：8,391 条是 raw survey volume，经过人工聚类只保留 628 item-equivalent / 74 clusters，过滤 7,797 条命名形状、重复、既定架构和 invented-only 噪声。任务背景中的 1,545 是 2026-06-30 旧审计，`TOPO_ORDER.md` 与 `GAP_REPORT_20260704.md` 均已标为 STALE。

## 输入列与判定方法

原文件无表头、固定五列：`block`、`gap_kind_or_group`、`named_symbol`、`source_anchor`、`severity`。部分块（b3b/b6/b6b/b9/b9b）第二列被聚合器写成 C++ 文件/分组名；本次保留原五列不改写，并从对应 `gapscan20260704/<block>.md` bullet 内的 `MISSING/PARTIAL/INVENTED` 标记恢复判定类型。输出新增 `status`、`judge_evidence` 两列和表头。

机械判据按以下顺序执行：

1. 从 symbol 取最后一个 named identifier，在当前 `packages/` 与审计基线树中按 token 搜索；C++ 目录同时约束 selfhost package 域（如 `Sema` → `packages/sema/`），避免跨包同名误判。
2. 对扫描记录中带 selfhost 路径的项，优先要求 identifier 位于同一相对文件；签名形态、首个当前行号写入 `judge_evidence`。
3. 索引 `47ce9cbc..74d4fe37` 的 packages patch，直接 token 增删附 commit hash/subject；仅有调用/同名或改过但无法证明全分支时标 `UNSURE`。
4. `PARTIAL` 不因“文件改过”自动清账。grep 不能证明全部 case/early-return，故改过的项仍标 `UNSURE`，未直接改过的维持 `PARTIAL`。
5. 不以能构建、测试通过或近似命名代替忠实性判断；本任务也按约束未运行任何构建。

原始聚合器自己的 declared counts 为 `missing=1686 partial=1310 invented=5391`，三者之和与 8,391 物理行也不相等；刷新 TSV 因而以“逐物理行保留 + 证据列”为唯一账本，不回填或伪造旧计数。

## 分布

按严重度的机械状态分布：

| severity | FIXED | PARTIAL | REMAINING | OBSOLETE | UNSURE | 合计 |
|---|---:|---:|---:|---:|---:|---:|
| BOOTSTRAP | 207 | 204 | 1,501 | 266 | 627 | 2,805 |
| BC | 157 | 144 | 669 | 15 | 239 | 1,224 |
| DIAG | 63 | 130 | 248 | 20 | 148 | 609 |
| LOW | 188 | 7 | 3,217 | 321 | 16 | 3,749 |
| 空/聚合异常 | 0 | 0 | 0 | 2 | 2 | 4 |
| **合计** | **615** | **485** | **5,635** | **624** | **1,032** | **8,391** |

按恢复后的扫描类型：

| 原扫描类型 | FIXED | PARTIAL | REMAINING | OBSOLETE | UNSURE | 合计 |
|---|---:|---:|---:|---:|---:|---:|
| MISSING | 393 | 0 | 1,074 | 0 | 219 | 1,686 |
| PARTIAL | 0 | 485 | 0 | 2 | 811 | 1,298 |
| INVENTED | 222 | 0 | 4,561 | 607 | 2 | 5,392 |
| 元数据/no-gap | 0 | 0 | 0 | 15 | 0 | 15 |

这里的 INVENTED 仍保留 raw 审计语义；聚合报告已明确 invented-only bullet 不可单独作为 gap 证据。因此攻击队列不按其 4,561 条 REMAINING 排序，而以 MISSING/PARTIAL 的 BOOTSTRAP/BC、`FEATURE_DEBT.md` 功能影响和明确源码锚交集为准。

## FEATURE_DEBT.md 交叉

债务源为 `/root/cj_build/audit_persist/FEATURE_DEBT.md`（仓库内没有同名文件）。逐 identifier 交叉后，273 条 raw TSV 证据行命中了债务文本中的 named identifier，均在 `judge_evidence` 末尾加了关联标记。

下列功能债没有以同名 top-level symbol 出现在 TSV 的 `named_symbol` 列，必须作为账外关联保留，不能因 TSV 无行而视为清账：

| FEATURE_DEBT 项 | TSV 关联/当前机械证据 | 裁决 |
|---|---|---|
| `-g` 完整调试信息、`--coverage` | b9b 的 9 个 CJNativeDIBuilder helper 中 1 FIXED、8 REMAINING；`CreateDIType` 本身不在 TSV named_symbol | REMAINING，功能优先 |
| O2 `InlineLambda/DoFunctionInlineForLambda` | TSV 无同名行；`packages/chir/src/ClosureConversion.cj:61` 仍有具名 `GAP_TODO` | REMAINING，功能优先 |
| 宏展开 host-ABI `MacroCall*` 桥 | TSV 无 `MacroEvaluationCJNative` 同名行；FEATURE_DEBT 记录 selfhost 仍传空指针且属句柄/pointer-identity 系统根 | REMAINING/BLOCKED，不能用替代实现 |
| `ComputeAnnotations` 第二次 ClosureConversion 与相对顺序 | TSV 只有其内部 value/helper 行，没有 `ComputeAnnotations` top-level 行 | UNSURE，保持债务 |
| `GetDerefedValue` 窄 `IsClassOrArray` 语义 | TSV 有两条：一条 REMAINING、一条 UNSURE | 已关联，需字段级复核 |
| 跨平台 Apple/Windows 分支 | 无单一 named_symbol 可一一对应 | 账外横切债，保持 |

已被后续提交明显覆盖的旧重点包括 MarkClassHasInited（5 个 helper + class 均已出现，提交 `a8a181c7`）、CHIRSplitter `.cgCache`、reflection metadata 主族、raw array/store 和 typed AnnotationMap；相应 TSV 行已按 token/commit 证据标 FIXED 或在不能证明全分支时标 UNSURE。

## 刷新版攻击排序

排序遵循 functional-first：先真实用户功能与 BC 影响，再自举覆盖面；同层内优先精确 MISSING，`UNSURE` 必须先做小范围源码对照，不能直接当修复任务。

| Rank | 攻击簇 | 当前证据 | 建议 |
|---:|---|---|---|
| 1 | `-g` / coverage 的 DI type lowering | CJNativeDIBuilder 8 个 BC helper 精确 REMAINING；FEATURE_DEBT #1/#2 | 先完整 DIBuilder 设计/依赖图；这是最大单件用户功能 |
| 2 | CHIR binary serializer/deserializer | BOOTSTRAP/BC 池中 serializer 77 REMAINING、27 UNSURE；deserializer 22 REMAINING、5 UNSURE；当前仍见 annotation switch `GAP_TODO` | 按 FlatBuffers typed path 整簇推进，禁止 text fallback 平行实现 |
| 3 | CodeGen CGType / TypeInfo | 207 条高影响 raw 行：40 REMAINING、67 PARTIAL、67 UNSURE、33 FIXED | 先按 concrete type family 聚类，优先实际 BC producer/consumer，不按 helper 数散弹修 |
| 4 | O2 lambda inline | TSV 账外；ClosureConversion 精确 `GAP_TODO` + FEATURE_DEBT #3 | 作为独立 O2 功能簇；先核 InlineLambda/DoFunctionInlineForLambda 全调用链 |
| 5 | 宏展开 host-ABI 桥 | FEATURE_DEBT 明确宏回调 SIGSEGV 与 `MacroCall*` 句柄系统根 | 保持 BLOCKED 纪律，等待句柄/pin 设计，不准空指针/扫描替代 |
| 6 | GenericInstantiation incremental/member family | 48 条高影响行：29 FIXED、17 REMAINING、2 UNSURE；`InstantiateForIncrementalPackage`、`RebuildGenericInstantiationManager` 仍精确缺失 | 从 incremental entry 与 member target 两个闭包拆分，逐 named dependency 拓扑推进 |
| 7 | CodeGen binary section info | `EmitPackageIR::GenerateBinarySectionInfo` BC 精确 REMAINING | 单点验证后可作为有界功能项派发 |
| 8 | CHIR source registration | `RegisterAllSources` BC 精确不存在 | 核调用时序与 source-id consumers 后派发 |
| 9 | annotation factory named chain | 8 条高影响：7 REMAINING、1 UNSURE；已有后续 annotation factory commits，但 exact names 仍缺 | 先核是否忠实重命名/拆分；未证明前不清账 |
| 10 | Sema Collector/TypeChecker named surface | Collector 高影响 25 条仅 2 FIXED、23 REMAINING；TypeCheckerImpl raw 数量更大但命名噪声高 | 以真实调用入口和复现为过滤器，禁止按 234 个 header 名盲目批量移植 |

已明确不是首攻项：3,217 条 LOW/REMAINING 中大部分来自 b14 selfhost helper invented-only 扫描；AST `Clone/Print/Node` 大族含大量 overload/每节点重复项。它们应先聚类和签名复核，不得压过上述功能项。

## 机械复核产物

未执行 `cjpm build`、编译器 build、bcgate 或 self-compile；未修改 `packages/`。本 chore 的校验只使用 grep/git/TSV 结构检查。

```text
INPUT_ROWS=8391
OUTPUT_LINES=8392 (header + 8391 data rows)
STATUS FIXED=615 PARTIAL=485 REMAINING=5635 OBSOLETE=624 UNSURE=1032 TOTAL=8391
SEVERITY BOOTSTRAP=2805 BC=1224 DIAG=609 LOW=3749 EMPTY=4 TOTAL=8391
FEATURE_DEBT_IDENTIFIER_LINKS=273
```

交付时 TSV 的 SHA-256：

```text
84a45fb56dbc1aae3db6e2017a0be9dbf1b686539ccacde8445842480208209f  gapscan_items_0711.tsv
```

本任务只生成账本和报告，没有新增/修改任何编译器函数、helper、类型或分支；因此无逐符号 C++ 新代码贴源项，也无平台分支移植项。无任何 grep 不到 C++ 出处的新编译器符号；未改业务源码绕过、未加 band-aid 吞 bug；撞到的系统根仅按 FEATURE_DEBT/BLOCKED 状态记账，未自行替代。
