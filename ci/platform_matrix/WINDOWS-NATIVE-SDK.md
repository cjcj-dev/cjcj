# Windows native SDK producer interface — WIP

Owner: `impl_platform_delivery_1018`. CI owns the final shared workflow/matrix.
The existing Linux `windows-x64` cross std component remains separate. No Windows
native build, language result, official runner dispatch or complete SDK package
has been executed by this change.

## Fixed sources and providers

|Input|Fixed source / actual retained provider|Remaining production|
|---|---|---|
|LLVM N|db51a4c7ebb6903e9f997d3b35d52f3577810385; local read-only object `/root/cj_build/llvm_rebase`, tree53dd7bc91e55122c781b8d9caf34155de4cb38cc|Windows native LLVM/cjdb/shim installation and original BUILD-INPUTS|
|Runtime and std R|79b34798d0f4696f9fe5a3708981539466ecd35b; clean donor `sym_cjcj_llvm_105_implement_r5898373141/runtime`, treea2724e06e7d3cbe3df7cd2e04bcb676a5be99aba|Windows runtime/bounds/shared/static, then native std through the SDK graph|
|C++ compiler / AST|new private9e26e5a989c9c4b2210a7aff7ad60c1c94bb028d, treec57c7a8f08a5d742d7ea831da53c7af14793fe92; parent174db8f40d5efddee63c47a3162bbf676bc227a0|schema flatc suffix fixed under TASK18:00. N and AST must both rebuild from this new source, pending independent review and actual native production|
|Official host H|1.3.0-alpha.20260925001050, Windows x64 ZIP, 268606563 bytes, SHA256904e1a7147c156b84afe03c2c01c0392a29267ae53a3847d3589e03cff96999d|Archive already retained on kkk2; Windows extraction and real execution remain|
|H1 / compiler|H1 1553645ac50f72ba58712843255313250869cbbc; platform compiler packages remain C08148651dc2aeee42eae161eca98d83a5cdb4935|Native H1/compiler/std normal rebuild; no Linux C2 reuse|
|full stdx|c3066ac097166145765b274d7a4a79e43d70ffc8, managed fixed Git source already on data|Native full target graph/build/install and original STDX-BUILD-INPUTS, not sdk-tools subset|
|six tools / HLE|Existing SDK owner supplies the fixed tools/cjpm selectors and HLE successor; original 1b1f8d917781ff98ab6e81c08ff8704387d3db35 source is not renamed as a later selector|All six native outputs and original tool build inputs. Node22.23.3 Windows x64, same five-package npm lock, and newly built Windows cjbind with matching target libraries; Linux HLE bundle is not a Windows provider|

Host ZIP is retained at
`kkk2:/mnt/cjcj-data/impl_platform_delivery_1018/host-providers/windows_x86_64/cangjie-sdk-windows-x64-1.3.0-alpha.20260925001050.zip`.
Its observed unpack size952673187B is an input measurement, not a build peak.

## Existing production entry chain

1. Official `windows-2022`/`windows-2025` runner, real Windows x64 Node, MSYS2
   MINGW64/MSVCRT clang, CMake>=3.29, Ninja/make, sccache. Native source/dependency
   checkouts are private. C++ commands use sccache; neither a Linux job nor
   renaming a COFF object establishes native Windows qualification.
2. Runtime entry remains `zx ci/platform_matrix/build_runtime.mjs`. Set the real
   `RUNTIME_SOURCE`, `PLATFORM_CI_ROOT`, `RUNTIME_REF=79b34798d0f4696f9fe5a3708981539466ecd35b`,
   `LLVM_SHA=db51a4c7ebb6903e9f997d3b35d52f3577810385`,
   `CJCJ_NATIVE_RUNTIME_REF=79b34798d0f4696f9fe5a3708981539466ecd35b`, `CJCJ_NATIVE_HOST_VERSION=1.3.0-alpha.20260925001050`,
   `NATIVE_RUNTIME_PLATFORM=windows_x86_64`, `RUNTIME_NATIVE_PAIR=1`,
   `RUNTIME_TARGET=windows-x86_64`, actual `RUNTIME_VERSION`, `SCCACHE_PATH`, and
   `MSYS2_BASH`. This invokes R's public build.py build/install via MSYS2. Its
   independent `runtime-install` receives the actual staged bounds DLL,
   original shell argv/rc, source materialization, installed hashes, SOURCE_SHA,
   RUNTIME-INPUTS and NATIVE-INPUTS. There is no synthesized Linux CPP status.
