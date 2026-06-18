## CHIR BCHIR Interpreter Deepening Status

Date: 2026-06-18

Scope: `packages/chir/src` BCHIR bytecode, BCHIR interpreter, interpreter value model, CHIR-to-BCHIR emission, and BCHIR debug printing.

Completed in the 2026-06-18 pass:

- Split the combined Cangjie CHIR-to-BCHIR helpers into C++-mirrored component files:
  `TranslateUnaryExpression.cj`, `TranslateBinaryExpression.cj`, `TranslateMemoryExpression.cj`,
  `TranslateOthersExpression.cj`, `TranslateIntrinsic.cj`, and `TranslateTerminatorExpression.cj`.
- Matched the C++ invoke stack convention by pushing the dummy callee cell before translating
  `INVOKE`/`INVOKE_WITH_EXCEPTION` operands, so method bodies keep the same prologue shape as ordinary functions.
- Ported static element-reference emission for `GET_ELEMENT_REF` and `STORE_ELEMENT_REF`, class/struct-aware
  allocation emission, field/path emission, primitive typecast emission, box/unbox/instanceof emission, raw-array
  allocation emission, intrinsic/VArray-get emission, and sorted-table `MULTIBRANCH` switch emission.
- Added bytecode layouts for `APPLY_WITH_EXCEPTION`, `INVOKE_WITH_EXCEPTION`, `INT_OP_WITH_EXCEPTION`,
  `ALLOCATE_WITH_EXCEPTION`, and `RAW_ARRAY_ALLOCATE_WITH_EXCEPTION`, reusing the linker/interpreter exception-target
  cell convention already present in this port.
- Deepened `BCHIRPrinter.cj` to mirror the C++ printer shape: linked-vs-prelink sections, default function slots,
  class-table details, annotation printing with file names, type/overflow/intrinsic labels, and variable-sized
  instruction decoding for `SWITCH`, `FIELD_TPL`, `GETREF`, `STOREINREF`, `SYSCALL`, and `CAPPLY`.
- Added real `IntrinsicKind`-based helpers in `BCHIRIntrinsic.cj` for the interpreter-supported intrinsic subset,
  replacing call-site hard-coded checks in new translation logic with the real sibling `IntrinsicKind` enum.
- Kept `cjpm build` green after the translator split and printer expansion.

Completed in this pass:

