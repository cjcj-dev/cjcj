# C1/C2 修改前顺序表
坐标基于 35da7be2434ad72348ed27e8a0bf599ec4e91524。待主控登记进 `/root/cj_build/ops/CURRENT_DOCS.manifest`。

| producer | consumer | 修改点 |
|---|---|---|
| bootstrap-handoff.mjs:44–47 stage2 SDK | build-stage3.mjs:65 stage2 身份检查 | 保留 wrapper 与 ELF 分别绑定 |
| build-stage3 final std 安装 | common.mjs:88, tools.mjs:94, stdx.mjs:17 | stdx/tools执行前显式选共同SDK |
| 同一SDK和工具 | package.mjs:121–132 | 验证源后避免同目录删除覆盖 |
| bootstrap stage2 wrapper | build-windows-final-std.mjs:50 | 独立校验入口及producer，不要求realpath相等 |
| stage3 compiler | compose-sdk → srcbuild artifact → release package --binary | 具名最终compiler身份 |
| Windows seed W1 + cross std | native clean/build W2 → package --binary | 延续现有native生产配方 |

这是源码顺序，不是运行证据；细化承重点及三臂待实施。
