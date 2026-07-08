# 自举完成路线图（ROADMAP to Full Bootstrap + BC 完全一致）

> 本文档定义"任务完全完成"的验收标准、当前基线、阶段计划与执行机制。
> 配套：`docs/STATUS.md`（当前状态）、`docs/CODEX_DELEGATION_PLAYBOOK.md`（派发手册）、`/tmp/audit/STATUS_ANCHOR.md`（session 台账）。
> 更新纪律：每合并一个根后更新"当前基线"表；阶段完成后勾选验收项。

---

## 一、终态验收标准（全部满足才算完成）

| # | 目标 | 验收命令 | 通过标准 |
|---|------|---------|---------|
| G1 | **BC 与 C++ 完全一致** | `python3 scripts/bcgate.py --self <cjc> -j 10` | differing **0**、byte-identical **2490/2490**、fully-identical samples **114/114**、compile-errors 0 |
| G1' | G1 严格复核 | 逐样本 `.bc` 全文件级 diff（**关闭** bcgate 的 hash 名字宽松归一化）+ `scripts/sc_bcgate.py`（自编译语料，多包 import 路径） | 双语料均零差异 |
| G2 | **自举闭环（A2-A4）** | stage2 = selfhost 编译 selfhost 全包并链接 cjc；stage3 = stage2 重复此过程 | stage2 可运行（`--version` 不 SEGV）；stage2 过 G3 全门；**stage3 与 stage2 产物逐字节一致（定点）** |
| G3 | **功能门全绿** | `bash scripts/difftest.sh -j 10`；smoke15 | difftest 114/114 MISMATCH=0 FAIL=0；smoke15 15/15（多包 import 语料，是 difftest/bcgate 对 import 回归盲区的唯一把关） |
| G4 | **宏自举** | macro_gate --self | 5/5（宏 .so 由 selfhost 编译并正确展开） |
| G5 | **完整性清账** | 审计清单 `/tmp/audit/`（1545 gap MANIFEST）+ `rg 'GAP_TODO|INVENTED' packages/` | 每条 gap 状态 = FIXED 或 显式记录的 BLOCKED/债（见第六节债表），无静默省略 |

**判据关系**：G1 是 G2 的前置（stage2 SEGV 是 codegen 分歧的症状，用户指令：bcgate 一致优先于 stage2 可运行性）。G1' 防 bcgate 宽松模式漏报。G5 防"语料没覆盖到"的暗缺口。

---

## 二、当前基线（2026-07-08，master @ 0b1e016d）

| 维度 | 数值 |
|---|---|
| 库包自编译（A1） | ✅ 18/18（+ cjc 驱动链接 = stage2 二进制 63MB） |
| difftest / smoke15 | 114/114 / 15/15 |
| bcgate | byte-identical **2381/2490（95.6%）**，differing **109**，fully-identical 46/114，compile-errors 0 |
| A2 stage2 | 链接成功，运行 SIGSEGV（**暂缓**，等 G1 功能分歧清净） |
| 宏自举 | 2/5；Layer A（decl 属性归一）已修；Layer B' 真根 = CPointer\<Unit\> 参数值 codegen 坍缩（objdump 实锤，在修） |
| 完整性 | 1545 gap 审计清单持续清账中；symdiff 核心桶（CHIR/CodeGen/Sema）已扫多批 |

**在飞任务**：cptrunit（G4 根）、whydiff9（G1 重排 118 differing）、forinconst（G1 最大簇 for-in 完整 ConstAnalysis）。

---

## 三、依赖关系

```
Phase 1  bcgate differing 118→0 ──────────┐
   (P1.1 for-in ConstAnalysis)            │
   (P1.2 whydiff 重排→逐根清)              ▼
   (P1.3 cosmetic 收尾)            Phase 3  A2 stage2 可运行
Phase 2  宏自举 2/5→5/5 (独立并行)          → A3 stage2 过全门
Phase 4  完整性清账 (独立并行,持续)          → A4 stage3 定点 = 自举完成
                                           ▼
                                   Phase 5  终验冻结 (G1'+G5 严格复核)
```

---

## 四、阶段计划

### Phase 1：bcgate differing 118→0（当前主攻）

