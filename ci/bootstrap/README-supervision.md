# Linux command supervision

The public `sdk-build.mjs` and `sdk-flow.mjs` commands use the same local
`supervisedCommand` implementation for each existing command edge. On Linux
this requires `python3` in PATH with `os.pidfd_open` and
`signal.pidfd_send_signal` (Python 3.9 or newer), Linux child-subreaper and pidfd
system calls, and `/proc`. The supervisor tests the actual APIs before borrowing
any jobserver bytes or launching the payload. Missing Python or unavailable APIs
fail with `SUPERVISOR_DEPENDENCY` or `SUPERVISOR_API` diagnostics. Even a generic
`repos: {}` configuration has this requirement; it does not borrow a runtime
checkout dependency. Other platforms retain the existing command path and do
not gain Linux subtree recovery guarantees.

The Python guardian owns the original upstream bytes and its kernel subtree.
The Node caller only handles ready/GO, cancellation and results. Parent EOF,
INT/TERM or child failure initiates cleanup; bytes are returned unchanged only
after the subtree has no children. A blocked return reports INCOMPLETE while
the live guardian retains its byte ledger and continues retrying. Output or
status closure does not release that responsibility.

Each sequential SDK command inherits one implicit slot. A numeric or FIFO
jobserver lends only currently available bytes, at most the requested jobs minus
one. The ordinary payload receives one implicit slot and those borrowed slots.
A Ninja coordinator donates its implicit slot to its private command pool.
No-auth ordinary SDK commands stay without authentication; disabled negative
FD authentication limits budgeted work to one slot. Invalid positive FDs fail.
This is not a separate admission scheduler for concurrent independent SDK
commands: callers must already own a valid implicit slot for each simultaneous
invocation. Never launch independent calls against one duplicated implicit slot.

Worker or intermediate guardian loss can be recovered by a surviving ancestor
guardian. Killing the last guardian that owns original bytes cannot be recovered
by this process protocol: it reports INCOMPLETE/non-success, does not fabricate
replacement bytes and cannot authorize the next stage. Such residuals need the
external caller's exact ownership-based cleanup.

Runtime vendors this ESM source verbatim as
`stdlib/scripts/command-supervisor.mjs` with a fixed source commit/blob record.
No runtime lookup of the tools repository is used. The file is a build-time
dependency, not an installed compiler launcher. Finite protocol, public
subtree-loss and native-budget tests live beside this document; they do not
qualify complete SDK production or another platform.

The guardian forks without waiting synchronously for exec. It registers the
child immediately and polls a nonblocking CLOEXEC error pipe while servicing
cancellation and owner EOF. The child inherits the payload cwd, environment and
stdio, starts a new session, and closes every descriptor except its private pool
and the temporary exec error endpoint. No extra ledger owner or thread is used.

Cleanup advances through quiescence, private-pool disposal, failure diagnostics,
original-byte return and final status. An exception retains the current phase
and byte prefix; there is no unconditional finally that returns loans. A live
guardian can report INCOMPLETE and keep retrying after the observer exits.
Diagnostic EIO/EACCES is failure, never evidence that a file is absent. A final
status must agree with the guardian's actual exit status. Signals only latch
in memory; filesystem work happens inside the guarded lifecycle.

Work diagnostics use the existing private execution domain, independently of a
possibly read-only payload cwd. These guarantees cover returned errors and a
schedulable guardian while a child is stuck before exec; they do not recover an
uninterruptibly blocked guardian kernel call, its SIGKILL/OOM, or host failure.

Signal completion preserves the kernel `childRc` and a numeric
`childSignalNumber` (and `cancellationSignalNumber` for cancellation). The
existing name fields remain names for enum members and are null for unnamed
real-time signals. Name availability cannot prevent finishing a settled ledger.
The public SDK/vendor signal fixture checks actual exit, original bytes returned
once, and no owned processes before test cleanup.
