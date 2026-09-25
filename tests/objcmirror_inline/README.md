# ObjCMirror inlining regression

Upstream `8163098c6707aed772e6729cdfd2dd2efd64e2ac`,
`src/CHIR/Optimization/FunctionInline.cpp:253-260`, allows `OBJ_C_MIRROR`
after the `INSTANCEVAR_INIT` check and before count/size thresholds.

Build the workspace, then run the fixture against its release archives:

```sh
python3 tests/objcmirror_inline/run.py --tree /path/to/candidate \
  --dependencies /path/to/candidate --sdk /path/to/host-sdk --out /path/to/evidence
```

The fixture calls the product `FunctionInline.Run` and observes remaining
`APPLY` expressions. An 80-expression mirror body must inline; an ordinary
body of the same size must remain. `NO_INLINE` still prevents mirror inlining,
and an ordinary small body still inlines. The runner compiles only the fixture,
links existing release archives, and records compiler/archive/runtime/ELF hashes,
return codes, affinity, timings, and assertion output.

For fault injection, remove only the `OBJ_C_MIRROR` branch from the product and
rebuild in a separate tree. Keep `--dependencies` pinned to the candidate tree;
only the CHIR archive is taken from `--tree`. Exactly `mirror_over_threshold`
must fail. Rebuild restored source with the same recipe and run all four again.
