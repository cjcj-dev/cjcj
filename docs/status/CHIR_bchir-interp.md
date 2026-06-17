## CHIR BCHIR Interpreter Deepening Status

Date: 2026-06-17

Scope: `packages/chir/src` BCHIR bytecode, BCHIR interpreter, interpreter value model, and CHIR-to-BCHIR memory-expression emission.

Completed in this pass:

- Reworked interpreter pointer values to carry arena/global roots plus aggregate element paths, matching the C++ interpreter's ability to represent references into heap/global aggregate storage.
- Ported execution for BCHIR memory/reference operations that were previously unsupported or approximated: `ALLOCATE_EXC`, `ALLOCATE_STRUCT(_EXC)`, `ALLOCATE_CLASS(_EXC)`, `ALLOCATE_RAW_ARRAY(_EXC)`, `ALLOCATE_RAW_ARRAY_LITERAL(_EXC)`, `RAW_ARRAY_LITERAL_INIT`, `ASG`, `STORE`, `DEREF`, `GETREF`, `STOREINREF`, `FIELD`, `FIELD_TPL`, `BOX`, `UNBOX`, `UNBOX_REF`, `INSTANCEOF`, and successful `APPLY_EXC`.
- Corrected CHIR memory translation so `LOAD` emits `DEREF` and CHIR `STORE` emits `ASG`, matching the C++ translator instead of using the interpreter-only `STORE` opcode.
- Added successful-path execution for exception-form integer arithmetic and unary negation opcodes so they skip exception-target cells when no exception is raised.
- Kept `cjpm build` green and confirmed no remaining `TODO(selfhost:CHIR)` markers under `packages/chir/src`.

Remaining C++ fidelity gaps:

- Full exception propagation is still not behavior-faithful: exception edges, raised exception payloads, `GET_EXCEPTION`, `RAISE`, and default runtime exception constructors need the C++ control-stack behavior.
- Dynamic dispatch, `INVOKE(_EXC)`, `TYPECAST(_EXC)`, `SWITCH`, `VARRAY_GET`, interpreter intrinsics, syscalls, and const-eval diagnostics remain incomplete relative to the C++ `BCHIRInterpreter.cpp` and `BCHIRIntrinsic.cpp`.
- The local CHIR IR model in this worktree exposes `GET_ELEMENT_REF` and `STORE_ELEMENT_REF` kinds but not yet the C++ path-carrying expression classes/accessors; translation for those remains blocked on that real IR surface rather than adding a duplicate compatibility type.
- String runtime representation is still simplified versus the C++ core-compatible tuple/raw-array layout.
