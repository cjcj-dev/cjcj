# Native producer jobs

The public entry is `node ci/bootstrap/native-cjdb.mjs CONFIG.json`.
`jobs` defaults to `os.availableParallelism()`. An explicit value must be a
positive safe integer; explicit oversubscription is allowed. There is no minimum CPU
count. `linkJobs` defaults to `min(jobs, 8)` and accepts an explicit positive
safe integer independently of the CPU count and build jobs. Memory limits
remain separate from these syntax checks.

The selected values reach `CMAKE_BUILD_PARALLEL_LEVEL`, both CMake build
commands (`-j`), `CANGJIE_LINK_JOB_POOL`, and the nested LLVM configure argument
`LLVM_PARALLEL_LINK_JOBS`. The effective selection is preserved in the ordinary
`BUILD-INPUTS.json` configuration after completion. Windows `pythonProducer`
inherits the native selection when its own `jobs` is omitted; an explicit
Python selection is validated by the normal Windows Python producer and
becomes MSBuild `/m:N`. Existing host identity, source, Python development
installation, AST, and sccache requirements remain in force.

`native-cjdb-jobs.test.mjs` exercises the public CLI in an actual four-CPU
domain. Supply `NATIVE_JOBS_EVIDENCE` (a fresh retained directory),
`NATIVE_JOBS_SCCACHE` (real sccache), and `NATIVE_JOBS_PYTHON` (real Python 3.11
development installation). Run from the repository root, through the assigned
resource slot, with `node --test ci/bootstrap/native-cjdb-jobs.test.mjs`.
The finite Linux fixture reaches real CMake configure and C compilation,
executes the compiled program, observes default 4 / explicit 2 jobs and
default 4 / explicit 1 link jobs, and checks the actual build argv. It stops
intentionally before native installation with public process rc1; the test
requires that exact stop after the compiled target has run. It does not build
LLVM/CJDB, install an SDK, or establish Windows production eligibility.

The product cut replaces `CMAKE_BUILD_PARALLEL_LEVEL:jobs` with `99`. The
compiled program must then report 99 and fail the expected jobs assertion;
invalid-capacity and wrong-host controls must still pass. Restore the product
file and rerun in fresh evidence directories. No test changes platform identity
or supplies fake Python executables. Memory, disk, and CI duration need their
own actual evidence; CPU count is not a correctness threshold.

The affected oversubscription gate in `native-cjdb-tools.test.mjs` passes
available CPUs + 1 build jobs and one more link job through real CMake,
compilation and the actual build argv. Reinstating the old upper-bound product
check must fail that test while the wrong-tool control stays green.
`native-python-jobs-explicit.test.mjs` checks the actual PCbuild argument
constructor and invalid values; it does not run Windows MSBuild.
The AST reader receives the exact configured `tools.cmake` as `cmakeCommand`;
reader acceptance and installation-order validation belong to its consumer.
