目标：忠实移植 FlatBuffers Builder 写 runtime 的实际使用子集，完成 round-trip 与官方字节对照。
已落 commit 清单：0d81fae5（公共包迁移、consumer 切换、round-trip/官方 byte probe、报告）。
下一步：提交后由 orchestrator 将 modulefmt_r3 与 CHIR 写侧统一切到 cjcj::flatbuffers 公共 Builder。
