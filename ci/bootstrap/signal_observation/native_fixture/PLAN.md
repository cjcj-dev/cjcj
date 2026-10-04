待主控登记进 `/root/cj_build/ops/CURRENT_DOCS.manifest`。

# #473 native fixture 源码准备与后续配方草案

坐标基于 `8b9d9b79832965da76208b00f814aad65090a65f`。本目录仅源码准备，所有构建、离线资格测试、native 执行与产品观察均 NOT_RUN。不得由本草案自动触发。新增源码不继承旧 driver 的已审资格；两 Rejects 与累计额度不变。终态 Triage，由下一冻结核单独激活 build-only 和一次观察。

## 写集与生产链

`main.cj` 是独立 managed executable，导入完整正常构建的 `cjcj::utils`；其路径依赖为完整 `packages/utils` → 完整 `packages/basic`，不抽取旧 cjc 的 archive，不复制 Signal，不编译模型，不调用 MRT/CJ_MCC 私有入口。生产链：managed main → foreign `fixture_run` → 原生 `pthread_create(native_entry)` → 合法 seed → typed `CFunc<() -> Int32>` → 编译器生成的 N2C 桥 → `fixture_verify_seed` → 产品 `CreateAltSignalStack` → 正常返回 → pthread join。

CFunc 的非捕获 lambda 用当前产品 `packages/utils/src/Signal.cj:101` 的现支持写法，C 调用约定由 CFunc 生成；不是同名产品包装。`@C` 在现树 Signal:41/56 用于 ABI record，不能凭注解名杜撰另一桥。最终具体 callback wrapper/N2C 代码由官方 compiler 生成，**必须建后核验** C ABI、Int32 返回、wrapper 调用真实 Create。若此写法不能从 native pthread 正常进入 managed，记录停止，不改成 managed spawn、私有 MRT 调用或其他输入。callback 名不含 observer 匹配词，main 不执行 RunDriverMain 或早 Create。

`helper.c` 一个 pthread_create 调用，一个 callback 调用，没有重试、尺寸切换或 SS_DISABLE。posix_memalign 16 对齐、size65536；先实际 query rc0 且不 ONSTACK，seed flags0 安装，再 query 同 pointer/size 且非 ONSTACK/DISABLE。桥内另 query，验证 pthread_threadid_np 的同一 ID 与同一 seed；桥替换活动栈就停止，产品不会被调用。每次 sigaltstack 的 rc 与 errno 在打印前立即保存；pthread/posix API 保存直接返回错误码（它们不以 errno 判失败）。失败时不释放活动 seed；join 成功后才 free；join 失败保留内存直到进程退出。产品成功/自然 skip 由原 observer 决定，helper 的 callback rc0 只表示桥回来了，不代表 INSTALLED。线程退出前不解除活动栈。

## 输入闭包与身份义务

固定使用匹配官方 Darwin arm64 SDK 的 compiler/cjpm、完整 std 与实际官方 runtime/bounds；不重编 compiler/runtime/SDK，不替换工具，不使用染色 std/runtime。沿用已有锁/官方 SDK 实体及现有工具；不得把旧 runtime1a5 参照的来源认作本次 loaded 官方 SDK。精确官方 SDK version/archive sha、SDK.lock sha、编译工具 sha 与 compilation/process SDK 同源凭证必须在冻结 build 激活书中绑定；本轮未填的 template 字段是阻断状态，不能表示已核验。

闭包采集表（均须在产生时 capture）：

| 对象 | 必须留存 |
|---|---|
| 新源 | 新 candidate head、git bundle/archive hash；本目录所有源码/配置/配方 hash |
| 包 | fixture/utils/basic 三个实际 manifest；所有 .cj 源含编译器选择/排除清单；生成后的 lock；实际 cjpm verbose 参数 |
| std | 官方 SDK 全部 std archive/cjo/shared 库清单与 hash；实用 import 闭包（含隐式 core、runtime、collection、convert、env、fs、io、sync、unittest/testmacro 的构建期宏依赖） |
| native | helper.o 的 hash、完整 clang argv、Xcode SDK header hash；utils/basic foreign 清单对应 libsystem/实际依赖符号解析表 |
| wrappers | 全部生成 wrapper/cjo/archive/object 路径与 hash；含 fixture CFunc N2C、utils C2N sigaltstack 桥及所选 std 库；不能只列三个手工文件 |
| 入口 | 最终 Mach-O hash/UUID/file/otool/nm-defined 输出；unique Create 的符号及地址；callback→实际 N2C→产品的反汇编和 relocation |
| runtime | 实际 runtime/bounds 的绝对路径、hash、UUID、SDK 来源；最终 otool -L 的每个依赖（含实际 std/LLVM/zstd 若存在）及完整加载模块核对 |
| receipt | schema473-native-fixture-v1：fixture source head 与旧 observer source head 分开，compilation/process SDK 同源；不可冒用 retained cjc 的3bee hash |

