# Array copy element-size regression

`run.sh COMPILER STDLIB_CORE_SOURCE OUTPUT` compiles the **real std.core sources**
with the supplied stage1 compiler, replaces `core.o` in a private core archive,
and links/runs `main.cj`. Merely compiling a call to `Array.clone` uses the
previously built std implementation and does not test this codegen path.

Set `CANGJIE_HOME` / `LD_LIBRARY_PATH` for the compiler's private target SDK and
host runtime; `COPY_RUN_LD` selects the coloured product runtime for the fixture.
The unchanged native objects come from that SDK's core archive. No runtime or
compiler implementation is copied into the test.

`check.py` follows the emitted SSA values, not the presence of a TypeInfo load:

* all emitted generic Array copy sites must multiply the count and both offsets
  by the same reference-kind-selected element size; its value arm must load
  element TypeInfo field 4;
* the resulting byte count and addresses must reach the generic copy intrinsic;
* clone's linked machine code must retain dynamic multiplication and the runtime
  copy call, without the old constant-eight scale;
* independent controls check byte-array stride and the zero-length clone CFG.

The single `genericArrayCopyUsesElementLayout` invariant reports each observed
function/site. It explicitly requires full/range clone and both CopyTo overloads.
A failed site cannot be hidden by another passing site. Candidate/cut/restored
use exactly the same checker and fixture. Runtime modes independently check
non-reference tuple elements containing class references, offsets, integer and
reference arrays, and zero length. Every successful runtime assertion prints a
marker. The emitted IR and disassembly, compiler and fixture hashes, return
codes, and before/after uptime remain in OUTPUT.

Source-only presence checks are insufficient: allocation already loaded
TypeInfo.size before this repair, so a scan for `ti.size` alone passes the old
broken copy path. The checker must trace the copy's actual operands.
