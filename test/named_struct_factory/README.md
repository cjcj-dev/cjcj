# Named struct factory regression

Build the compiler normally with `cjpm build`. With the matching official host
SDK in `CANGJIE_HOME`, link the regression suite against those product archives:

```sh
bash test/named_struct_factory/build.sh /absolute/product/tree /absolute/test-elf /absolute/assertions/libLLVM-15.so /absolute/assertions/cjselfhost_llvmshim.o
LD_LIBRARY_PATH=/absolute/assertions:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/third_party/llvm/lib /absolute/test-elf --filter='NamedStructFactoryTest.*' --show-all-output
```

Build the shim against the same LLVM source and generated headers as the library.
The LLVM library must have assertions enabled: the regression is LLVM's
`StructType::setBody` opaque-type precondition (`llvm/lib/IR/Type.cpp:446`). A
release library without that assertion cannot establish the cache-miss-only
initialization invariant. The harness reads the product's returned LLVM type;
it does not recompile or replace `CGType` or `CGTypeInfo`.

`NamedStructFactoryTest` checks Unit, BitMap, TypeTemplate, GenericTypeInfo and
GenericCustomTypeInfo. Each factory is created once (layout) and looked up
again on the same `LLVMContext` (identity, still not opaque). `TypeInfoGcTibUsesBitMap`
checks that `GetOrCreateTypeInfoType` field 5 is a pointer to the `BitMap` type
returned by `GetBitMapType`.

`NamedStructRulerTest.BareSecondSetBodyHitsOpaquePrecondition` is not part of
the green filter. On an assertions library it must exit non-zero at the second
bare `LLVMStructSetBody` (`Struct body already set`). A non-assertions library
that survives that call is not a pass.

For a factory control, restore unconditional `SetStructTypeBody` in an isolated
product build: the matching first-layout case must still pass, and the repeated
lookup must reach the LLVM precondition. For the consumer control, replace the
`GetBitMapType` call inside `GetOrCreateTypeInfoType` with `i8*`: only
`TypeInfoGcTibUsesBitMap` fails, on the field-identity assertion after
`NAMED_STRUCT_TYPEINFO_GCTIB_COMPARE`.

This suite validates the five named-type factories. It does not qualify GC
behavior, self-hosted compiler execution on a coloured runtime, or ExtensionDef
(`GetOrCreateExtensionDefType` is cjcj#74).
