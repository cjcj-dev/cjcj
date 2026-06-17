# CodeGen llvm-ffi Deepening Status

Date: 2026-06-17

Build: `cjpm build` passes.

Reference inspected:

- `/root/cj_build/cangjie_compiler/src/CodeGen/IRBuilder.{h,cpp}`
- `/root/cj_build/cangjie_compiler/src/CodeGen/CGModule.{h,cpp}`
- `/root/cj_build/cangjie_compiler/src/CodeGen/CGContext.{h,cpp}`
- `/root/cj_build/cangjie_compiler/src/CodeGen/DIBuilder.{h,cpp}`
- `/root/cj_build/cangjie_compiler/src/CodeGen/IRAttribute.h`
- `/root/cj_build/cangjie_compiler/src/CodeGen/CGFunction.cpp`
- `/root/cj_build/cangjie_compiler/src/CodeGen/CJNative/CJNativeIRBuilder.cpp`
- LLVM C API headers installed under `/usr/include/llvm-c-20/llvm-c`

Implemented in this pass:

- Expanded the LLVM C API surface into CodeGen-owned component files:
  `LLVMAnalysis.cj`, `LLVMBitcode.cj`, `LLVMPassBuilder.cj`, and `LLVMTargetMachine.cj`.
- Added bindings for verifier/function analysis helpers, memory-buffer bitcode and IR reading, bitcode memory/FD
  writing, target/target-machine/data-layout APIs, target-machine emission APIs, and the new pass-manager
  `LLVMRunPasses` API. These are external LLVM bindings only; LLVM is not reimplemented.
- Added resource-style wrappers for LLVM memory buffers, pass-builder options, target-machine options, and target
  machines so future callers can use the same `try (...)` ownership shape used elsewhere in the self-hosted port.
- Extended the core LLVM binding with source-file-name access, module printing, metadata strings, builder
  insertion-before support, basic-block insertion before another block, fast-math flag application, and safe
  LLVM-message-to-Cangjie-string conversion.
- Matched more C++ `CGModule` behavior by adding the `CJBC`, `Cangjie_OPT`, and macOS `Cangjie_PACKAGE_ID` module
  flags, making function/global creation get-or-insert instead of blindly adding duplicate LLVM symbols, printing
  verifier diagnostics, and generating the C++-style `UNIT_VAL_STR` global for unit values.
- Matched more C++ context/builder behavior by materializing `record.std.core:String` as `{ i8 addrspace(1)*, i32,
  i32 }`, placing entry allocas in a dedicated `allocas` block before the real entry block, applying fast-math flags
  when enabled, and lowering rune literals to their numeric code point rather than a string hash.
- Added context-safe LLVM attribute helpers that scan an existing attribute list, avoid duplicate attributes, and
  support typed attributes through `LLVMCreateTypeAttribute`/`LLVMGetTypeAttributeValue`.
- Matched the direct-function C++ `CreateCallOrInvoke(llvm::Function*)` attribute behavior more closely: struct-return
  declarations now get typed `sret` plus `noalias`, and call/invoke instructions propagate direct callee `sret`/`noalias`
  attributes when the callee is an actual LLVM function.
- Expanded `IRBuilder2` with wrappers used by the C++ builder surface: memset/memcpy/memmove, inbounds GEP, struct GEP,
  varray GEP, PHI creation/incoming edges, select, and extractvalue.
- Added checked target lookup and target-machine emission helpers that preserve LLVM diagnostic messages for file and
  memory-buffer emission, plus option setters for CPU/features/ABI/opt level/relocation/code model.

Known remaining gaps for this scope:

- The C++ LLVM integration still has broader native-backend behavior not reachable through the current partial CHIR
  emitters: full target initialization policy, package-level object/assembly emission orchestration, complete
  pass-pipeline selection, target-dependent ABI/CFFI attributes, and precise debug-info attachment for
  functions/types/locals.
- `IRBuilder2` restores insertion to the current block after entry alloca creation; the C API wrapper does not yet
  preserve an arbitrary instruction iterator the way C++ `IRBuilder` does.
- Indirect function-pointer calls still rely on higher-level emitters to supply correct struct-return storage and
  attributes from `CGFunctionType`; the low-level builder now mirrors the C++ direct-function overload only.
- The target-machine and pass-builder wrappers are ready for callers, but the package-level emission path does not yet
  drive them end to end.

Remaining `TODO(selfhost:CodeGen)` markers in this llvm-ffi slice: 0.

Estimated behavior coverage for this llvm-ffi/module/context/IRBuilder slice: 52%.
