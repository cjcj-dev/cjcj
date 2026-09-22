# Reference store strength

The checker consumes the product compiler's retained `0_GenIncremental/*.ll`.
For each fixture function, pass `--expect FUNCTION_REGEX=1` (Strong), `=2`
(NoKeepAlive), or `=0` (an explicitly documented unknown slot). It checks every
write in the selected functions and independently checks that every module write
has four operands with a legal constant. `--filter strength.REGEX` runs the
selected strength assertion without treating input assertions as fatal.

The weak case must compile the real `std.ref` implementation: merely compiling
a caller of `WeakRef.clear()` at O0 does not observe the store in its callee.
Do not replace it with a test-local class named WeakRef. Capture the compiler,
LLVM and runtime identities along with the emitted IR.

Product control arms: change the slot classifier to non-weak / weak, and remove
the fourth operand at the common emitter. Run the same fixture functions with
the same checker, then restore the product and repeat. Hand-written IR can check
the parser but is not evidence of frontend emission.

The slot resolver uses the declaring member (`std.ref.WeakRefBase._value`),
including inherited accesses. Its constructor's own receiver initialization is
Strong, as in ZGC's ordinary constructor putfield; explicit clear/reset stores
are NoKeepAlive. Unknown is reserved for erased/unresolved destination paths,
and the checker requires an explicit per-function `--allow-unknown` entry.

`run.sh` compiles `main.cj` and the supplied real std.ref source concurrently.
Set `STRENGTH_CJC`, `STRENGTH_WEAK_SOURCE`, `STRENGTH_OUT`, `CANGJIE_HOME`, and
`LD_LIBRARY_PATH` to a private, matched compiler/LLVM closure. The array case
observes an element initialization store; compiling an Array setter caller
alone would not prove its separately compiled callee's barrier.

Use `setup_sdk.py --host HOST_SDK --tuple LLVM_TUPLE --compilers ARM_BIN_DIR
--output NEW_DIRECTORY` to prepare the private closure. The arm directory must
contain `cjcj-strength`, `cjcj-r1`, `cjcj-r2`, and `cjcj-r3`. The script uses
`cp -aL` for all reused artifacts, including auxiliary host tools and their LLVM
libraries, and records a symbolic-link inventory in `sdk-links.json`. Auxiliary
tool wrappers point only into the new private host copy. Set `CANGJIE_HOME` to
`NEW_DIRECTORY/sdk` and prepend `NEW_DIRECTORY/tuple/lib` plus the SDK's runtime
and tools library directories to `LD_LIBRARY_PATH`. Preserve each arm's loader
trace and dependency hashes alongside the compiler and IR identities.
