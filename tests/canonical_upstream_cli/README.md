Run `zx run.mjs COMPILER SDK NEW_OUTPUT [candidate|cut|restored]` inside the assigned
remote resource slot, using the installed compiler and its matching C/N/R/std SDK.
The output directory must not already exist. The runner invokes the normal compiler
driver, linker and produced executable at O0 and O2; it records exact child status,
signal, timeout error, source/compiler/executable hashes and target assertions.

`control` is independent arithmetic. `resource_bound` consumes Resource through a
generic intersection bound, checking one close on normal return and exception.
`array_copy` exercises generic primitive/reference copies, nonzero offsets, overlap
and zero length. Its small runtime length does **not** validate the >2GiB split
boundary. `alias_store` reads through an immutable member pointing to a mutable
object before and after aliased call/store. `struct_store` directly exercises the
tracked struct allocation with nested field stores, nested/member mutating calls,
whole-value reads, an unchanged copied value and an immutable field control.
`match_guard` exercises both fragments
of an alternative pattern with true/false guards and the exhaustive final case,
checking compiler reachability diagnostics as well as runtime values.

These are prepared consumer inputs, not executed evidence. The arm label does not
perform a product cut or grant a pass: a cut must be made in an isolated compiler
source, rebuilt through the normal target, and associated with its actual diff and
producer. A failed compile is not a reached runtime assertion. Matching runtime
SO and SDK producer identities are supplied by the enclosing build/install run.

The resource-bound consumer keeps its resource try in statement position and
retains the return from inside that scope. Its trailing throw makes unexpected
fallthrough fail; it does not replace the close-count or exception assertions.
The original 700a fixture ended with the Unit-typed resource try in an Int64
return-expression position and was correctly rejected before execution. Its
first failure remains in the v104 evidence; correcting that input does not
change the compiler's Unit rule or establish that the generic-bound path passes.

The argv-driven integer consumers explicitly import `std.convert.*`: the fixed
stdlib defines `Int64.parse` as an extension in that package, not in core. This
keeps runtime input parsing and every original mechanism assertion unchanged.

Alternative patterns cannot bind variables. The guarded alternative therefore
uses wildcards and extracts the payload in its branch body, retaining both outer
fragments, true/false guards, all original expected values, and the reachability
check. An unexpected Empty value in that body throws instead of returning a
plausible payload. The original illegal pattern diagnostic is retained as v106.
