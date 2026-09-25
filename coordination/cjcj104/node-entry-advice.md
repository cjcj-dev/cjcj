LANE=sym_cjcj_104_implement_r5834555322
ROLE=implement
PROGRESS=WIP

# 范围/合同冲突请求裁决

冻结 cjcj origin/master=96e28e3dd5bfd96246a6636e4b5fbc757e9ea716，回读 rc=0。
经 wf_kkk2.sh sh 槽复现 /usr/local/bin/node 三次 rc=127；/usr/bin/node 同样三次 rc=127。
证据 /root/cj_build/reports/EVIDENCE-sym_cjcj_104_implement_r5834555322/reproduce.log。

输入探索报告 REPORT-sym_cjcj_104_explore_r5832867801.md 建议恢复 /media/kkk2/428602AC8602A111 -> /mnt/win 的软链或改三条管理软链；但本轮用户规则复用产物一律实体复制，唯一软链例外为 SDK 编译器入口。旧前缀整体恢复也会影响本任务外的消费者。

建议限本条范围：将既有 v20.19.0（sha256=34bc6627675906f8431892630b5e91fc4cc9f1e03ce15e9716025aa551e5c823）实体复制到稳定的 /usr/local/lib/node-v20.19.0-linux-x64，node 入口实体复制，npm/npx 如需入口用普通启动脚本指向完整包内 CLI。不改 cjcj 消费端，不碰共享 SDK。请裁决此方案，或明确管理入口软链是否授权例外；也可按 issue 正文仅交支持路径文档。

本项为主机 Node 装置，无 runtime SO/GC 相位。请确认按装置实际入口/MJS 执行证据验收，runtime 双构型、GC 三臂、SO 切刀与 entry_cut_check 不适用；候选交可复用维护脚本/文档 PR，红臂可在私有复制装置上验证，不破坏其他棒的已恢复入口。