机械导出：`rg -n '^import |foreign \{|^[[:space:]]*func ' packages/{basic,utils}/src`；manifest 递归查 dependencies；包构建日志/依赖图识别所有实际 std 包；`find <独立build目录> -type f` 的全清单与逐文件 shasum，列全 wrapper/库再分类，不能先筛到看得见的那几个。任何额外非标准 native 依赖若未在冻结书绑定即停止，不临时拼 shim/空实现。

## 一次 build-only 配方草案（尚未执行）

独立官方 macos-15 arm64 / Xcode16.4（16F6）job，SDK15.5；核与工具包络下一冻结书绑定。不修改旧 workflow，不复用旧大 job；不 dispatch 当前 workflow。后续编排可用一个新的显式 build-only 路由，观察路由默认关闭；路径选择/dispatch 本轮不实现。

1. `ulimit -c 0`；记录 uptime、uname、Xcode/SDK/clang/cjpm/cjc 的实体身份，核域与 wall。完整源码实体 cp 到本轮专用目录；官方 SDK 和完整 std/runtime 实体也 cp，不更改共享安装。保持 fixture 到 packages 的相对路径。receipt 编译 SDK 与运行 SDK 分栏，禁止默认指到别棒 sdk-host。
2. `xcrun --sdk macosx clang -arch arm64 -isysroot "$SDKROOT" -O0 -g -fno-lto -pthread -c <新fixture/helper.c> -o <独立out/helper.o>`，立即 `shasum -a 256`。无需运行 helper/calibrator/product。
3. 在副本中只生成独立包构建布局：以临时**manifest副本**指向完整 basic/utils 和 fixture，避免根 workspace 拉入全 compiler。fixture path 依赖仍按正常 cjpm 递归构建完整包，不截 Signal 文件；basic/utils 的实际 compile-option 均设 `-O0 -g`，根 override 同样，不加入 LTO。保存生成前后三份 manifest 的 diff/hash。需要 workspace 时只列 basic/utils/fixture 三包，不修改仓内共享 manifest。
4. 环境清空后显式传 HOME/TMPDIR/PATH、CANGJIE_HOME、DYLD_LIBRARY_PATH、SDKROOT、`SIGNAL_FIXTURE_HELPER_O=<绝对helper.o>`；使用固定官方 `SDK/tools/bin/cjpm build -j <冻结核数>` 的真实包入口。具体官方 SDK 的 option/manifest 能力由 build-only 核实，不重编工具；所有 native C 链入参按 `cjpm.toml` link-option 的对象实体，参考 `packages/cjc/cjpm.toml:13`，没有自写产品桥。记录实际 argv 并确认全链无 LTO、无裁剪 Create 符号。
5. 编译失败原样记 rc，不运行产品、不重试调配方。成功时立即 capture 所有产物 hash、真实 import/ffi 闭包；`nm` 读完整已定义符号（不是仅 nm-D），`otool -tvV/-L`、wrapper 反汇编证明唯一 Create/真实 N2C 和 malloc/query/install 路由。发现重复入口/内联后无法唯一定位则停止，不改 observer 算法。
6.填独立 build receipt 为 BUILT/build_rc0 **仅在原始证据支持时**；qualification.unique_product_entry/normal_n2c_bridge/no_lto 三字段须有证据引用，不能凭源码推断填 true。source_inventory/generated_wrappers/libraries/sdk_entities/manifests 各列实体 path/hash。尚无资格就 NOT_RUN/停止，不能把 build rc0 当桥合格。

两包 actual std/native 依赖并未在本轮构建验证；官方SDK兼容性、Int32 CFunc桥与 unique Create 都是冻结核的未闭合项。源码草案不是最终构建保证。

## 新 config/driver 离线资格计划（NOT_RUN）

