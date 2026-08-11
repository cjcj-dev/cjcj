# 五平台 release dry-run 执行政策

状态：`POLICY_READY / EXECUTION_UNBLOCKED_PENDING_USER_APPROVAL`（0811 06:1x 主控翻）。

> 解阻依据（逐条可复现，`reports/REPORT-execstate.md` 是全表）：
> 五条顺序契约 + 两条失败证据 **7/7**，且每条另行直读 workflow YAML 核对，不只看测试是否通过。
> `ci.yml:53-64` 把 `ci/test-manifest.mjs` 的清单喂给 `node --test`（`-ge 26` 地板），该 step
> 无 `continue-on-error`、无 `|| true`；清单第 23 行含 `phase-control.test.mjs`。逐字跑该步：
> 128 tests / 128 pass / rc=0，七条契约名全部出现在输出里；阴性对照（查一个不存在的
> `policy contract 6`）0 命中，证明匹配不是恒真。CI 侧对应 run `2cec8f5b`（27 文件，48s）。
>
> ⚠ **口径陷阱**：`ci.yml` 里现在**看不到** `phase-control.test.mjs` 这个字面量（已改为清单驱动）。
> 按“文件名是否出现在 workflow 里”去查会得到**错误的否定**。正确判法是三段组合：清单含它、
> workflow 消费清单、该 step 不可 `continue-on-error`。
>
> ⛔ **状态是“只差用户批准”而不是“可执行”**：政策自己规定所有 GitHub Actions 动作都是外向动作，
> 必须先取得用户批准。解阻解掉的是技术前置，不是那道闸。

本文只定义执行政策，不授权 workflow dispatch、rerun、cancel、push、tag、draft 或 release。所有 GitHub Actions 动作都是外向动作，必须由主控先向用户取得批准。

0.0.2 的最终候选发布另走 [`ops/coord/RELEASE_0_0_2_RUNBOOK.md`](../coord/RELEASE_0_0_2_RUNBOOK.md)：它固定 `draft=true,dry_run=false`，在同一个 run 内复核 artifact 后等待人工批准。本文的五平台演练固定 `dry_run=true`，不得拿演练 artifact 冒充候选发布 artifact。

## 1. 当前事实与版本边界

### 1.1 `required_reviewers` 不挡纯 dry-run

`release.yml` 的 publish 条件显式要求 `!inputs.dry_run`，而 `release-draft` environment 只挂在 publish job 上（`.github/workflows/release.yml:225-247`）。所以 `dry_run=true` 时 publish 在 job 条件处跳过，五个平台 producer/package 不进入 environment，也不会等待 reviewer。

publish job 内的 `required_reviewers` 查询是对仓库 environment 配置的二次断言，不是 dry-run job 的前置条件。三条 reviewer 路径仍列在 §8，但它们只决定 `dry_run=false` 的候选 draft 如何过门。

### 1.2 分阶段 DAG 与失败取证已经就位

旧版政策识别出的两个装置缺口已经在今天的 master 上闭合：

1. `.github/workflows/release.yml` 以五个具名 package job 固定 §3 顺序；Phase N 的 source/package 通过 `needs` 等待 Phase N-1 package 成功。source workflow 接收单个 `targets`，不会在 Phase 1 尚未报告时预启后续昂贵 source build。
2. `.github/workflows/build-release-package.yml` 的 Unix/Windows smoke 只在成功时清理 workspace，并用 `if: failure()` 上传逐平台 `pkg-diagnosis-*`；`.github/workflows/srcbuild.yml` 继续上传逐 target `srcbuild-diagnosis-*`。
3. `ci/srcbuild/tests/phase-control.test.mjs` 静态锁定五条顺序契约和两条失败证据契约，并由 `ci/test-manifest.mjs` 接入 `ci.yml` 的不可吞错测试 step；`.github/workflows/needs-semantics-probe.yml` 单独测量 `needs` 的 skip 语义。

因此本文不再把 phase control 或 failure capture 列为执行前代码阻塞。剩余阻塞是外向执行尚未得到用户批准，以及具体 campaign 的 freeze/身份门尚未产生。

### 1.3 0.0.2 保持 `SHA_ONLY`；attestation 属于 0.0.3