3. N's existing entry is `node ci/bootstrap/native-cjdb.mjs <native-cjdb.json>`:
   actual fixed C++ compiler/LLVM/runtime/bounds/flatbuffers/Python/xml2 paths,
   `platform=windows_x86_64`, paired `commits`, native cc/cxx and sccache feed
   CMake→lldb/all/install→Python checks→selfhost shim→BUILD-INPUTS. AST's normal
   `cangjie-ast-support`/flatbuffers/schema installation must complete before
   its descriptor is supplied. The `flatc.exe` source successor above is explicit;
   no successful native build record is fabricated here.
   The subsequent native producer emits `BUILD-INPUTS.astInstallation` from its
   actual CMake target/install and carries the unedited cache/install manifest.
   See `../bootstrap/NATIVE-AST-INPUTS.md`. CI must consume the normal
   `lib/windows_x86_64_cjnative/libcangjie-ast-support.a` path and explicit C++
   repository/commit in its shared GHA entry; the old flattened reader is still
   pending that integration. This producer increment does not declare it closed.
4. `CJCJ_NATIVE_INPUTS=<descriptor> CANGJIE_WORKSPACE=<private workspace>` feeds
   `node ci/bootstrap/prepare-bootstrap-plans.mjs`, followed by
   `node ci/bootstrap/sdk-build.mjs --config <workspace>/build-targets.json --no-package`.
   Descriptor explicitly sets llvmCommit/runtimeCommit/stdlibCommit to Ndb51/R79b,
   and astCommit to9e26e5a989c9c4b2210a7aff7ad60c1c94bb028d. The original N
   BUILD-INPUTS.commits.compiler must equal that AST source; old N/174db facts
   cannot be relabeled as the new pair. It also supplies
   the Windows host, fixed source paths and actual N/R/AST build/install records.
   The existing scheduler produces H1→bootstrap std→C2→final std→C3 and an
   independent installation. `.compiler-exec` and target libraries stay distinct.
5. Public `build/cli.mjs --target windows-x64` selects the native execution
   adapter only on win32/x64. Supply actual native dependency directories in
   `CJCJ_NATIVE_LLVM_BIN` and `CJCJ_NATIVE_OPENSSL_LIB`, and the installed compiler
   through `CJCJ_SRCBUILD_CONSUMER_SDK`. Full stdx uses `build stdx`; the fixed SDK
   tools implementation retains `--tools-phase build|install|all`, fixed
   selectors, six original producer outputs, and target HLE dependency facts.
   CI must preserve that implementation when applying the platform delta; this
   lane's older tools stage is not an alternative SDK tools scheduler.
6. CI's existing `ci/srcbuild/steps/package-install.mjs` consumes the same install
   via `packageInstall`: actual installed hello/macros/final std, original input
   manifest, ZIP, original root made unreachable, clean unpack and repeated
   consumption. Windows uses fileURLToPath for the relocated Node entry and PE
   import/export tables for the existing ABI check. `packageConsumption`'s
   EXECUTED value selects a required branch; it is not a result before that
   branch runs. CI must add the full sourceBuild cell/artifact only with this
   whole producer dependency closure; stdProducerFor alone is insufficient.

## Source composition and current permission

Required existing SDK code is reused from fixed CI
aca347a88a2030d69f1f05cf02020a8bf73febfe; std platform/stage shape comes unchanged
from SDK3551f4788fe0e3217bd30ad2e6b0574382b0cd29. These source inputs are not a
new complete SDK qualification. The original 3966 Windows slice is reused as
source evidence only. Old2eabe/25fe review objects remain frozen.

Current allowance: data total13GiB including retained inputs, script gates
8cores/8GiB/core0 through box+wf. No new stage/GHA/dispatch/deployment. Complete
Windows native peak disk/RSS is UNKNOWN. Proposed native work needs an official
runner with >=64core stage capacity or an explicit controller capacity ruling,
plus separate native build disk allowance; current script budget is insufficient.
The platform owner retains N/R/AST/host/HLE/full stdx/cross/Windows production,
installation and package responsibility while these exact prerequisites close.
