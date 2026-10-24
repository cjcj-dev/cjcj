# 有限夹具与真实安装门（TASK 2026-10-20 01:18）

正式147中的有限夹具不再冒充完整原生SDK。文本工具与小C ABI文件仅用于到达文件布局、来源、ABI或缺件拒绝；不写假的STAGE/BUILD事实，不把任意异常视为通过。`package-fixture.mjs`调用正式`build/cli.mjs package`，只接受具体缺失`STAGE-INPUTS.json`；Windows缺原生compiler仍拒绝。旧首失败保留在本lane r16/r17/r21原件。

| 原保证/测试 | 仍执行的有限断言 | 正向真实责任与当前状态 |
|---|---|---|
| source-build-parity：SDK/stdx归档名和根、九工具路径 | 正式package精确缺stage事实；真实archiveInstall及packageStdx生成/解包有限布局归档 | `source-build-installed.integration.mjs`正式package/verify核正式归档名、根、已安装工具及真实消费；NOT_RUN，缺完整install/config |
| compiler双入口、pcre相对链接，移走旧目录后独立 | 正式package保复制链接；archiveInstall停车旧目录、归档/解包并核实际链接/bytes | 同一真实installed门的ABI/path parity与停车原install后的消费；NOT_RUN |
| pcre/stdx链接独立于compiler别名 | 正式package保pcre；实际packageStdx和archiveInstall解包后读链接 | 同上，要求完整stdx真实安装；NOT_RUN |
| 原生必需路径缺失、恢复 | 真实C ABI控制只让正式CLI到达path parity，删/恢复模块路径精确拒绝/重新到达缺stage事实 | 真实installed门对完整SDK路径、ABI、hello/cjpm/宏、final std及安装事实；NOT_RUN |
| Linux仅排除指定Windows可选根 | 正式CLI精确路径反例，类似前缀仍拒绝 | 同上Linux目标真实正向；NOT_RUN |
| Windows完整target库/modules | 正式CLI拒缺原生cjc.exe；独立现役assertSdkPathParity保两类必需路径坏/恢复 | srcbuild-target.yml Windows原生producer→package-install→receive_native_sdk→verify_native_release及原平台验收；NOT_RUN；Linux有限门不替Windows |
| 额外外部链接 | 正式CLI在path parity精确拒绝，恢复后到达缺stage事实 | 真实installed门对完整目录的路径/解包隔离；NOT_RUN |
| Cangjie工具源码产物、默认/显式/原位/别名/复制 | 正式CLI保实际被选择目录、九工具launcher/retained products；缺任一工具拒绝；无stage事实拒绝 | 完整原生工具安装→installedInputs→真实installed门；NOT_RUN |
| compose-sdk-entry：stage3及local/GHA原始来源/run/parent/std、最终归档bytes | 正式compose配置缺失与实际installed stage缺失分别拒绝，无产物；已存在final-compiler.test/windows-final-compiler.test继续核来源/run/std/bytes | srcbuild-target正式package-install在真实stage3安装上产出final-compiler；真实installed门及release compose复核最终归档；NOT_RUN |
| Android list/single、OHOS/iOS各tuple component bytes与归档 | 正式compose接现役env接口，精确拒缺完整native SDK archive；真实archiveInstall运输每个component并核解包bytes | release.yml/compose-package→verify_native_release的实际cross集合、runtime来源、std内容→真实SDK归档/解包；按linux-x64-android、linux-x64-ohos、darwin-arm64-ios及targets其它适用平台分别NOT_RUN |

原正向义务未删除。`ci/test-registry.json`保留真实installed门的manual登记。该门要求`SOURCE_PARITY_INSTALLED_CONFIG`指向私有、同目录完整install及真实officialSdkRoot；不能用H、现成N、组件归档或这些有限fixture替代。release原生包必须由唯一srcbuild producer交实际归档，按正式workflow传`NATIVE_SDK_ARTIFACT_DIR/NATIVE_SDK_INSTALL_DIR/RELEASE_PLATFORM/RELEASE_KEY/CJCJ_NATIVE_SDK_VERSION/CJCJ_RELEASE_SOURCE_SHA/RUNTIME_REF/FINAL_STD_DIR/CROSS_STD_DIR/CROSS_STD_ARTIFACTS`执行compose。各平台所需集合由targets与workflow实际声明，单一Linux手动门不授其它平台。

截至本次变更，主控确认没有合格完整SDK供体；原R081包GC崩溃和完整SDK缺件保持。本清单不新增资格记录或通过章；有限147变绿也不授原正向验收、合并、stage/GHA或发布。

TASK 2026-10-20 01:39：固定SDK042cb九工具producer/layout、raw与install事实、readiness、package及release消费者完整接入CI后继。新增cjlint/cjprof/cjcompat的公开package缺件拒绝只授有限接线；真实九工具正向仍缺最终SDK，不能用SDK owner并行cjprof独立产物替代其它八项。`verify-target-tools.integration.mjs`保留manual登记，等待完整九工具install及真实per-tool业务探针。

Native cjlint/cjprof/cjcompat consume ordinary producer/install facts and actual artifacts; no CJTOOL stamp is fabricated for their C++ bodies. Existing Cangjie lineage dye scope stays intact. The finite native-tool-install test checks nine launcher bodies, while its dye rejection assertion applies to the existing Cangjie-bearing tool set; this manual fixture does not qualify the real native producers. The installed positive gate now compares all nine public tools after unpacking.
