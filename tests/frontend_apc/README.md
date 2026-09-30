# Frontend APC output contract

`ci/test-frontend-apc.py` runs the real standalone frontend and inspects every
generated bitcode file with the same LLVM library used by the compiler. It
checks explicit file outputs, existing directory outputs, omitted `-o`, APC
warnings, and complete function-definition sets against a single-module
reference. It also exercises incremental cold/warm execution and the full
driver independently. Assertions continue after warning or parse failures so
that an earlier diagnostic cannot hide the completeness assertion.

Explicit files must match the single-module definition set exactly. Directory
and omitted-output partitions must contain that set; partition-local extra
definitions are recorded without filtering. Use `--baseline-work` with a
baseline evidence directory to require an empty baseline/candidate definition
set difference for every directory configuration. `--modes` and `--surfaces`
select independent integration surfaces without changing their assertions.

Run on a build host with an official host compiler SDK and paired LLVM:

```sh
ulimit -c 0
python3 ci/test-frontend-apc.py \
  --compiler /path/to/cjcj-stage1 --sdk /path/to/host-sdk \
  --llvm-library /path/to/libLLVM-15.so --repo "$PWD" \
  --core /path/to/fixed/stdlib/libs/std/core --work /path/to/evidence
```

The core input must include the layout-contract additions used by
`ci/test-codegen-runtime-layout.sh`; retain and hash this fixed input tree.
The explicit array/reference fixture is separate from that historical core
input. Each work directory must be new. The default is three executions per
main configuration, not a repeat-until-success loop. Compiler, LLVM and host
runtime hashes, commands, compile/parse return codes, definition sets, and
every assertion are retained in the evidence directory.
