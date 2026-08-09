# cjcj 0.0.2 release runbook

状态：`WORKFLOW_WIRED_ENVIRONMENT_NOT_CONFIGURED`。release DAG 已采用“甲：一次构建、两段消费”：同一个候选 run 先完成 producer/package，人工复核该 run 的五个不可变 `pkg-*` artifact；publish job 在 `release-draft` environment 等待批准，批准后仍从该 `github.run_id` 下载并发布同一批 artifact，不再 dispatch 第二个 run。

仓库外还有一个启动前硬门：`release-draft` 必须先由仓库管理员配置 required reviewers，并开启 prevent self-review。2026-08-09 的只读现场结果是 `gh api repos/cjcj-dev/cjcj/environments` 返回 `{"total_count":0,"environments":[]}`。GitHub 对不存在的 environment 会自动创建一个**没有 protection rules** 的 environment，所以只写 workflow 名称不能冒充人工审批。完成 §1.2 的环境配置与机械检查前，禁止触发 0.0.2 候选 run。

本文不授权 push、tag、workflow dispatch 或 release 创建；这些外向动作只由主控执行。`draft` 输入及 `gh release create --draft` 逻辑没有改，0.0.2 仍只能创建 draft。

固定顺序：

```text
freeze → 环境门预检 → 单次候选 run（producer/package）→ exact artifact 复核 → 人工批准 → 同 run draft publish → 持久归档
```

任一步没有达到机械判据，状态立即变为 `STOP`，后续步骤不得开始。

## 1. 发布门结构

### 1.1 producer/package 失败传播

- `build` 仍用 `if: always()` 收齐五个平台 package 结论。
- `publish.needs` 直接列出 `source-final-std`、`windows-fixed-llvm-tuple`、`patched-cjpm`、`windows-runtime` 与 `build`。
- `publish.if` 使用 `always()` 后逐项要求上述五个 `needs.<job>.result == 'success'`，并保留 `!inputs.dry_run`。任一 producer 失败、取消或跳过时，其 result 都不等于 `success`，publish 在 job 条件处被跳过；任一 package matrix 格失败也使 `needs.build.result != 'success'`。

因此 `dry_run=true` 仍是纯演练，publish 必定跳过。0.0.2 最终候选使用一次 `dry_run=false` dispatch；在批准前，这个 run 的 producer/package 部分就是复核段，publish 因 environment protection rule 保持 waiting。不得先跑 `dry_run=true`、再跑 `dry_run=false` 并把前一 run 的复核冒充后一 run 的复核。

### 1.2 仓库 environment 是启动前硬门

管理员在 GitHub 仓库 Settings → Environments 创建 `release-draft`，至少配置：

1. 一个或多个 required reviewers；
2. `Prevent self-review`；
3. 建议关闭 administrators bypass；若未关闭，审批记录必须明确没有使用 bypass。

主控在 dispatch 前运行以下只读检查并把原始 JSON 放入版本持久证据目录：

```bash
export RELEASE_REPO=cjcj-dev/cjcj
export RELEASE_EVIDENCE_ROOT=/root/cj_build/ops/release_evidence/0.0.2

gh api "repos/$RELEASE_REPO/environments/release-draft" \
  > "$RELEASE_EVIDENCE_ROOT/release-draft-environment.json"
jq -e '
  [.protection_rules[]
   | select(.type == "required_reviewers")
   | select(.prevent_self_review == true)
   | select((.reviewers | length) >= 1)]
  | length == 1
' "$RELEASE_EVIDENCE_ROOT/release-draft-environment.json"
```

API 404、`jq` 非 0、reviewer 为空或 `prevent_self_review != true` 都是 `STOP-ENVIRONMENT`。不要靠运行 workflow 自动创建 environment；GitHub 官方语义是这种自动创建的 environment 没有 protection rules。

同一条断言也位于 publish job 的第一个 checkout 后步骤，且在 artifact download 与 `gh release create` 之前。即使有人违反 runbook 先触发 workflow，自动创建出的无保护 environment 也会在该步骤失败，不能继续发布。

### 1.3 同一 artifact 的机械绑定

