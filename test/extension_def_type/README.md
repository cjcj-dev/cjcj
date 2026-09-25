# ExtensionDef cache regression

Build the compiler normally with `cjpm build`. With the matching official host
SDK in `CANGJIE_HOME`, link the regression suite against those product archives:

```sh
bash test/extension_def_type/build.sh /absolute/product/tree /absolute/test-elf /absolute/assertions/libLLVM-15.so
LD_LIBRARY_PATH=/absolute/assertions:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/third_party/llvm/lib /absolute/test-elf --filter='ExtensionDefTypeTest.*' --show-all-output
```

The LLVM library must have assertions enabled: the regression is LLVM's
`StructType::setBody` opaque-type precondition (`llvm/lib/IR/Type.cpp:446`). A
release library without that assertion cannot establish the cache-miss-only
initialization invariant. The harness reads the product's returned LLVM type;
it does not recompile or replace `CGType`.

Cases check the initial eight-field runtime layout, repeated lookup identity,
and reuse through `GetOrCreateExtensionDefPtrType`. For a regression control,
restore the old factory in an isolated product build: initial layout must still
pass, while repeated lookup and pointer reuse must reach the LLVM precondition.
For a consumer control, replace the pointer helper's factory call with the i8
type: only the pointer identity assertion must fail. Restore the retained normal
product artifacts and rerun the same cases.

This suite validates the named-type factory. It does not qualify GC behavior,
self-hosted compiler execution on a coloured runtime, or other type factories.
