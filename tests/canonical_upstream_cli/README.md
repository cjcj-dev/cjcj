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
object before and after aliased call/store. `match_guard` exercises both fragments
of an alternative pattern with true/false guards and the exhaustive final case,
checking compiler reachability diagnostics as well as runtime values.

These are prepared consumer inputs, not executed evidence. The arm label does not
perform a product cut or grant a pass: a cut must be made in an isolated compiler
source, rebuilt through the normal target, and associated with its actual diff and
producer. A failed compile is not a reached runtime assertion. Matching runtime
SO and SDK producer identities are supplied by the enclosing build/install run.
