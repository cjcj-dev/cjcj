# Generic mutable receiver copyback

Run `node test/generic_this_copyback/run.mjs /absolute/public/cjc /new/output candidate`
under the normal compiler and target runtime environment. `PAYLOAD_RUN_LD` may
select the target runtime independently of the compiler host. No test macros or
runtime changes are needed. Four normal compile/run arms cover O0/O2, debug and
non-debug; each records nine independent field/body/exception assertions.

`ReplaceFunction` only runs with compile debug enabled. Its no-reference
constructor and mutable-method receiver is a headerless original payload; the
callee wrapper operates on a boxed temporary. The readback must begin at byte
zero of native storage. Reference-bearing receivers retain their aggregate
barriers. Stack and managed-field destinations, call and protected invocation,
and a real constructor unwind are included. Inspect the saved actual IR to
confirm call/invoke reachability; source-level try alone is not branch evidence.

The product cut restores only the no-reference copyback to the prior
CallGCWriteGenericPayloadFromSrc call, rebuilds the actual codegen package and
compiler, and runs this unchanged matrix. Preserve all results rather than
stopping at the first assertion. The non-debug/reference/unwind controls must
remain valid. A tool report recovery additionally requires normal rebuilding
and installation of affected std code: rebuilding this fixture or cjcov alone
cannot replace old std.collection machine code.
