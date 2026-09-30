# Macro runtime path regression

Run on Linux with an official-host stage1 and its matching official SDK:

```sh
python3 tests/macro_runtime_path/run.py --compiler /path/to/cjcj-stage1 \
  --sdk /path/to/official-sdk --out /path/to/new-results
```

The runner copies the compiler into two independent layouts. The valid layout
contains physical runtime and boundscheck copies; the missing layout omits the
compiler-relative runtime while retaining the same host SDK environment.
Five CLI invocations run concurrently, preserving each exit code, output hash,
diagnostic checks, compiler identity, CPU affinity and before/after uptime.
Every assertion prints its result, including after an earlier failure.

The fixed custom annotation must compile with valid libraries. Missing runtime
must reject it and name the requested library in the realpath diagnostic.
Plain functions compile in both layouts; an undeclared annotation remains an
error with a valid runtime. Successful compilation alone does not certify all
annotation metadata consumers. The frozen baseline is expected to fail only
the missing-runtime diagnostic check; use this same runner for every arm.

Specification: upstream `src/Macro/InvokeUtil.cpp:33`. The namespace loader
must report the same realpath failure before returning an unopened handle.