- 五格在 `build-release-package.yml` 用 `actions/upload-artifact@v7` 各上传唯一 `pkg-<platform>`，并显式 `retention-days: 90`。人工审批的操作 SLA 是 30 天；超过 30 天一律拒绝本 run，90 天 retention 留足复核与事故取证余量。
- upload-artifact v4+ 的 artifact 不可原地修改；覆盖会产生新 artifact ID。复核记录固定每个 artifact 的 `id + name + digest + expired`。
- publish 使用 `actions/download-artifact@v8`，显式传 `repository: github.repository` 与 `run-id: github.run_id`，并只匹配 `pkg-*`。所以批准后下载源仍是当前候选 run，不存在第二次 producer 构建。
- 批准前必须再次抓 artifact 清单并与复核时的 TSV 字节比较；ID 或 digest 任一变化就拒绝批准。

## 2. 执行表

| 顺序 | 做什么 | 谁做 | 机械判据 | 失败信号与动作 |
|---|---|---|---|---|
| 1 · freeze | 在版本证据根写 `FREEZE.json`，固定 version、cjcj full SHA、runtime/LLVM pin、workflow ref、`draft=true`、`dry_run=false`。 | 主控 | 树干净；所有 SHA 为 40 位；JSON 与现场逐字一致。 | `FREEZE_FAIL`；写 STOP，禁止 dispatch。 |
| 2 · environment | 按 §1.2 配置并只读复验 `release-draft`。 | 仓库管理员配置；主控复验 | required reviewers 至少 1 个且 prevent self-review 为 true；JSON 已持久保存。 | `STOP-ENVIRONMENT`；当前现场就是此状态。 |
| 3 · 单次候选 run | 只 dispatch 一次 Release：`version=0.0.2,dry_run=false,draft=true`。等待四个 producer 与五格 package success；publish 应显示等待 `release-draft` 审批。 | 主控 dispatch；CI 执行 | run head SHA 等于 freeze；四个 producer success；五格 package success；publish 未开始任何 step。 | 任一 producer/package 非 success，或 publish 未等待审批即启动，为 `STOP-CANDIDATE`；拒绝本 run。 |
| 4 · exact artifact 复核 | 从该候选 run 抓五个 artifact 的 ID/digest，下载五包，验 sidecar checksum、内外 manifest、7 行字段与持久 ledger；复核结束再抓一次 ID/digest。 | 复核 lane；不得由产包 job 自批 | 五个规范名称各一；`expired=false`；前后 TSV `cmp` RC0；五包 checksum OK；内外 manifest `cmp` RC0。 | 缺格、ID/digest 漂移、checksum/manifest 失败均为 `STOP-PACKAGE-AUDIT`；拒绝审批。 |
| 5 · 批准并 draft publish | 复核人提交 exact run/attempt/head SHA、五个 artifact ID/digest、ledger SHA；required reviewer 只批准该 run 的 `release-draft` deployment。publish 从同一 `github.run_id` 下载后创建 draft，run 完结后归档 run/jobs/log。 | 复核 lane交证；required reviewer 批准；CI 发布 | 审批记录完整；download 与复核均绑定相同 run 和五个 ID；release 状态为 draft；最终证据 ledger 可复算。 | 拒绝/超时/bypass/非 draft/ID 不同为 `STOP-PUBLISH`；不得补跑另一套包。 |

## 3. 批准前 exact artifact 取证

持久目录仍使用：

```text
/root/cj_build/ops/release_evidence/0.0.2/
├── FREEZE.json
├── release-draft-environment.json
└── run-<run_id>-attempt-<attempt>/
    ├── artifacts.review.json
    ├── artifacts.approve.json
    ├── artifact-ids.review.tsv
    ├── artifact-ids.approve.tsv
    ├── artifacts/pkg-<platform>/...
    ├── PACKAGE_FILE_SHA256SUMS
    ├── run.json
    ├── jobs.json
    ├── logs/run.log
    └── EVIDENCE_SHA256SUMS
```

严禁使用 `/tmp`。publish 等待 environment 时 run 尚未 completed，现有 `scripts/archive_release_evidence.mjs` 的 dry-run 校验器会正确拒绝这种状态；因此批准前先保留 raw capture、artifact API JSON、ID/digest TSV 和逐文件 SHA。run 完结后再补 run/jobs/log 与总 ledger。该脚本仍只用于 `dry_run=true + publish=skipped` 的演练归档，不得拿它的演练结论替代最终候选证据。

批准前命令形状：