**方法**：收敛循环 = whydiff 全量分簇重排 → 按样本数取最大功能簇 → 对照 C++ 定位根 → codex 忠实移植 → 独立门控+亲审 → 合并 → 重排。每合 2-3 根重跑 whydiff 刷新排名（根之间有遮蔽效应）。

- **P1.1 for-in `<main>` 残余（~20-28 样本，最大单根）**：interim ConstTerminatorAnalysis（81e9be0c）只折无 break/continue 的简单形；含 break/continue 的 delay-exit 需完整移植 C++ `CHIR/Analysis/ConstAnalysis.cpp`（格+全 opcode 转移）挂在已有 dataflow Engine 上，ConstPropagation 升级为全规则，块删除改 `funcsNeedRemoveBlocks` 集合限定（CHIR.cpp:495，同时清偿 81e9be0c 的包级删除债）。→ 在飞 forinconst。
- **P1.2 其余功能簇**：whydiff9 重排后逐根派发。已知候选（旧排名，待刷新）：Range.last lowering（~14）、for-keeping（~22）。每根一个 worktree、一个 codex、AGENTS.md 约束、独立 verify.sh full 门控。
- **P1.3 cosmetic 簇收尾**：纯块标号/命名序差异（whydiff 判 cosmetic 的）最后统一处理——多数源于 pass 顺序/临时编号分配序，须对照 C++ 的确切发号点修，不许改 C++ 侧或加归一化遮蔽。
- **P1.4 严格模式复核（G1'）**：differing=0 后关闭 bcgate 宽松归一化跑全文件 diff + sc_bcgate 自编译语料；暴露的 hash 名/多包差异按同方法清。

**风险**：ConstAnalysis 是 ~3000 行设计重移植，codex 发明风险高 → AGENTS.md + 诊断 spec（forincfg_diagnosis.md）+ 亲审"是否复用 Engine、opcode 全计数"。

### Phase 2：宏自举（独立并行）

- **B' 根**（在飞 cptrunit）：codegen 把 CPointer\<Unit\> 函数参数值按零大小 Unit 坍缩（已收窄到 MapCFuncParameters 零大小分支，对照 C++ `IsZeroSizedTypeInC`——C++ 里 CPointer\<T\> 恒 i8*，值不因 T=Unit 丢失）。验收：objdump 宏 wrapper 从 `movq $0x0` 变真实指针传递；macro_gate 2/5→提升；xcross 四象限 SELF .so 不崩。
- 修完 B' 后若 macro_gate 仍 <5/5：按同方法（gdb+objdump+四象限交叉编译）定位下一层，禁 band-aid 特判宏路径。

### Phase 3：自举闭环 A2→A4（触发条件：Phase 1 功能簇清零；cosmetic 未清不阻塞，SEGV 只可能来自功能性分歧）

1. **A2**：用清净后的 master 重编全包 → 重链 stage2 cjc → `--version`/`--help` 冒烟。若仍 SEGV：按 dupfn-corrupts-selfhost-binary 三步判别（同签名重复函数污染）→ runtime 初始化序 → TypeInfo 构造器（.ti 新发射路径），gdb 定位后回到 Phase 1 方法修根，**不做链接层 workaround**。
2. **A3**：stage2 cjc 跑 difftest 114/114 + smoke15 + bcgate（stage2 产物 vs C++ 参考，应与 stage1 结果一致）。
3. **A4**：stage2 编译 selfhost 源得 stage3，`cmp` 逐字节比对 stage2/stage3 全部 .a+cjc（剥离时间戳/路径类非确定性段后必须零差异；若有非确定性来源=真 bug，修根）。定点达成 = **自举完成**。

### Phase 4：完整性清账（独立并行，持续到 G5）

- symdiff 余桶（Sema 余/GenericInstantiation/Modules 余/CHIR 剩）继续按桶扫+移植；每桶产 FIXED/BLOCKED 对账（按 symbol）。
- 第六节债表逐条清偿。
- unittest-port 战役（C++ unittest → std.unittest）持续低优先推进，作为 G5 的行为级证据。

### Phase 5：终验与冻结

1. 全门一次性跑齐（G1/G1'/G2/G3/G4/G5），原始输出存档入 repo（docs/FINAL_ACCEPTANCE.md）。
2. 债表清零或每条余债有显式接受记录。
3. master 打 tag（如 `bootstrap-complete`），STATUS.md 定稿。

