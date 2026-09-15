# Managed String literal backing

Run `run.sh` on kkk2 through the workflow wrapper. Set `CANGJIE_HOME` to a private target SDK containing the rebuilt static/shared std closure, `LITERAL_HOST` to the frozen host SDK, `LITERAL_RUNTIME` to the matching runtime/boundscheck directory, `LITERAL_OUT` to a fresh output directory, and `LITERAL_CORES` to a reserved CPU domain. `LITERAL_CJC` selects an independently built compiler arm.

The fixture compiles an imported package and the executable with separate module partitions. It checks the compiler's actual IR and emitted GC root table, then reads the generated String arrays through the public raw-data API. Native observation checks the runtime's registered heap ranges and exact payload bytes. Two pointers are pinned together for sharing checks. It also copies literals into object fields and checks them after an explicit GC. Empty literal and `String.empty` field values cross that same GC.

The ordinary heap byte array and native byte constant are controls. The C observer records every target assertion, return status, and process mappings. The runner retains compiler/std/runtime identities, backend output, and executable hashes.

This fixture validates the producer and its consumers. It does not establish the separate runtime package-initialization completion ABI or the #607 field-barrier axes.

`library/run.sh` builds actual split Cangjie DLLs plus a native public-API
caller. `LITERAL_RUNTIME_HEADERS` supplies the runtime's `Cangjie.h` and
`PackageInitTest.h`. `LITERAL_CONCURRENT=1` requires the testable runtime's
cooperative Complete pause and exact waiter observation. Missing waiter
observation fails the fixture; a started native thread does not establish
participation in the runtime wait graph. The fixture obtains package/unit/reset addresses from linker
references to symbols extracted from this compiler's emitted IR.

The library fixture is work in progress: its first control InitCJLibrary
currently hits the runtime mutator saferegion precondition (library-dev2,
rc134), before the cache target assertions. It is not accepted evidence.
`LITERAL_FAIL_BODY=1` is reserved for a compiler allocation-fault arm and
checks the first original failure followed by the generated Abort(70) path.

`LITERAL_BUILD_ONLY=1` prepares the DLL/ELF artifacts and records `build.rc`;
`run.rc` explicitly says `NOT_RUN(build-only)`. This allows a runtime owner
to provide the reviewed shared-library pair before any lifecycle assertion
runs. Preserve both the build-time identities and the actual run-time pair.
