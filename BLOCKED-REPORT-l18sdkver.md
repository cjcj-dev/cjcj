# BLOCKED-REPORT: L18 CJ_SDK_VERSION compile-time injection

## Status

Correctly blocked on the missing build-to-source configuration facility. No compiler source change is included in this report commit.

During delivery checking, an unowned concurrent worktree edit appeared in `packages/codegen/src/EmitPackageIR.cj`, changing the local constant to `CANGJIE_VERSION`. It was absent from the initial `git status`, was not made by this task run, and is intentionally neither overwritten nor staged. As explained below, that edit deduplicates the current hard-coded value but does not supply the missing build-time injection facility.

L18 is not a codegen-IR emission gap: selfhost already emits `cj.sdk.version`. The missing facility is the C++ build-time definition chain that supplies the emitted string:

- `build.py:177-178` maps the release `--version` argument to `-DCJ_SDK_VERSION=<value>`.
- `CMakeLists.txt:10-12` declares the `CJ_SDK_VERSION` cache setting and its default.
- `CMakeLists.txt:195-197` turns that setting into the quoted C++ compile definition `CJ_SDK_VERSION`.
- `src/CodeGen/EmitPackageIR.cpp:48-52` initializes the translation-unit constant `CANGJIE_SDK_VERSION` from that definition, including the definition-absent empty-string branch.
- `src/CodeGen/EmitPackageIR.cpp:338-349` emits the value as the private, aligned, retained `cj.sdk.version` global.

The selfhost tree has no build configuration API or source-generation step that can expose a caller-supplied SDK version as a Cangjie `String` constant. Its workspace `cjpm.toml` contains only empty `compile-option`/`override-compile-option` fields. The installed compiler's `--cfg` facility supplies conditional-compilation conditions; it does not interpolate an arbitrary string into a declaration. Repository-wide searches find no generated build-config module or `CJ_SDK_VERSION` input.

`packages/basic/src/Version.cj:3` is not that facility: it hard-codes `"1.2.0-alpha.20260619020029"`. `packages/codegen/src/EmitPackageIR.cj:23-29` independently hard-codes the same value and explicitly records the missing injection mechanism. Replacing the latter with an import of the former would only deduplicate two hard-coded values; it would not mirror `build.py:177-178` or `CMakeLists.txt:195-197`, and therefore would be a forbidden plausible parallel implementation rather than L18's requested compile-time injection.

This dependency is outside the <=40-line proportional exception. The absent facility crosses the external build interface, workspace/package compilation, and source constant generation. There is no existing selfhost prerequisite API to wire, and inventing a CJPM wrapper or environment-variable runtime lookup would have no named C++ counterpart and would change compile-time semantics.

## Mechanical evidence

Exact source search:

```text
$ rg -n "CJ_SDK_VERSION|SDK_VERSION|CANGJIE_VERSION|VERSION_TAIL" . --glob '!build/**' --glob '*.{cj,toml,json,sh,cmake,txt,yaml,yml}'
./packages/modules/src/ASTSerialization.cj:12:import cjcj::basic.CANGJIE_VERSION
./packages/modules/src/ASTSerialization.cj:105:        let version = fb.CreateString(CANGJIE_VERSION)
./packages/conditional_compilation/src/ConditionalCompilationConfig.cj:3:import cjcj::basic.CANGJIE_VERSION
./packages/conditional_compilation/src/ConditionalCompilationConfig.cj:19:    public var cjcVersion: String = CANGJIE_VERSION
./packages/codegen/src/EmitPackageIR.cj:23:// GAP_TODO(sdk-version-injection): C++ derives this from the CJ_SDK_VERSION build macro
./packages/codegen/src/EmitPackageIR.cj:29:private let CANGJIE_SDK_VERSION: String = "1.2.0-alpha.20260619020029"
./packages/codegen/src/EmitPackageIR.cj:340:            versionCString = unsafe { LibC.mallocCString(CANGJIE_SDK_VERSION) }.asResource()) {
./packages/codegen/src/EmitPackageIR.cj:343:                    UInt32(CANGJIE_SDK_VERSION.size), 0)
./packages/basic/src/Version.cj:3:public let CANGJIE_VERSION: String = "1.2.0-alpha.20260619020029"
```