---

## 五、执行机制（已验证有效，不变）

- **派发**：`bash /root/cj_build/audit_persist/dispatch_codex.sh <worktree> <prompt.md> <log>` —— 自动投放 AGENTS.md 忠实硬约束（每轮自加载，禁发明/禁静默省略/BLOCKED=合格交付）+ git-exclude。worktree 必 `git worktree add -b fix/<name>`（禁占 master）。
- **诊断先行**：设计重的根（跨 pass 框架、ABI）先出精确 C++ 机制+file:line 的 spec 再派实现；spec 压制发明。
- **独立门控**：codex 自检不作数。合并前必由 orchestrator 跑 `bash /tmp/audit/verify.sh <wt> full <lane>`：difftest 114/114 + bcgate 非回归（byte-identical ≥ 当前基线且 compile-errors 0）+ smoke15 15/15。
- **亲审**：逐符号对照 C++ file:line 抽查忠实性；折叠/删除类改动必须引用 C++ 做该操作的确切 pass。不忠实 = 拒，带审稿意见换新路径 `fix/<id>_rN` 重派（勿复用被拒 worktree 路径，防 auth-poison）。
- **合并**：orchestrator 独占。ff-only（或 squash 单 commit）、作者 `Zxilly <zxilly@outlook.com>`、单行 semantic commit（feat:/fix:/chore:/chir:/codegen:）、禁 AI 署名、push origin master。bcgate 回归 = 绝不合。
- **并发**：正交任务全部并发（实际约束 = build-storm ~16 并发编译）；监控看日志 MTIME 非 tail。
- **节奏**：每次合并记 STATUS_ANCHOR（session 编号+bcgate 前后值）；bcgate 趋势是唯一进度主指标。

---

## 六、已知忠实债与风险表（G5 清账对象）

| 债 | 内容 | 清偿计划 |
|---|---|---|
| for-in 块删除 scope | 81e9be0c 用包级 UnreachableBlockEliminationForPackage，C++ 是 funcsNeedRemoveBlocks 限定（CHIR.cpp:495）；当前等价+非回归 | forinconst 落地时改 scoped |
| JoinAndMeet stub | sema 类型格 Join/Meet 简化实现 | Phase 4 对照 C++ JoinAndMeet.cpp 补全 |
| cjo text-scrape | cjo 元数据部分靠文本抽取而非结构化反序列化 | Phase 4，importmgr 战役后续 |
| CGTypeInfo MTABLE | MTABLE 相关 TypeInfo 字段未完整 | Phase 4，撞到即修（可能被 A2/A3 逼出） |
| pointer-identity（R-C） | Cut1-3 有界改+objectId 键 stand-in，未做 C++ 全量结构化 interning | 仅当 bcgate/自举被证明需要 Cut4 时升级 |
| CME utils used-set | addImportedDeclToCurrentPackage 与 C++ used-set 分离未做 | Phase 4 |
| parity 记账（A18 改名/B3C4 thunk/D7 keeptypes） | 0704 主动脉着陆时的具名 parity 债 | 随 P1.2 whydiff 簇逐个对上销账 |
| bcgate 盲区 | 宽松归一化遮 hash 名差异；单文件语料对 import 路径回归盲 | G1' 严格复核 + smoke15 常开 + sc_bcgate |
| sema 宽松接受重复函数 | 同签名重复函数静默接受会污染自举二进制 | A2 若 SEGV 按三步判别排查；Phase 4 补 sema 重复检查 |

---

## 七、里程碑核对清单

- [x] A1：18/18 库包自编译（2026-07-07）
- [x] bcgate ≥95%（2381/2490，2026-07-08；session44 whydiff9+valanalysis +9）
- [ ] 宏自举 5/5（Phase 2）
- [ ] bcgate 功能簇清零（Phase 1 主体）
- [ ] bcgate differing = 0（G1）
- [ ] 严格模式+sc_bcgate 零差异（G1'）
- [ ] A2 stage2 可运行
- [ ] A3 stage2 全门绿
- [ ] A4 stage3 定点 = **自举完成**（G2）
- [ ] 债表清零/显式接受（G5）
- [ ] 终验存档+打 tag（Phase 5）
