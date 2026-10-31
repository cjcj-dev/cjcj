# Function body lowering consumer

Status: NOT_RUN. Use the newly installed compiler with the fixed target std and runtime pair.

Compile and run `consumer.cj` at O0 and O2, with `--jobs 1`, `--jobs 4`, and
`--jobs 4 --cjcj-disable-lowering-concurrency`. Capture actual lowering-worker events
with `CJCJ_BACKEND_CONCURRENCY_TRACE=1`; the parallel arm must show distinct worker
threads and overlapping begin/end intervals. Run the normal multi-module deterministic
trials separately; this consumer checks return values from branches, captured lambdas,
nested functions, generic calls, exceptions, virtual dispatch, shared globals and arrays.
Compare outputs and declared artifact identities across arms. A passing build alone is
not a runtime result, and the disable arm must contain no lowering-worker events.

The generic cloning arm also compares `--cjcj-disable-generic-concurrency` at O2.
`pick` and `genericCapture` require cloned statements to retain cross-statement local
references and captured variables after the ordered registration/reconnection phase.
Capture generic-clone-worker events to establish actual concurrent allocation.
