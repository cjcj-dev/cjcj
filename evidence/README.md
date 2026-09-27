# 发布持久证据路径政策

发布版本的持久证据根只由 cjcj 仓 `ops/coord/RELEASE_0_0_2_RUNBOOK.md` 中的 `RELEASE_EVIDENCE_ROOT` 定义。按该 runbook 归档发布批准记录、environment JSON 与门证据；本文件不另设根路径。

`$RELEASE_EVIDENCE_ROOT/GATE_EVIDENCE.json` 是版本根下的门证据索引。`gates` 中的路径相对于该根解析，例如 `G12: gates/G12`、`G14: gates/G14`；门脚本 `ci/release-gates.mjs` 从 runbook 读取根，再读取索引。索引路径不得越出版本根。

`/root/cj_build/evidence/<campaign_id>/` 是 `ci/generate-freeze.mjs` 的默认 campaign 输出位置，可通过 `--evidence-root` 指定父目录。每个 campaign 目录新建且不可覆盖，保存该次冻结身份；它不替代跨 campaign 的版本持久根。当前冻结身份的选择按 runbook 执行，已有证据不搬迁、不删除。

- 证据不放 `/tmp`：本机 `/tmp` 是 tmpfs，重启即失。
- 证据产物不入 git；本政策文本入 git，便于审查与追溯。
- `srcbuild-diagnosis-*` / `pkg-diagnosis-*` artifact 最短保留期为 7 天，过期前须复制到 runbook 指定的版本持久根，并保留来源及校验值。

本文件也是 `/root/cj_build/evidence/README.md` 的部署来源；该位置仅存本政策副本，不定义另一套路径规则。
