# Package reset across split modules

Status: NOT_RUN. This is a normal CLI consumer for the package-wide reset phase;
it does not reproduce or explain the historical LLVM getName fault by itself.

With an independently installed candidate and its matching target SDK, compile
`consumer.cj` using `--apc 4 --jobs 4 --save-temps=<new-directory>` and
`CJCJ_BACKEND_CONCURRENCY_TRACE=1`. Use a new output path and retain the actual
compiler command, exit status, trace and emitted IR. No LLVM/runtime substitution,
debugger, retry loop or disabled concurrency is required.

Before running the produced executable, require all of these compilation checks:

- Four split-module definition and finalization tasks actually execute. A filter
  or a one-module fallback is not this test.
- The emitted package initializer calls its imports initializer. That imports
  initializer's definition is in another split module; if the splitter keeps it
  in the main module, record COVERAGE_MISS rather than claiming cross-module
  coverage. Locate this from the emitted definitions/declarations, not names of
  the output files alone.
- Every definition task ends before the package task begins. Exactly one package
  task completes before the first finalization task begins. Definition and
  finalization work still use the existing worker queue.
- The emitted `ir2` reset/flag-reset closure includes the imported collection
  package reset call, with an actual definition and valid call types. Merely
  deleting dependency traversal is not a passing repair.

The executable must then return zero and print `PACKAGE_RESET_PHASE_OK`, checking
that its normal global initialization has completed. This is a finite normal
consumer, not an SDK-wide or historical-crash qualification.

For independent review, the precise old-source counterexample is the main
finalizer's `CollectDependentPackages` querying/traversing a foreign module while
that module's finalizer mutates its LLVM context or removes IR. Reintroducing the
old placement of `CreatePackageInitResetFunction` invalidates the phase-order
condition. No probabilistic crash is required to establish that the source
permits unsynchronized access; an old run that happens to finish is not a red
control. Dynamic execution and any controlled fault arm need their own admission.
