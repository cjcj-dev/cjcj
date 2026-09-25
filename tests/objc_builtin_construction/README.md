# Builtin Objective-C constructor checks

Run with a real stage1 compiler and its matching host SDK environment:

```sh
python3 tests/objc_builtin_construction/run.py \
  --compiler /absolute/path/cjcj-stage1 \
  --stub-compiler /absolute/path/sdk-host/bin/cjc \
  --out /absolute/path/evidence
```

`internal.cj` and `lang.cj` are Linux front-end declaration fixtures. They are
not an Objective-C runtime and do not qualify Darwin execution. Both packages
must be imported: the product ObjC desugar entry checks whether `objc.internal`
is accessible. `--imports` reuses a previously built import directory so all
compiler arms read the same CJO files.

The runner checks the real compiler's exit code, exact diagnostic count and
source target, and rejected constructor state in the post-desugar AST. Each
assertion is independent and printed, including failures; a diagnostic failure
cannot hide the AST state assertion. Legal ordinary and CPointer constructions
are controls. Upstream 1e741869 has no accompanying tests.
