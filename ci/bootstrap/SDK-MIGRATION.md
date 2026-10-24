# Native SDK entry migration

The public path is `prepare-bootstrap-plans.mjs` → `sdk-build.mjs` →
`sdk-flow.mjs`. Native repositories still own their build and installation.
The existing `sdk_build.sh` and `gha_run.sh` names are forwarding shims only;
their remaining shell lines are tracked under cjcj#883. No receipt, directory
authority or alternate SDK scheduler is retained.

| Retired consumer or test | Current obligation and entry |
| --- | --- |
| `bootstrap.sh`, supplied stage1 and stage0 cache | `sdk-inputs`, `sdk-targets`, `sdk-flow` validate fixed sources, configuration and predecessor results; `sdk-resume*`, `sdk-pair-inputs`, `sdk-stage2-*` cover the applicable paths. |
| `sdk_verify.py`, SDK swap/std/runtime/shared-pair tests | `sdk-verify-install`, `sdk-flow` inventory/copies and `sdk-installed-macros`; native input libraries and ordinary installed compiler execution remain separate integration obligations. |
| `compiler_identity.py`, `test_compiler_identity.py` | `compiler_identity.mjs` CLI; `compiler-identity.integration.test.mjs` retains the frontend replacement rejection, independent compiler control and restoration. |
| `stage1_host_runner.sh`, its host/LLVM tests | `sdk-install-entries`, native-launcher and `sdk-host-inputs`; host and target loading are derived from the actual installed entries. |
| old srcbuild stage1/stage2 scripts | The existing native target stages and fixed private H1 adapter; `sdk-native-stage` retains trimpath before compiler cjpm execution. The mainline trimpath helper and pinned local mirror fixture are retained. Full adapter/ABI/layout/compiler execution remains a native integration obligation, not a script-only result. |
| `test/runtime_param_layout`, `test/macro_instance_stack` | Native startup owns the single loaded runtime. `test/macro_same_runtime` and `sdk-installed-macros` exercise the supported macro path; no second-runtime or CJ-side parameter-layout implementation remains. |
| old compose SDK/install tests | `package-install`, shared installed verification, archive extraction and repeated verification; no second assembly path. |
| `tools/srcbuild_kkk2.sh` | Existing `tools/srcbuild-kkk2.mjs` forwards the native configuration to the controlled box entry. |

The six frontend/macro consumer files are the complete fixed 02abc→1b
mechanism, including loaded-image/API checks, CJ plugin calls, flatbuffers import
lookup and the installed macro-server path. Script tests do not qualify newly
compiled CJ consumers, LSP child-process mode or CJ plugins.

The Linux host record and tool/stdx/cjpm source selections in this private
candidate are existing fixed input records. Other host platform records and the
generic host selection are retained. These edits do not publish mainline pins.

The standard-library final barrier still uses the existing output capture. Its
known `ERR_CHILD_PROCESS_STDIO_MAXBUFFER` failure is owned by the separate std
acceptance task; this migration neither bypasses that assertion nor claims full
std/SDK acceptance.

The private tools and cjpm selectors both select the reviewed complete source
`1b1f8d917781ff98ab6e81c08ff8704387d3db35`. Its object is not published at the
canonical URL; use the existing source mirror interface with the supplied local
object. An explicit or saved older tools selection still takes precedence and
must not be represented as this tuple. Use a separate workspace with the explicit
new selection for migration, preserving existing outputs.

The associated compiler `278a80e7b5426b4ba55ab9a6d8dcd18610b42912` and stdx
`c3066ac097166145765b274d7a4a79e43d70ffc8` are source candidates only. They are not
the installed C2 or newly qualified SDK inputs. This two-selector update does
not change the existing compiler/stdx selectors or authorize native production.

CI integration also retires `prepareColourSdk`'s pinned std archive,
`std-receipt`, `runtime-provenance` SDK.lock readers and `verify-resume-std`.
`prepare-colour-sdk.mjs` now configures actual native inputs, validates the native
target plan and runtime pin, runs the public native builder and consumes its
independent install. `colour-sdk.test.mjs` checks installed compiler bytes,
runtime mismatch, target loader selection and child exit forwarding through the
real wrapper. It is an entry apparatus, not native Cangjie production evidence.
Both native target families of the Linux runtime gate remain reachable; download
pin/local-cache tests remain even though this gate no longer downloads a legacy
language SDK. Full language, ABI and source checks remain in the native graph.

CI's existing official-tool audit is retained. The native launcher clears
inherited loader overrides, including LD_AUDIT; that audit cannot certify the
native descendants. Native installed-language/macro/library gates and the
separately recorded official execution closure remain required. No script result
or frozen source tuple supplies that production qualification.
