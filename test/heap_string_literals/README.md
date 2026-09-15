# Managed String literal backing

Run these fixtures on kkk2 through the workflow wrapper. Use a private target
SDK with the rebuilt static/shared std closure. Set `CANGJIE_HOME`,
`LITERAL_HOST` (compiler host SDK), `LITERAL_RUNTIME` (runtime/boundscheck
pair), `LITERAL_OUT` (fresh directory), and `LITERAL_CORES` (reserved CPUs).
`LITERAL_CJC` optionally selects an independently built compiler arm.

## Literal producer and consumers

`run.sh` compiles a split executable and imported package, verifies actual
IR/assembly GC roots, then reads generated String backing arrays through the
public raw-data API. It checks heap membership, exact bytes, substring sharing,
NUL/UTF-8, globals, const declarations, object-field copies, and GC. Ordinary
heap arrays, ordinary aggregates, and native bytes provide controls.

`exceptions/run.sh` covers compiler-created division-error messages before and
after GC, plus the synthetic main OOM printer. The OOM is produced by a real
oversized array allocation. Its expected child exit is recorded separately.

## Cache initialization and reset

`library/run.sh` builds real split Cangjie DLLs and a native public-API caller.
`LITERAL_RUNTIME_HEADERS` supplies `Cangjie.h` and `PackageInitTest.h` from the
matching runtime. It derives real package/unit/reset code addresses from the
emitted IR and linker references; it never substitutes a cache implementation.

`LITERAL_CONCURRENT=1` uses the testable runtime's exact Complete pause and
waiting-caller query. It verifies a single-worker wait, GC while parked, no
consumer before completion, full bytes afterwards, and cache reuse on reset.
Missing observations fail the test. Reset must rerun the ordinary body and its
callback while preserving unrelated package state and complete literal caches.

`LITERAL_BUILD_ONLY=1` records `build.rc` and explicitly marks `run.rc` as
`NOT_RUN(build-only)`. `library/execute.sh` replays these retained artifacts
with `LITERAL_ARTIFACTS`, a fresh `LITERAL_OUT`, and an explicit runtime pair;
it records original build inputs and actual execution hashes separately.

For the allocator-fault DLL set `LITERAL_FAIL_BODY=1`. Then run
`library/verify_failure.py <run-directory>`: it checks the actual original OOM,
absence of consumers, Failed state, and Abort exit 70. The verifier produces
fixed target assertions even though a successful Abort cannot return to the
child fixture. The child's actual exit code remains in `run.rc`.

Controlled compiler patches are in `cuts/`. Preserve green/cut/restored
compiler, std, ELF and shared-library identities. These fixtures do not claim
coverage of the separate #607 field-barrier axes.