- Reworked interpreter pointer values to carry arena/global roots plus aggregate element paths, matching the C++ interpreter's ability to represent references into heap/global aggregate storage.
- Ported execution for BCHIR memory/reference operations that were previously unsupported or approximated: `ALLOCATE_EXC`, `ALLOCATE_STRUCT(_EXC)`, `ALLOCATE_CLASS(_EXC)`, `ALLOCATE_RAW_ARRAY(_EXC)`, `ALLOCATE_RAW_ARRAY_LITERAL(_EXC)`, `RAW_ARRAY_LITERAL_INIT`, `ASG`, `STORE`, `DEREF`, `GETREF`, `STOREINREF`, `FIELD`, `FIELD_TPL`, `BOX`, `UNBOX`, `UNBOX_REF`, `INSTANCEOF`, and successful `APPLY_EXC`.
- Corrected CHIR memory translation so `LOAD` emits `DEREF` and CHIR `STORE` emits `ASG`, matching the C++ translator instead of using the interpreter-only `STORE` opcode.
- Added successful-path execution for exception-form integer arithmetic and unary negation opcodes so they skip exception-target cells when no exception is raised.
- Added BCHIR `RUNE` literal execution and stored rune values as numeric code points as well as literals, allowing rune equality, ordering, literal conversion, and switch selection to behave like the C++ interpreter value path.
- Corrected CHIR-to-BCHIR literal emission for rune constants to write the rune code point instead of a string hash.
- Added successful-path virtual dispatch for `INVOKE(_EXC)` through the BCHIR class vtable, preserving receiver arguments and control-frame return state.
- Ported sorted-table `SWITCH` execution with default target selection for integer, boolean, and rune selectors.
- Added primitive successful-path `TYPECAST(_EXC)` execution driven by BCHIR source and target type-kind cells for rune, boolean, integer, and floating-point sources, with width truncation for integer-like casts.
- Ported ordinary `VARRAY_GET` execution over stack-provided VArray index paths, including nested VArray traversal and bounds rejection.
- Corrected CHIR-to-BCHIR emission for `VARRAY` and `RAW_ARRAY_LITERAL_INIT` so the translator no longer collapses both into generic `ARRAY`.
- Added a narrow `BCHIRIntrinsic.cj` split mirroring the C++ intrinsic component for the intrinsic IDs that the C++ interpreter executes, without copying the full CHIR IR intrinsic enum.
- Ported successful interpreter execution for reference-equality intrinsics (`OBJECT_REFEQ`, `RAW_ARRAY_REFEQ`, `FUNC_REFEQ`) and `ARRAY_GET_UNCHECKED`.
- Added explicit exception-slot handling for `RAISE_EXC` and `GET_EXCEPTION`, plus uncaught `RAISE` trapping, and taught CHIR-to-BCHIR emission to produce `RAISE(_EXC)` and `GET_EXCEPTION`.
- Added `RAW_ARRAY_INIT_BY_VALUE` emission and interpreter fill behavior over the existing raw-array pointer/path model.
- Deepened `BCHIRLinker` toward the C++ linker: global names are reserved before function bodies are linked, per-package file/type/string tables are remapped into the linked `BCHIR`, code-position annotations are preserved with remapped file IDs, and string operands no longer duplicate linked string table entries blindly.
- Ported linker-specific handling for C++ BCHIR layouts that are not fixed-size raw copies: `ALLOCATE_CLASS_EXC`, `INTRINSIC1` type aux remapping, `SYSCALL`, `CAPPLY`, and sorted-table `SWITCH` target relocation.
- Matched the C++ linker’s class-table behavior more closely by materializing class metadata for boxed/`INSTANCEOF` nominal types without local serialized class info and by recording transitive superclasses in linked `BCHIRClassInfo`.
- Kept `cjpm build` green and confirmed no remaining `TODO(selfhost:CHIR)` markers under `packages/chir/src`.

Remaining C++ fidelity gaps:

- Explicit `RAISE_EXC`/`GET_EXCEPTION` handler flow now works for direct bytecode exception edges, but full exception propagation is still not behavior-faithful: default runtime exception constructors, diagnostics, and all checked operation exception edges need the C++ control-stack behavior.
- `INVOKE(_EXC)`, `TYPECAST(_EXC)`, and `SWITCH` now cover their ordinary successful paths, but exception-target behavior, checked/overflow-exact casts, failed casts, and diagnostic/reporting details remain incomplete relative to the C++ `BCHIRInterpreter.cpp`.
- `VARRAY_GET` now covers ordinary reads, but bad-index exception construction/propagation is still simplified to interpreter trap behavior.
- Interpreter intrinsics now cover reference equality and unchecked raw-array get, but syscalls, SIMD/platform intrinsics, the broader intrinsic set, and const-eval diagnostics remain incomplete relative to the C++ `BCHIRInterpreter.cpp` and `BCHIRIntrinsic.cpp`.
- The linker now covers more bytecode layouts, but it still lacks the C++ const-eval-only manual global initializer map and generated calls to const-init functions.
- Dynamic/runtime-index element references are still intentionally not lowered to BCHIR because the C++ BCHIR path
  opcodes encode static aggregate paths; those runtime-index paths need a separate real lowering strategy rather
  than a compatibility duplicate.
- CHIR-to-BCHIR method-name emission for dynamic dispatch still uses the currently exposed source method name, not
  the full C++ `MangleMethodName` signature key, so overloaded virtual dispatch remains less faithful than C++.
- Intrinsic bytecode ID conversion is implemented for the interpreter-supported subset; unsupported intrinsics still
  lower to intrinsic opcodes but do not yet preserve every C++ numeric intrinsic ID.
- BCHIR debug printing now tracks C++ layout and variable instruction sizes, but float bit patterns are still printed
  as raw bits rather than fully reinterpreted decimal `float`/`double` values.
- String runtime representation is still simplified versus the C++ core-compatible tuple/raw-array layout.
