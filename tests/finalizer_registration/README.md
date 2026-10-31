# Root constructor registration

The source fixtures exercise the real compiler with a minimal `std.core` for
CHIR tests. `run.py` collects compiler exit codes, CHIR artifacts, compiler and
loaded-library hashes, CPU affinity, and uptime. It does not treat successful
compilation as a finalizer assertion.

`root.cj` covers the root return and a multilevel construction chain;
`delegated.cj` covers a delegated constructor. The const fixtures cover a
finalizable object, a shared global reference, a temporary outside the result
graph, a nested finalizable object, and a non-finalizable folding control.

The minimal core fixtures cannot substitute for the real core package during
code generation: the package initialization path requires its exception raiser.
For IR checks, compile the complete pinned `stdlib/libs/std/core` sources with
`integration/core_probe.cj` added to a private source copy. This supplies the
real exception and package initialization definitions, and adds two source-level
allocation callers for the finalizable and non-finalizable comparisons.

`verify.py` checks the collected CHIR. `core_ir.py` copies each product ELF to
its supported `cjc-frontend` entry name, records equal hashes and an exec trace,
and emits IR without invoking a different LLVM installation. `verify_ir.py`
checks the dynamic root branch, managed non-leaf bridge, allocation metadata,
inlined ordinary-object control, and constructor exception edge.

`integration/read_chir.cj` calls the existing `CHIRDeserializer.Deserialize`
file entry and checks its returned nodes. Link it against the exact CHIR library
archive used for the tested compiler, and retain both archive and link hashes.
`roundtrip.py` supplies actual compiler-produced binary CHIR, including an
independent scalar folding control. This validates the library serialization
lifecycle; it does not establish that the common-part frontend succeeds.

The frontend's non-visible `--deserialize-chir-and-dump` option is not enabled
by these tests. The `platform.cj` and `imported.cj` inputs retain the distinct
common-part and ordinary-import reproductions; their input CJO identity must be
verified before treating either as a rebuilt-core result.

The compiler package changes are held for combination with cjcj-llvm#109 and
cangjie-runtime#1394. Compiler CHIR/IR checks do not establish runtime registration
timing for a mixed compiler/LLVM/runtime installation. Rebuild the standard
library and imported CHIR with the complete candidate combination before use.