0.0.2 的 `RELEASE_SIGNATURE_POLICY` 固定为 `SHA_ONLY`。理由不是拒绝 attestation，而是忠实记录当前可验证状态：五个平台 archive 尚未在获批 campaign 中产生，所以没有五份可验证的 GitHub attestation 对应物。把 manifest 先写成 `GITHUB_ATTESTATION` 会使 G16 从“政策值唯一且可计算”退回“缺五平台实证、不可计算”。

旧 `relpolicy` 补丁使用 `actions/attest-build-provenance@v4`，它只在真实 package job 运行时为 exact archive 产生对应物；本地 Node 测试只能证明 wiring，不能替代五个平台签发与 `gh attestation verify`。因此旧 workflow、权限、manifest 值和验证文案不进入 0.0.2。

attestation 移到 0.0.3：只有五平台获批 campaign 能逐包生成、验证并按 freeze 绑定 repository/workflow/ref/head SHA 后，才可把唯一政策从 `SHA_ONLY` 升为 `SIGNED`（或项目最终采用的等价枚举值）。若同时引入经审核 SBOM，则使用 `SIGNED+SBOM`。不得以默认关闭但 manifest 宣称已签的方式提前升级政策。

## 2. 冻结与启动门

每次政策 run 有一个不可变的 `campaign_id = <full-head-sha>-<UTC>-<sequence>`。主控在任何 dispatch 前把以下内容写入持久证据根的 `FREEZE.json`：

- repository、workflow ref、40 位 cjcj head SHA；
- runtime、LLVM、compiler、tools、stdx 的精确 pin；
- version、`draft=true`、`dry_run=true`，以及 `runtime_ref` 是否为空；
- orchestrator 文件 SHA-256、policy 文件 SHA-256；
- 获批的用户指令或审批记录标识；
- 本次版本的唯一签名政策；0.0.2 必须是 `SHA_ONLY`。

启动判据全部满足才是 `GO-0`：工作树/待合提交已确定；workflow ref 可达 frozen head；所有 commit pin 是合法 full SHA；静态 workflow 测试和 YAML/actionlint 通过；持久证据目录新建且为空；没有另一个相同 campaign 正在运行。

dispatch 后第一项取证是 run JSON。`head_sha != FREEZE.json.head_sha`、`event != workflow_dispatch`、inputs 不等于冻结值、run attempt 不唯一，任一项都是 `STOP-IDENTITY`，立即停止且不读后续绿灯。

## 3. 五平台唯一顺序

| Phase | 平台 | 为什么排在这里 | 本格 `GO` 的最低条件 |
|---:|---|---|---|
| 1 | `linux-x64` | 约 34 分钟的已观测失败前缀；覆盖共享 source-build 主链、x86-only 判据，并顺带产生 Windows cross final std，单位成本信息量最高。 | §4 第 0–2 层全绿；package/smoke/manifest/checksum 全绿，manifest 唯一政策为 `SHA_ONLY`。 |
| 2 | `linux-aarch64` | 已观测失败前缀约 32 分钟；尽早验证不同架构与 arm runner，而成本远低于冷 Darwin。 | 同上；明确记录 x86-only probe 的预期 skip，不能伪装为 pass。 |
| 3 | `windows-x64` | 复用 Phase 1 的同代 cross final std；覆盖 Windows runtime、MinGW/LLVM tuple、PowerShell、ZIP 与 cjdb。已观测冷成本高于 Linux、低于 Darwin x64。 | Windows runtime/tuple/export、cross std、ZIP checksum、manifest、smoke 全绿。 |
| 4 | `darwin-arm64` | 已观测 compiler oracle 失败前缀 1:35:28；先验证 Apple/arm64、Python 3.12 和 dylib，再支付最贵的 Intel 冷编译。 | Python 3.12 选择、Darwin loader/LTO/static-lib 正臂、package/smoke 全绿。 |
| 5 | `darwin-x64` | 冷缓存 `Build compiler oracle` 已实测 3:02:55，是最贵单格，只有前四格把共享问题排净后才值得启动。 | 全部门全绿；随后才允许形成五格 dry-run 结论。 |

时间依据是 `/root/cj_build/reports/REPORT-citime.md:37-69`。这些是失败路径观测，不是成功时长承诺，只用于排序。

## 4. 分层停损：先判身份，再读业务结果