`configure.py` 是**仅生成配置的独立 driver 草案**；不调用旧 reuse select，不调用 subprocess，不执行 LLDB。`observation.template.json` 和 `receipt.template.json` 的空字段不能直接观察。configure 的输入必须是上步实体与已审同源 calibration receipt，输出到新的独立目录，不覆盖 retained mapping/calibration/cjc；旧 observer 和 calibrate.c hash 在 source-identity.json。

下一冻结核独立批准离线测试时，建立一份有效最小 **synthetic** receipt/file 集（不得称产品证据），HOME显式存在且保持固定，测试如下差集；每个单独 filter，打印目标拒绝 reason，不被其他先验遮蔽：

| 变体 | 目标拒绝/断言 |
|---|---|
| 合法 receipt | config argv=[]、新binary/hash、selected131072、SDK path、runtime/bounds loader path、observer.argv 三段真实路由准确；launch次数恒0须对照 monkeypatch LLDB执行哨兵（任何启动即红） |
| 改 binary 实体一字节，保持其他先验 | binary-hash；恢复回绿，且目标断言执行到 |
| 改 modules runtime一字节，其他固定 | module-hash；同一输入恢复回绿 |
| receipt compilation/process SDK 单项异源 | sdk-mismatch；HOME存在，因此不是HOME先遮蔽 |
| observer 实体变/改其声明hash | observer-hash或observer-source 分别独立覆盖 |
| retained3bee hash、重复模块、旧argv--version、空wrapper、未BUILT | 各目标 retained-cjc/duplicate-module/argv[]不变量/missing-generated_wrappers/not-built，逐项覆盖 |
| 配置路由承重刀 | 切 configure.py 的 config.binary / DYLD_LIBRARY_PATH/ observer.argv 写入行，单项目标断言红，恢复同输入绿；只证明装置，不外推产品 |

此计划测试配置生成实际输出，不在旧driver已审结果上借绿。不声称已做切刀；无产品臂授权。未来离线验证还须核 source inventory 集合与 source head 匹配，以及模板中声明资格字段对应原始 hash/反汇编证据，configure 中的 true 检查本身不证明技术资格。

## 一次观察配方草案（另需激活，NOT_RUN）

固定同一成功 build-only 的 Mach-O 和闭包，不再构建。先只读核 SDK/source/observer/calibrator实体 hash与 receipt；使用已审 calibration layout，与实用 SDK header 绑定。不重新启动 calibrator（若布局无已审匹配证据，停止等冻结核）。configure.py 生成独立 config、input-receipt、observer.argv；保留新driver/source hash。观察前冻结完整 config及环境与唯一 native launch 额度，显式打印 input argv，禁止调旧 workflow 默认 job。

批准后仅一次 `/usr/bin/lldb --batch -o 'command script import <未改observer.py>' -o signal-observe`，`SIGNAL_OBSERVER_CONFIG` 指新config。外层timeout120秒，原observer110秒。不得自动补跑。运行时 helper query/seed/bridge receipts 逐行与 observer entry_thread_id/product query thread对位；bridge-query的同pointer65536须与产品query返回对位。最终动态 modules 路径/hash/UUID与 SDK/library receipt逐项核对（runtime/bounds/std/LLVM等实际加载者），不能只看 expected_libraries字段。只有一 product entry、query满足seed、安装实参131072且rc0、return同线程、main rc0、成功join 才有候选安装输入资格。任何 native/query/seed/bridge 失败、自然skip、模块异源、第二入口、observer非INSTALLED立即停止，留下原始日志/rc，不换线程/栈尺寸/fallback，不从helper rc0宣称安装通过。

输入规格三层分别留证：实用SDK `SIGSTKSZ/MINSIGSTKSZ` macro；实用libsystem sigaltstack的用户态 size检查/真实指令与模块UUID；绑定实用OS版本的XNU阈值及坐标。三者不互相替代。Signal.cj:13的注释不作为libsystem或内核真值。64KiB是否接受只能由这一次真实seed-install rc证明；旧8192不在本批，不从本输入预言其失败。不得GDB写内存/寄存器、SS_DISABLE、伪造errno或安装产品私有状态。

## 停止与角色

准备阶段不构建、helper/product启动、GHA、旧8192/cut/restore、release、最终Signal验收或PRMerge。build-only与观察皆NOT_RUN；产品闭环缺执行和因果段，不计通过。候选提交同原分支、PR489；固定8b9起点，本阶段不merge主线或改shared bootstrap/产品/observer算法。35分钟源码准备额度不重置旧额度，不预授25分钟运行。
