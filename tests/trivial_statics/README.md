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

Two independent product mutations must fail only
`actual_types_choose_nonrecursive_raw_callee`:

* Remove `devirtStatics.RunOnPackage` in `CodeGenBridge.cj`.
* Replace `ResolveStaticCallee` at its call site with the pre-d1f7107d
  `GetExpectedFunc(invoke.GetMethodName(), invoke.GetMethodType(), true,
  ArrayList<Type>(), builder, false)` query.

The second mutation selects `f1(String)` for the `Int64` argument, recreating the
recursive dispatch choice described by d1f7107d. Keep the same runner, fixtures,
SDK and build configuration in candidate, mutation and restored arms. Preserve
compiler hashes immediately after each build. Compilation failures cannot count
as the expected failing assertion.