任何 `STOP-*` 都要求 phase DAG 阻止后续 phase，并让已开始的当前 phase 完成失败证据上传。不得为了“收齐五格”继续启动更贵平台，也不得用 rerun/cancel 绕过未获批外向动作边界。

### 第 0 层：身份与装置

这一层不绿，后续所有结果都建立在错误产物上，禁止继续判读。以下任一形状在任一格出现，都是全 campaign `STOP-IDENTITY`：

- checkout/head SHA、任一 source pin、runtime override 与 `FREEZE.json` 不同；
- `assertFrozenStamp` 报 occurrence 不等于 1、`-dirty` 或 frozen SHA mismatch；
- base SDK / gate apparatus 的 archive SHA、host runtime SHA、platform 或 reviewed apparatus 不匹配；
- `ABI_PAIR=MISMATCH`；
- LLVM tuple manifest 缺 `llc`/`opt`、SHA/version/loader 不符；
- final std artifact 名与 `final-std-<exact-platform>` 不同、缺失、来自其他 run，或 Windows cross tuple 回填数量任一为 0；
- manifest 缺 core component、存在 unresolved/旧 `unavailable:`、artifact SHA 非 64 位，或发现的 Cangjie tool population 为 0；
- manifest 的 `signature_policy` 不唯一、为空或在 0.0.2 不等于 `SHA_ONLY`。

### 第 1 层：编译期判据

只有第 0 层全绿才读这一层：

- `TESTS_MANIFEST` 三个数（今日实测 `configure=1 manual=15 orphan=5`，21 条条目）必须满足**三条不变量**，
  任一不满足即 `STOP-CONTRACT`，不能只认 `PASS`：
  1. `configure >= 1` —— 配置期那道负编译门还在跑；
  2. `configure + manual + orphan == 21` —— **没有条目静默消失**（这才是“覆盖面没缩水”的真判据）；
  3. `orphan <= 5` —— 欠债不增长。
  ⛔ **不要写成 `manual == 15` 这类等式**：把一个 orphan 接上 runner 会让 `manual` 变 16、`orphan` 变 4，
  那是**改进**，而等式判据会把它判成契约违反。一道把还债当违约的门，只会让人不还债。
- `SLOT_TYPE_PROBE` 必须是 `control=1 witness=1 negatives=5`，五个负臂都必须“拒绝且诊断到预期 symbol”；错误拼法编过、control 不编过、或因无关错误失败，均为 `STOP-CONTRACT`。
- Linux x64 的共享 compiler/runtime/stdx/stage1/2/3 任一确定性编译或测试失败为 `STOP-SHARED-BUILD`，后四格不得启动。
- Linux AArch64 的架构编译/测试失败为 `STOP-LINUX-ARM64`；Windows 的 cross runtime/export/PowerShell/ZIP 失败为 `STOP-WINDOWS`；Darwin arm64 的 Python 选择、compiler、loader/LTO 失败为 `STOP-DARWIN-ARM64`；Darwin x64 任一失败为 `STOP-DARWIN-X64`。

### 第 2 层：产物判据

- x86 格 `STAGE3_WRITE_BARRIER_PASS` 还必须有有效 population；`bypassed>0`、`INDETERMINATE` 或没有判读对象均为 `STOP-WRITE-BARRIER`。AArch64 的明确 `reason=probe-is-x86-only` 是记录为 `EXPECTED-SKIP`，其他 skip 不是绿。
- `PROVENANCE.txt` 必须存在，五个字段 `BUILT_BY_CJC/BUILT_WITH_SDK/COLOURED/PREFLIGHT_C2/GENERATIONAL_POST_BARRIER` 都必须逐项归档；`ARTIFACT-SHA256` 不能为空，且 packaged std 每个已发现产物都必须被其覆盖。
- archive 外部 `.sha256` 必须 RC0；archive 内外 `RELEASE-MANIFEST.jsonl` 必须字节相同；manifest 中每个 artifact path 必须从解包目录复算 SHA-256。
- package smoke、cjdb bundled Python import/session、Darwin LTO static-lib 正臂任一红，停止在本格。
- 0.0.2 不要求 attestation，也不得把缺 attestation 记成失败；其真实政策是 `SHA_ONLY`。
- 0.0.3 若启用 `SIGNED`，`gh attestation verify` 对本格 archive 必须 RC0，且 signer repository/workflow/ref/head SHA 与 freeze 一致；缺失或身份不符为 `STOP-ATTESTATION`。

