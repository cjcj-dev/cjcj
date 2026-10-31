# Trivial static devirtualization

With `CANGJIE_HOME` and `LD_LIBRARY_PATH` set to the compiler's matching host SDK:

```sh
python3 tests/trivial_statics/check.py \
  --compiler /path/to/cjcj-stage1 --out /path/to/empty-evidence --jobs 192
```

The runner compiles three source fixtures at `-O2` and reads the real compiler's
`Devirtualization` CHIR dump. It checks that an inlined `C.f1(String)` call selects
`C.f1(Int64)` using its original `Int64` argument. The two methods implement
separate instances of `I<T>`. It also observes preserved generic type arguments,
a generic receiver, dynamic RTTI, and an ordinary constant-folded return.

The merged Devirtualization pass follows upstream 2a468452. Remove
`RunOnFuncForInvokeStatic` from `Devirtualization.RunOnFuncs` to exercise the
static collection boundary. The CHIR unit cases in
`packages/chir/src/devirtualization_tests` additionally cover RTTI(value),
TryInvokeStatic successors, unknown receiver types, and the STATIC attribute of
an instantiated function. Removing the GetRTTIStatic guard must affect only the
RTTI(value) cases; bypassing `invoke.ReplaceWith(call)` exercises the existing
RewriteToApply consumer.

Keep the same runner, fixtures, SDK and build configuration in candidate,
mutation and restored arms. Preserve compiler hashes immediately after each
build. Compilation failures cannot count as the expected failing assertion.
