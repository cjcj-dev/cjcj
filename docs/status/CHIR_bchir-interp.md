## CHIR BCHIR Interpreter Deepening Status

Date: 2026-06-17

Scope: `packages/chir/src` BCHIR bytecode, BCHIR interpreter, interpreter value model, and CHIR-to-BCHIR memory-expression emission.

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
- Kept `cjpm build` green and confirmed no remaining `TODO(selfhost:CHIR)` markers under `packages/chir/src`.

Remaining C++ fidelity gaps:

- Full exception propagation is still not behavior-faithful: exception edges, raised exception payloads, `GET_EXCEPTION`, `RAISE`, and default runtime exception constructors need the C++ control-stack behavior.
- `INVOKE(_EXC)`, `TYPECAST(_EXC)`, and `SWITCH` now cover their ordinary successful paths, but exception-target behavior, checked/overflow-exact casts, failed casts, and diagnostic/reporting details remain incomplete relative to the C++ `BCHIRInterpreter.cpp`.
- `VARRAY_GET` now covers ordinary reads, but bad-index exception construction/propagation is still simplified to interpreter trap behavior.
- Interpreter intrinsics, syscalls, and const-eval diagnostics remain incomplete relative to the C++ `BCHIRInterpreter.cpp` and `BCHIRIntrinsic.cpp`.
- The local CHIR IR model in this worktree exposes `GET_ELEMENT_REF` and `STORE_ELEMENT_REF` kinds but not yet the C++ path-carrying expression classes/accessors; translation for those remains blocked on that real IR surface rather than adding a duplicate compatibility type.
- String runtime representation is still simplified versus the C++ core-compatible tuple/raw-array layout.