### 第 3 层：已知 report-only

`provenance` 或 `emitpop` 的 report-only 只在 `FREEZE.json` 已逐项登记预期状态、population 非 0、实际计数不比冻结值退化时允许继续收集后续格；它们必须把 campaign 标为 `YELLOW`。出现新的 unresolved 字段、population=0、计数下降、或 report-only 变成 apparatus error，都是 `STOP-REPORT-ONLY-DRIFT`。

`YELLOW` dry-run 可以完成取证，但不能自动升级为 0.0.2 draft 候选；是否接受/闭合由主控另行裁决。

## 5. 基础设施红与重试上限

只有以下证据明确指向 GitHub/runner 基础设施而非仓库输入时，才允许同格重试一次：hosted runner lost、GitHub artifact/cache service 5xx、已记录的 rate limit、网络下载服务 5xx。编译错误、测试断言、SHA/manifest/stamp mismatch、OOM、timeout、磁盘满都不自动归为基础设施红。

重试规则：

1. 先完成失败 attempt 的 §6 归档，再建立新的 `attempt-<n+1>` 目录；不得覆盖旧目录或日志。
2. head SHA、pins、workflow SHA、inputs 必须与 freeze 完全相同；否则不是重试，而是新 campaign，从 Phase 1 重来。
3. 只重跑当前红格及其必需 producer；后续格仍不启动。
4. 同一形状第二次出现即确定性 `STOP-REPEATED`，禁止第三次“碰碰运气”。

## 6. 逐格证据、位置与保留期

持久根固定为：

```text
/root/cj_build/ops/release_evidence/dry-runs/<campaign_id>/
├── FREEZE.json
├── campaign-events.jsonl
└── run-<run_id>-attempt-<attempt>/
    ├── run.json
    ├── jobs.json
    ├── artifacts.json
    ├── artifact-ids.tsv
    ├── logs/run.log
    ├── logs/job-<job_id>-<platform>.log
    ├── cells/<platform>/
    │   ├── archive + archive.sha256
    │   ├── RELEASE-MANIFEST.external.jsonl
    │   ├── RELEASE-MANIFEST.embedded.jsonl
    │   ├── PROVENANCE.txt
    │   ├── GATE-APPARATUS.json
    │   ├── PYTHON-BUNDLE.json
    │   ├── attestation-verify.txt  # 0.0.3 SIGNED campaign only
    │   └── failure/...
    └── EVIDENCE_SHA256SUMS
```

每格无论绿红都保留：run/job URL、job ID、起止时间、结论、原始未改日志、artifact API 的 ID/name/digest/expired、producer 与 package 制品、外部 checksum、内外 manifest、PROVENANCE、smoke/cjdb 输出。失败格还必须保留第一个原始错误前后日志、完整 stack/stderr、step summary、部分 `dist`、未清理的 smoke workspace、source stage diagnostics 和 sccache error/stats；不能只留最后一行通用 `Error 2`。

归档时限与保留期：

- sccache error artifact 现有 retention 只有 1 天，所有 raw log/API/diagnostic 必须在 run 结束后 24 小时内复制；source final std/diagnosis 多为 7 天，tuple/cjpm 多为 7–14 天，`pkg-*` 是 90 天。这些只是抢救窗口，不是政策保留期。
- 持久根中每个成功、失败和重试 attempt 都保留到 0.0.2 正式发布或明确放弃之日起至少 365 天；安全事件或争议中的 campaign 不得按期删除。
- `scripts/archive_release_evidence.mjs` 用于 completed 的纯 dry-run collect/verify，并生成 `EVIDENCE_SHA256SUMS`；脚本拒绝 `/tmp`。

并发卫生是硬门：一个 run/attempt/job ID 一个新目录和一个日志文件；先写该目录内临时文件，再原子改名。禁止多个进程用 `>` 写同一路径，禁止把 `run.log` 当共享追加管道。任何人不得删除 campaign root、别人的 run 目录或仍被进程持有的目录；到期清理由证据 owner 按 exact ledger 目标单独执行并留下删除记录。

## 7. 一格红后的恢复 DAG

恢复接在 `releasewire` 已闭合的 producer → exact-platform artifact → package DAG 上，不允许跳边：

