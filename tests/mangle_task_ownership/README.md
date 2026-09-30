# Macro mangling task ownership (#692)

The P0 input generator emits legal macro packages and a non-macro control.
`qualify.py TREE --diff FILE` installs the observation-only fixture into a
**disposable compiler source copy**. Build that copy with the normal stage1
recipe. The installed function observes normal desugared declarations immediately
before `DoMangling`; it does not manufacture AST types or reject inputs.

Qualification requires actual output showing that RaceA and RaceB have the same
source ClassTy with a bound declaration, belong to different full batches, and
leave a remainder batch. Source declaration counts are not qualification evidence.
The fixture is absent from default compiler source; verify this with
`nm --defined-only` on both compiler artifacts.

Specification: upstream `src/Frontend/CompilerInstance.cpp:794-805,845-869`;
#692 Synthesize report P0-P5. The full intermediate-model migration belongs to
#693 and is outside this test package.

`qualify.py --race` additionally installs `Race.cj` and synchronization calls in
real StoreTy and parameter-consumption paths. Use it only after the observation
qualification succeeds. `BeginTop` schedules complete top-level walks, including
prefix conversion and cache release. It runs the two selected batch prefixes
without overlap, parks the consumer at its qualified index, and permits only
the qualified producer to hold the first publication. Other batches wait until
the pair completes. The consumer's top-level finally releases the producer.
The scheduler changes no declaration, type, cache result, task membership, or
mangling call. The candidate and both cuts use the same fixture. A timeout,
unqualified publisher, or missing consumer event is a fixture failure.

`run.py` records compiler/runtime/source hashes, affinity, uptime, compiler rc,
bitcode hash and defined symbol set. `--race --red parallel` accepts only the
missing-Class-declaration result observed at the real parameter consumer;
ordinary compiler errors do not satisfy that condition. Single-worker and
remainder/control cases must still succeed. Successful intermediate outputs are
removed after recording identities; failure artifacts are retained.

Use `cut.py --kind adapter` for the baseline-existing task-adapter constructor
cut and `--kind macro` for the candidate macro-route cut, before installing the
fixture. Reports must retain the actual rc and assertion evidence for every arm;
source inspection alone is not product validation.
