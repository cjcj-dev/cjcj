# cjcj 0.0.2 release runbook

状态：`EXECUTABLE_THROUGH_AUDIT`。固定顺序和证据政策已经确定；当前 workflow 还不能把“已复核的 dry-run 原包”交给一个人工批准后才运行的 draft publish job，因此在第 5 步必须停住，直到主控完成本文“发布门现状”所列接线。本文不授权 push、tag、workflow dispatch 或 release 创建；这些外向动作只由主控执行。

固定顺序只有这一条：

```text
freeze → producer → dry-run（完成即归档）→ 抽包复核 → 人工批准 draft
```

任一步没有达到机械判据，状态立即变为 `STOP`，后续步骤不得开始。失败信号必须写进该版本的持久证据目录，不能只留在 Actions 页面。

## 1. 发布门现状（2026-08-09 现场核验）

### 1.1 已经成立的部分

- release 的五个平台矩阵是 `.github/workflows/release.yml:76-102`；`fail-fast: false` 在 `:80-91`，所以五格都会给出各自结论，不会因第一格失败而失去其余格证据。
- publish 直接 `needs: build`（`.github/workflows/release.yml:104-107`），而它的 `if: ${{ !inputs.dry_run }}` 不含 `always()/failure()/cancelled()` 等状态函数。GitHub 会隐式应用 `success()`；因此 **五个平台 package build 任一失败或跳过，现有 publish 已不会运行**。GitHub 官方语义见 [Defining prerequisite jobs](https://docs.github.com/en/enterprise-cloud@latest/actions/how-tos/write-workflows/choose-what-workflows-do/use-jobs#defining-prerequisite-jobs) 和 [Status check functions](https://docs.github.com/en/actions/reference/workflows-and-actions/expressions#status-check-functions)。
- dry-run 时 publish 由 `.github/workflows/release.yml:107` 跳过；`draft` 输入默认 `true`（`:21-25`），真正创建 release 时 `:129-133` 才把它翻译成 `gh release create --draft`。

### 1.2 尚未成立的两处；未接线前禁止 draft

1. **“任何 producer/package 格失败都不得 publish”尚未完整成立。** `build` 直接依赖四个 producer，但使用 `if: always()`（`.github/workflows/release.yml:76-79`），会打断 producer 失败向后的默认跳过链；publish 又只直接 `needs: build`（`:104-107`）。若 producer 在已上传可消费 artifact 后的后续步骤失败，而五个 package job 仍成功，publish 没有直接检查 producer 的 result。
   - 主控需要改的位置：`.github/workflows/release.yml:104-107`。把四个 producer 与 `build` 都列为 publish 的直接 `needs`，并在 `if:` 中显式要求每个 `needs.<job>.result == 'success'`，同时保留 `!inputs.dry_run`。本 lane 按禁区没有修改它。
2. **没有“复核 dry-run 原包后人工放行”的执行点。** dry-run 在 `:107` 永久跳过 publish；改为非 dry-run 重新 dispatch 会从 `:48-102` 重建另一套 artifact，而不是发布刚刚抽包复核的那套。`draft: true` 只是创建形式，不是审批门。
   - 主控需要接在 `.github/workflows/release.yml:104-109` 的 publish job 前：受保护的 `release-draft` environment，或一个只消费指定 dry-run `run_id + run_attempt`、复验 `EVIDENCE_SHA256SUMS` 后发布的独立 job/workflow。批准人必须在 exact run 的归档与抽包结果产生后才批准。未完成此项时，不得用“再跑一次非 dry-run”冒充第 5 步。

以上是现有 workflow 与 G17 的真实结构冲突，不用一份假装能跑通的操作文字掩盖。

## 2. 五步执行表

| 顺序 | ① 做什么 | ② 谁做 | ③ 判据（可机械检查） | ④ 失败了怎么办 / 怎样知道失败 |
|---|---|---|---|---|
| 1 · freeze | 在 `/root/cj_build/ops/release_evidence/0.0.2/FREEZE.json` 固定版本、cjcj full SHA、runtime/LLVM pin、workflow ref 和 `draft=true`；只允许干净且已提交的树。 | 主控 | `git status --porcelain` 为空；`git rev-parse HEAD`、`ci/runtime_pin.env` 的 `RUNTIME_REF`、`ci/llvm_pin.env` 的 `LLVM_SHA` 都是 40 位小写十六进制；`jq -e` 复核 `FREEZE.json` 与现场逐字相等。 | 任一值为空、非 40 位、带 `-dirty`、树不净或后续 run 的 `head_sha` 不同，信号即 `FREEZE_FAIL`；在版本根写 `STOP-FREEZE.md`，不得启动 producer。 |
| 2 · producer | 主控以 freeze 的 workflow ref、`version=0.0.2`、`dry_run=true`、`draft=true` dispatch **一次** Release；CI 运行 `source-final-std`、`windows-fixed-llvm-tuple`、`patched-cjpm`、`windows-runtime`。producer 定义在 `.github/workflows/release.yml:48-74`。 | 主控 dispatch；CI 执行 | 四个顶层 producer job conclusion 全为 `success`；五份 final std artifact 存在；Windows LLVM tuple、cjpm、runtime artifact 存在。run 的 `head_sha` 必须等于 freeze SHA。 | Actions job conclusion 为 `failure/cancelled/timed_out/action_required`、artifact 缺失或 `head_sha` 漂移就是具体红信号；记 job URL，状态 `STOP-PRODUCER`，不得把已有的部分 artifact 送入下一棒。 |
| 3 · dry-run + 立即归档 | 同一个 run 的五个平台 package job 执行；publish 必须是 `skipped`。run 一完成立刻按 §3 抓 run/job URL、原始合并日志、五份旁挂 manifest 和五份 checksum 到持久目录，然后运行 `collect` 与 `verify`。 | CI 产包；归档 lane 或主控抓取 | run `status=completed/conclusion=success`；除 `Publish release` 外所有 job 都是 `success`；五个 `<platform> / Build release package` 各恰一个；`Publish release` 恰一个且 `skipped`；归档工具输出 `ARCHIVE_EVIDENCE_OK ... manifests=5 checksums=5`。这些检查由 `scripts/archive_release_evidence.mjs:90-152,248-330,363-416` 实施。 | 任一非 publish job 不是 `success`、五格不齐、publish 不是 `skipped`、log 为空、URL 缺失、manifest/checksum 缺失或工具非 0，就是 `STOP-DRY-RUN`；保留失败 run 的 URL/日志，不得进入抽包复核。 |
| 4 · 抽包复核 | 五格各取该 run 的唯一 package archive，不解压落盘地验证 checksum；流式读取包内 `RELEASE-MANIFEST.jsonl`，与旁挂 manifest 字节比较；复核每份 manifest 的 7 行字段形状。 | 主控指定的复核 lane；不得由产包 job 自批 | Linux/Darwin 四包的 `sha256sum -c *.tar.gz.sha256` 与 Windows 包的 `sha256sum -c *.zip.sha256` 都输出 `OK`；`tar -xOf`/`unzip -p` 的内嵌 manifest 与旁挂文件 `cmp` RC0；归档再次 `verify` RC0。字段真值来自 `build/lib/release-manifest.mjs:127-195`，非本 runbook 自创。 | checksum 输出 `FAILED`、内外 manifest `cmp` 非 0、7 行缺失/重复/字段空、归档 ledger 漂移，任一个就是 `STOP-PACKAGE-AUDIT`；写明 platform、命令、RC 和原始输出，拒绝批准。 |
| 5 · 人工批准 draft | 复核人把 exact `run_id/run_attempt/head_sha`、归档目录、`EVIDENCE_SHA256SUMS` 自身 SHA-256、五格复核结果交给主控。主控只批准受保护环境或只消费该 exact run artifact 的 publish；创建必须保持 `draft=true`。 | 复核 lane提交证据；主控独占批准与外向动作 | 审批记录含批准人、UTC 时间、exact run URL、attempt、head SHA、归档 ledger SHA、`draft=true`；发布执行点在运行前机械复验这些值；GitHub Release 创建后状态是 draft，非 published。 | 今天的 workflow 没有这个执行点，机械信号是 §1.2 两项仍为 open；状态保持 `READY_FOR_DRAFT_APPROVAL_BUT_BLOCKED`，**不得** dispatch 非 dry-run、push、tag 或手工拼另一套包。审批拒绝/超时同样停止。 |

## 3. dry-run 后立即归档

### 3.1 持久目录约定

唯一根目录：

```text
/root/cj_build/ops/release_evidence/0.0.2/
├── FREEZE.json
├── .capture/
│   └── run-<run_id>-attempt-<attempt>/
│       ├── run.json
│       ├── jobs.json
│       ├── run.log
│       └── artifacts/pkg-<platform>/...
└── run-<run_id>-attempt-<attempt>/
    ├── ARCHIVE_INDEX.json
    ├── EVIDENCE_SHA256SUMS
    ├── run.json
    ├── jobs.json
    ├── urls.tsv
    ├── logs/run.log
    ├── manifests/cjcj-0.0.2-<platform>.RELEASE-MANIFEST.jsonl
    └── checksums/cjcj-0.0.2-<platform>.<tar.gz|zip>.sha256
```

选择 `/root/cj_build/ops/release_evidence/` 是因为它是主控持久运维域、与 Git checkout 和 runner artifact 生命周期解耦；严禁 `/tmp`。工具在 `scripts/archive_release_evidence.mjs:63-69` 对 `/tmp` fail-closed。每次 run/attempt 使用新目录，工具拒绝覆盖已有 destination（`:248-259`）；原始输入与规范化归档分开，便于复算。

### 3.2 抓取与校验命令

以下命令只读 GitHub；`RELEASE_RUN_ID` 和 `RELEASE_RUN_ATTEMPT` 由主控从刚完成的 dry-run 填入。不要使用旧 run 代替。

```bash
export RELEASE_VERSION=0.0.2
export RELEASE_REPO=cjcj-dev/cjcj
export RELEASE_RUN_ID=<dry-run-id>
export RELEASE_RUN_ATTEMPT=<attempt>
export RELEASE_EVIDENCE_ROOT=/root/cj_build/ops/release_evidence/$RELEASE_VERSION
export RELEASE_CAPTURE_DIR=$RELEASE_EVIDENCE_ROOT/.capture/run-$RELEASE_RUN_ID-attempt-$RELEASE_RUN_ATTEMPT
export RELEASE_ARCHIVE_DIR=$RELEASE_EVIDENCE_ROOT/run-$RELEASE_RUN_ID-attempt-$RELEASE_RUN_ATTEMPT

mkdir -p "$RELEASE_CAPTURE_DIR/artifacts"
gh api "repos/$RELEASE_REPO/actions/runs/$RELEASE_RUN_ID" > "$RELEASE_CAPTURE_DIR/run.json"
gh api --paginate --slurp "repos/$RELEASE_REPO/actions/runs/$RELEASE_RUN_ID/jobs?per_page=100" > "$RELEASE_CAPTURE_DIR/jobs.json"
gh run view "$RELEASE_RUN_ID" --repo "$RELEASE_REPO" --log > "$RELEASE_CAPTURE_DIR/run.log"
gh run download "$RELEASE_RUN_ID" --repo "$RELEASE_REPO" --pattern 'pkg-*' --dir "$RELEASE_CAPTURE_DIR/artifacts"

node scripts/archive_release_evidence.mjs collect \
  --source "$RELEASE_CAPTURE_DIR" \
  --destination "$RELEASE_ARCHIVE_DIR" \
  --version "$RELEASE_VERSION"
node scripts/archive_release_evidence.mjs verify \
  --archive "$RELEASE_ARCHIVE_DIR" \
  --version "$RELEASE_VERSION"
```

成功只有一个信号：两次命令均 RC0 且各自打印一整行 `ARCHIVE_EVIDENCE_OK`。工具还会把归档中除 ledger 自身外的每个文件写入 `EVIDENCE_SHA256SUMS` 并在复核时重算（`scripts/archive_release_evidence.mjs:332-360`）；多文件、少文件、改字节都非 0。

### 3.3 完整性范围与 manifest 形状

归档缺以下任一类都失败：

1. run 元数据和 run URL；
2. 完整 jobs 元数据和每个 job URL；
3. 非空原始 workflow log；
4. 五个平台各一份旁挂 `RELEASE-MANIFEST.jsonl`；
5. 五个平台各一份 archive checksum；
6. 规范索引和全文件 SHA-256 ledger。

manifest 校验严格跟随 `build/lib/release-manifest.mjs:127-212`：每行必须有 `schema=1`、`platform`、`component`、`source.repository/source.commit`、`artifact.path/artifact.sha256`、`embedded_stamp`；当前 writer 生成 7 个唯一 component 行。`unavailable: reason` 和 `no-stamp` 是 writer 的显式值，不能擅自删行或用空串替代。

## 4. 时限规则

- 仓内最短显式期限是 final std 7 天（`.github/workflows/srcbuild.yml:250-256,287-294`）与 Windows runtime 7 天（`.github/workflows/build-windows-runtime.yml:126-132`）；LLVM tuple 与 cjpm 是 14 天（`.github/workflows/platform-tuples.yml:134-140`、`.github/workflows/build-cjpm.yml:130-136`）。
- package artifact 在 `.github/workflows/build-release-package.yml:360-370` 没有单独 `retention-days`，run log 也不是固定“7/14 天”；二者服从仓库/组织 retention policy。GitHub 官方默认是 90 天且可配置，单个 artifact 可以另设更短期限，见 [Removing workflow artifacts](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/remove-workflow-artifacts) 和 [Managing GitHub Actions settings](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository#configuring-the-retention-period-for-github-actions-artifacts-and-logs-in-your-repository)。
- 操作 SLA 不是“第 7 天前有空再做”，而是 **dry-run completed 后立即归档**。长 run 中先产生的 7 天 artifact 已经开始计时，且 run/artifact 可以被有权限者提前删除；不能用名义 retention 当缓冲。
- GitHub 的 run-log 下载链接本身只短时有效，原始内容必须复制到持久目录；官方 REST 说明见 [Download workflow run logs](https://docs.github.com/en/rest/actions/workflow-runs#download-workflow-run-logs) 与 [Download job logs](https://docs.github.com/en/rest/actions/workflow-jobs#download-job-logs-for-a-workflow-run)。

## 5. 归档工具正负对照

测试必须把 fixture 放在持久目录而非 `/tmp`：

```bash
RELEASE_EVIDENCE_TEST_ROOT=/root/cj_build/llt_artifacts/relrunbook \
  node --test build/test/release-evidence.test.mjs
```

`build/test/release-evidence.test.mjs:49-110` 先构造五格齐全的假 run 并要求 collect RC0；随后复制归档、故意删除整个 `logs/` 类，再要求 verify 非 0 且错误含 `missing raw workflow log`。这就是缺类阳性对照，不是只测 happy path。

## 6. Q18 答案与 G17 状态

- Q18 的执行顺序、停损信号、证据种类、归档位置、时限和完整性判据已经由本文固定。
- G17 的证据归档部分已闭合；package-grid→publish 的现有失败门已核实成立。
- G17 整体仍为 `PARTIAL`，只剩 §1.2 两个 workflow/外部审批接线项。它们属于主控外向动作禁区；在完成并用一次真实 exact-run 审批证明前，不得宣称 `MET`。