| 红点 | 允许的最小恢复前置 | 禁止复用 |
|---|---|---|
| checkout/pin/stamp/apparatus/ABI 身份红 | 修复后产生新 full SHA、重写 freeze、从 Phase 1 新 campaign 开始。 | 旧 campaign 的任何 producer/package artifact。 |
| native source SDK/final std 红 | 同 frozen SHA 的基础设施重试可只重跑该 source 格；代码修复则新 campaign。必须先重新得到 exact `final-std-<platform>`。 | 红格的 partial final std、其他平台 std。 |
| Windows final std 红 | 重跑它的 Linux x64 stage2 host + Windows cross producer，验证同代 runtime/MinGW；再跑 Windows package。 | 其他 run 的 Linux host compiler 或 Windows std。 |
| LLVM tuple/runtime/cjpm/hle producer 红 | 对应 producer 先绿，artifact name/digest/sidecar 校验后才可恢复 consumer。 | 手工复制、同名旧 cache payload、缺 sidecar 二进制。 |
| package download/compose/manifest 红 | 所有同平台 producer 保持同 run、未过期且 digest 未变；重新从 download contract 开始该 package 格。 | 红 package 的 partial archive。 |
| smoke/cjdb 红；0.0.3 另含 attestation 红 | producer digest 不变时可重跑完整 package + verify（0.0.3 再加 attestation）格；不得只重跑失败命令后手工上传。 | 未经过完整 package job 的修补 archive。 |

任何修复改变代码、workflow、pin 或输入，旧 campaign 只能作为失败证据，不能与新 campaign 拼成“五格绿”。五格结论必须来自一个 frozen identity 下、按 §3 顺序完成的受控 campaign。

## 8. `release-draft` reviewer 三条路的代价（不代主控选择）

| 路径 | 代价与边界 |
|---|---|
| 甲：配置 environment 加 reviewer | 需要仓库管理员配置并长期维护至少一名非自审 reviewer，候选 run 会占用 waiting 状态；优点是保留 0.0.2 draft 的人工停点。 |
| 乙：临时移除守卫 | 需要同时审计 workflow 与仓库 environment、事后恢复并证明窗口内无人误发；`dry_run=false` 期间会扩大意外 publish 面，风险和审计成本最高。 |
| 丙：只跑不需要守卫的格 | 对 `dry_run=true`，当前实际是四类 producer 加五个 package 格全部可跑、publish skipped，并非只能跑部分平台；代价是完全没有验证 reviewer waiting/approval/draft publish 路径，不能替代最终候选 run。 |

因此，纯五平台 dry-run 不需要在甲/乙/丙中解除一个“reviewer 阻塞”；只有随后进入 `dry_run=false,draft=true` 候选时，主控才必须向用户请示并记录选择。

## 9. 0.0.2 draft、0.0.3 attestation 与正式版边界

0.0.2 只能创建 draft。draft 创建前必须已有且复核通过：五个平台 archive、每包 `.sha256`、包内外 manifest、PROVENANCE/component lineage、五格 smoke/cjdb，以及唯一 `SHA_ONLY` 政策。0.0.2 不以愿望值冒充签名，不要求尚不存在的 attestation，也不得在 release note 给出本版可用的 attestation 验证命令。

0.0.2 不提供 CycloneDX/SPDX SBOM，release note 应如实说明；这不把政策提升为 `SIGNED+SBOM`。0.0.3 若引入 attestation，必须在五平台 package job 中默认启用且逐 archive 可验证，才可改为 `SIGNED`；若再引入 SBOM，必须绑定 exact archive digest 并通过 schema/license/source-pin 审核，才可改为 `SIGNED+SBOM`。

正式版不得重建或替换 draft 的 archive。只能把同一组已复核 artifact 从 draft 提升；checksum、manifest 或（0.0.3 起）attestation subject digest 任一变化都必须废弃 draft、重新 freeze 并从 Phase 1 开始。

## 10. 收口状态

只有同时满足以下条件才允许写 `DRYRUN=PASS`：用户明确批准外向执行；同一 freeze 下按顺序 5/5 `GO`；没有未解释的第 0–2 层红；全部原始证据已进持久目录且 ledger 复算通过。

否则只能写具体的 `STOP-*`、`YELLOW` 或 `NOT_RUN`，不得用“总体可接受”“大体通过”替代。