The reference compiler reports the official value shape:

```text
Cangjie Compiler: 1.2.0-alpha.20260619020029 (cjnative)
Target: x86_64-unknown-linux-gnu
```

Minimal static-library reproduction used `scripts/difftest_corpus/01_return.cj` with `--output-type=staticlib --save-temps`. Raw result:

```text
COMPILE ref_rc=0 self_rc=NA
/tmp/l18_ref/0-01_return.s:299:cj.sdk.version,@object        # @cj.sdk.version
/tmp/l18_ref/0-01_return.s:301:cj.sdk.version:
/tmp/l18_ref/0-01_return.s:302:cj.sdk.version:
/tmp/l18_ref/0-01_return.s:303:1.2.0-alpha.20260619020029
/tmp/l18_ref/0-01_return.s:304:cj.sdk.version, 27
```

`self_rc=NA` because this clean worktree has no prebuilt selfhost executable. No build was started after the blocker was established, because no compiler change exists to validate.

## Required restoration API

A dedicated build-configuration lane must provide the complete equivalent of the named C++ facility before L18 can resume:

1. A build input named `CJ_SDK_VERSION` accepting the full SDK string (for example `1.2.0-alpha.20260619020029`).
2. A deterministic build-time source/constant exposure API that makes that exact value available to Cangjie compilation as `cjcj::basic.CANGJIE_VERSION`, not a runtime environment lookup.
3. The C++ definition-absent behavior (`CANGJIE_SDK_VERSION = ""` at `EmitPackageIR.cpp:50-51`), or an upstream build invariant proving the selfhost input is always defined.
4. Workspace wiring so all packages consume one generated value, including `basic/Version.cj` and codegen's `CANGJIE_SDK_VERSION` source.
5. Reproducible rebuild invalidation when `CJ_SDK_VERSION` changes.

After that API is merged, resume this lane, replace the codegen hard-coded value with the supplied compile-time constant, compile the minimal static library, inspect `cj.sdk.version`, and run the full verify gate.

## Delivery audit

- Platform grep command:

  ```text
  rg -n "_WIN32|__APPLE__|__OHOS__|__linux__|#ifdef|#elif" /root/cj_build/cangjie_compiler/src/CodeGen/EmitPackageIR.cpp /root/cj_build/cangjie_compiler/src/Basic/Version.cpp /root/cj_build/cangjie_compiler/CMakeLists.txt
  ```

  Relevant raw output:

  ```text
  /root/cj_build/cangjie_compiler/src/Basic/Version.cpp:17:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
  /root/cj_build/cangjie_compiler/src/CodeGen/EmitPackageIR.cpp:48:#ifdef CJ_SDK_VERSION
  ```

  The missing `CJ_SDK_VERSION` supply chain has no OS-specific branch. Backend and definition-present/absent branches are identified above.
- Full-branch coverage: N/A because the missing build facility was not ported. The C++ constant initialization has all 2 preprocessor branches identified (`#ifdef CJ_SDK_VERSION` and `#else` at `EmitPackageIR.cpp:48-51`); neither was silently replaced with a hard-coded approximation.
- `/tmp/audit/verify.sh`: intentionally not run after the blocker was proven, because there is no compiler fix to validate and no selfhost executable in this clean worktree.
- No temporary instrumentation or generated test artifacts remain in the worktree.
- 无任何 grep 不到 C++ 出处的新编译器符号。
- 未改业务源码绕过、未加 band-aid 吞 bug。
- 撞到的缺失 named C++ 构建设施已 BLOCKED 上报、未自行替代。
