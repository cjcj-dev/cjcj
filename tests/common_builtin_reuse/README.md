# Source builtin reuse

Run `python3 tests/common_builtin_reuse/run.py /path/to/cjcj-stage1 /path/to/evidence`
with the compiler's paired host SDK environment (`CANGJIE_HOME` and
`LD_LIBRARY_PATH`). Each independent compiler invocation uses `--jobs 192`;
the driver runs up to four invocations concurrently.

The root and original platform fixtures are fixed copies from commit
`f310f332b0595fb3f69a38d9f597047d20d429c0` of the finalizer registration input.
The driver checks actual compiler return codes, nonempty CHIR, and the
serialized declaration kind and builtin type discriminator, not name-only
matching. Each of the five kinds must occur once; generic parameters and
CPointer's CType constraint must survive import. Typed platform functions
consume all five restored kinds.

Partial common inputs clear only the top-level flag of one unused builtin
declaration in the original exported CJO. Its index and the other serialized
records remain unchanged. The original root's CHIR does not consume these
builtin types. This exercises per-kind missing declaration production through
the real loader and Sema entry, without a product test hook.

User duplicate declarations must still fail. A user class named RawArray is
not an AST BuiltInDecl and must not suppress compiler builtin creation. The
existing zero-range diagnostic exception for this invalid input is recorded
as the baseline rejection signature, not as successful diagnostic rendering.
The unrelated non-core common/specific control uses the normal prelude;
`--no-prelude` cannot supply its required std.core Object declaration.

Each target emits a PASS/FAIL line even when compilation fails, and
`summary.json` retains commands, return codes, declaration observations and
artifact hashes. The driver does not treat a missing compiler or missing
output as a successful test.
