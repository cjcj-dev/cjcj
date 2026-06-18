# CodeGen llvm-ffi Deepening Status

Date: 2026-06-18

Build: `cjpm build` passes.

Reference inspected:

- `/root/cj_build/cangjie_compiler/src/CodeGen/IRBuilder.{h,cpp}`
- `/root/cj_build/cangjie_compiler/src/CodeGen/CGModule.{h,cpp}`
- `/root/cj_build/cangjie_compiler/src/CodeGen/CGContext.{h,cpp}`
- `/root/cj_build/cangjie_compiler/src/CodeGen/DIBuilder.{h,cpp}`
- `/root/cj_build/cangjie_compiler/src/CodeGen/IRAttribute.h`
- `/root/cj_build/cangjie_compiler/src/CodeGen/CGFunction.cpp`
- `/root/cj_build/cangjie_compiler/src/CodeGen/EmitFunctionIR.cpp`
- `/root/cj_build/cangjie_compiler/src/CodeGen/Utils/CGUtils.cpp`
- `/root/cj_build/cangjie_compiler/src/CodeGen/Base/CGTypes`
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
- Added LLVM type-introspection bindings for function return/parameter types and implemented the C++ `SetZExtAttrForCFunc`
  behavior for C ABI boolean returns/arguments. C function declarations now receive `zeroext` where their raw LLVM
  function type uses `i1`, and direct calls propagate direct callee `zeroext` attributes to call/invoke instructions.
- Added `IRBuilder2.CreateCallOrInvoke(CGFunctionType, ...)` and `CreateCallOrInvoke(CGFunction, ...)` wrappers that
  mirror the C++ overload shape: they synthesize a leading struct-return slot, attach typed `sret` plus `noalias` on the
  call, return the sret storage for struct-return calls, and normalize Unit-return calls to `GenerateUnitTypeValue()`.
- Added LLVM exception-handling builder bindings and `IRBuilder2` wrappers for native landing-pad token type,
  landing-pad clauses/cleanup flag, resume, catch/cleanup pads, catch switches/handlers, and catch/cleanup returns.
  This mirrors the C++ wrapper surface used by landing-pad block emission while keeping LLVM itself external.
- Added C++-style basic-block insertion helpers: create-before-first-entry for true entry insertion and
  create-and-insert-after-current variants that preserve the C++ block ordering used by overflow/type-info helper
  generation.
- Added LLVM personality-function C API bindings and the C++ `CGModule::GetExceptionIntrinsicPersonality` behavior:
  macOS uses the runtime declaration, while other targets materialize a private `__cj_personality_v0$` shim returning
  `i32 0`. `CGModule` now exposes set/get/has personality helpers and attaches the exception personality to real CHIR
  function bodies while skipping foreign/CFFI-wrapper functions.
- Added target-data bindings for the C++ `DataLayout` queries used throughout CodeGen: type bit/store/alloc size,
  ABI/call-frame/preferred alignment, preferred global alignment, pointer-sized integer types, pointer sizes, and
  struct element offset lookup. `LLVMTargetMachineHandle` now exposes target/cpu/feature/triple queries, target-data
  creation, and target-machine tuning switches; `CGModule` exposes borrowed module data-layout helpers matching the
  C++ `GetTypeSize`/alignment/offset query shape.
- Added explicit resource ownership to core LLVM handles: contexts, modules, and builders now implement `Resource`,
  module handles retain their creating context when available, released package modules can dispose LLVM modules before
  their paired contexts, and `IRBuilder2` now exposes the same resource-compatible close path for its underlying C
  builder.
- Added `CGModule.Clear()` to mirror the C++ destructor/cleanup ordering for self-host objects that are not released to
  the driver: finalize debug info, dispose the LLVM module first, clear CodeGen caches, then dispose the owned LLVM
  context.
- Corrected `IRBuilder2.CreateEntryBasicBlock` to match the C++ helper contract by inserting before the existing first
  block. Ordinary CHIR block materialization now uses a separate append-at-end helper so `EmitBasicBlockIR` keeps the
  C++ DFS block creation order while true entry/helper blocks get the intended insertion semantics.
- Deepened the LLVM memory-buffer, IRReader, BitReader, and BitWriter wrappers used by the C++ cached-IR/bitcode paths:
  file-buffer creation now has a checked result that preserves LLVM open errors, memory buffers expose size/string
  accessors and range-copy creation, parsed modules retain the context handle supplied by the caller, and file helpers
  mirror the C++ `parseIRFile`/bitcode-file read shape.
- Matched LLVM C API ownership more precisely for memory buffers: ordinary bitcode parse borrows its buffer, lazy
  bitcode module loading transfers the buffer on successful module creation, and `LLVMParseIRInContext` is treated as a
  consuming call because the LLVM implementation wraps the incoming buffer in a `unique_ptr`.
- Added checked bitcode output helpers for file paths, file descriptors, and memory-buffer output so callers can avoid
  the old status-only/nullable patterns when porting C++ `WriteBitcodeToFile` and cached module emission.

Known remaining gaps for this scope:

- The C++ LLVM integration still has broader native-backend behavior not reachable through the current partial CHIR
  emitters: full target initialization policy, package-level object/assembly emission orchestration, complete
  pass-pipeline selection, target-dependent ABI/CFFI attributes, and precise debug-info attachment for
  functions/types/locals.
- `IRBuilder2` restores insertion to the current block after entry alloca creation; the C API wrapper still does not
  preserve an arbitrary instruction iterator the way C++ `IRBuilder` does.
- The new `CGFunctionType` call wrapper covers known-size struct-return setup and call attributes, but the full C++
  unknown-size generic sret path still depends on later generic-allocation/type-info intrinsic lowering.
- Landing-pad construction now has the LLVM wrapper surface and ordinary `GetOrInsertCGFunction` bodies get the Cangjie
  personality function, but higher-level CHIR landing-pad block emission and special package-entry/helper personality
  call sites are still incomplete in the partial self-host port.
- The target-machine, target-data, and pass-builder wrappers are ready for callers, but the package-level emission path
  does not yet drive target creation, pass execution, and object/assembly output end to end.
- The C API `LLVMParseBitcodeInContext2` and `LLVMGetBitcodeModuleInContext2` do not expose diagnostic strings; the
  wrapper reports faithful success/failure and ownership but cannot preserve the richer C++ `SMDiagnostic` text for
  those bitcode-only paths without adding a native shim.

Remaining `TODO(selfhost:CodeGen)` markers in this llvm-ffi slice: 0.

Estimated behavior coverage for this llvm-ffi/module/context/IRBuilder slice: 68%.
