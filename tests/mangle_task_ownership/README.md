# Macro mangling task ownership (#692)

The P0 input generator emits legal macro packages and a non-macro control.
`qualify.py TREE --diff FILE` installs the observation-only fixture into a
**disposable compiler source copy**. Build that copy with the normal stage1
recipe. The installed function observes normal desugared declarations immediately
before `DoMangling`; it does not manufacture AST types or reject inputs.

Qualification requires actual output showing that RaceA and RaceB have the same
source ClassTy with a bound declaration, belong to different full batches, and
leave a remainder batch. Source declaration counts are not qualification evidence.
The fixture is absent from default compiler source; verify this with
`nm --defined-only` on both compiler artifacts.

Status: input generation validated by the official compiler; stage1 qualification
and deterministic synchronization arms are still pending. These files alone do
not establish the task-ownership invariant or acceptance of a product fix.

Specification: upstream `src/Frontend/CompilerInstance.cpp:794-805,845-869`;
#692 Synthesize report P0-P5. The full intermediate-model migration belongs to
#693 and is outside this test package.