```bash
export RELEASE_VERSION=0.0.2
export RELEASE_REPO=cjcj-dev/cjcj
export RELEASE_RUN_ID=<the-single-candidate-run-id>
export RELEASE_RUN_ATTEMPT=<attempt>
export RELEASE_DIR=/root/cj_build/ops/release_evidence/$RELEASE_VERSION/run-$RELEASE_RUN_ID-attempt-$RELEASE_RUN_ATTEMPT

mkdir -p "$RELEASE_DIR/artifacts"
gh api --paginate --slurp \
  "repos/$RELEASE_REPO/actions/runs/$RELEASE_RUN_ID/artifacts?per_page=100" \
  > "$RELEASE_DIR/artifacts.review.json"
jq -e '
  [.[].artifacts[] | select(.name | startswith("pkg-"))] as $pkg
  | ($pkg | map(.name) | sort) == [
      "pkg-darwin-arm64",
      "pkg-darwin-x64",
      "pkg-linux-aarch64",
      "pkg-linux-x64",
      "pkg-windows-x64"
    ]
    and all($pkg[];
      ((.digest | type) == "string")
      and (.digest | test("^sha256:[0-9a-f]{64}$"))
      and (.expired == false))
' "$RELEASE_DIR/artifacts.review.json"
jq -r '
  [.[].artifacts[] | select(.name | startswith("pkg-"))]
  | sort_by(.name)[]
  | [.id, .name, .digest, .expired] | @tsv
' "$RELEASE_DIR/artifacts.review.json" > "$RELEASE_DIR/artifact-ids.review.tsv"
test "$(wc -l < "$RELEASE_DIR/artifact-ids.review.tsv")" -eq 5
test "$(cut -f2 "$RELEASE_DIR/artifact-ids.review.tsv" | sort -u | wc -l)" -eq 5
test "$(cut -f4 "$RELEASE_DIR/artifact-ids.review.tsv" | sort -u)" = false

gh run download "$RELEASE_RUN_ID" --repo "$RELEASE_REPO" \
  --pattern 'pkg-*' --dir "$RELEASE_DIR/artifacts"
(cd "$RELEASE_DIR" && find artifacts -type f -print0 | sort -z | xargs -0 sha256sum > PACKAGE_FILE_SHA256SUMS)
```

按五格逐一执行 sidecar `sha256sum -c`、流式读取包内 `RELEASE-MANIFEST.jsonl` 并与旁挂文件 `cmp`。准备批准时重新抓 API JSON，以同一个 jq 生成 `artifact-ids.approve.tsv`，然后：

```bash
cmp "$RELEASE_DIR/artifact-ids.review.tsv" "$RELEASE_DIR/artifact-ids.approve.tsv"
(cd "$RELEASE_DIR" && sha256sum -c PACKAGE_FILE_SHA256SUMS)
```

两条都必须 RC0。artifact API 清单中不是恰好五个唯一 `pkg-*`、任一 digest 空、任一 expired=true、或前后 TSV 不同，都拒绝批准。

## 4. 批准与发布后的收尾

required reviewer 在 exact run 页面选择 `release-draft`，核对 run ID、attempt、head SHA 与五个 artifact ID 后批准。GitHub 只有在 environment protection rules 通过后才让 publish job 开始；拒绝会令 workflow 失败。

publish 下载配置显式绑定：

```yaml
github-token: ${{ secrets.GITHUB_TOKEN }}
repository: ${{ github.repository }}
run-id: ${{ github.run_id }}
pattern: pkg-*
```

发布命令仍只在 `inputs.draft == true` 时加入 `--draft`；0.0.2 的 freeze 与人工核对都必须要求 true。run 完结后立刻抓最终 `run.json`、`jobs.json` 与原始 log，生成 `EVIDENCE_SHA256SUMS`。任何 artifact 到期、被删除或下载 digest mismatch 都应令 publish 失败；不得改成重新 producer。

## 5. 当前裁决

- 两个仓内结构缺口已接线：publish 直接检查全部 producer/package results；最终发布与人工复核绑定同一个 run 的不可变 artifact。
- 方案甲代价：五个 package artifact 跨 job 保存 90 天；最终候选 run 在人工批准前保持 waiting；需要仓库管理员维护 `release-draft` protection rules。
- 第三个同类缺口已经显式化：仓库当前没有任何 environment。workflow 已在下载/发布前 fail-closed；外部配置仍是运行 BLOCKER，§1.2 变绿前禁止发版。
- `draft:` 的默认值和发布命令语义未改；触发事件未改；本 lane 没有触发 workflow、tag、push 或 release。
