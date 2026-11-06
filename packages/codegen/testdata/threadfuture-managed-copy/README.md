# Managed aggregate copy across an ordinary call

The fixture preserves ThreadFuture.GetState and its Option<Bool> field from
packages/driver/src/ToolFuture.cj. Compile it through the public compiler:
```
cjc -O2 --save-temps <private-temps> -o <private-output> threadfuture-managed-copy.cj
llvm-dis <private-temps>/1-driver@cjcj.bc -o <private-raw.ll>
llvm-dis <private-temps>/1-driver@cjcj.opt.bc -o <private-opt.ll>
node check-threadfuture-managed-copy.mjs <private-raw.ll> <private-opt.ll>
<private-output>
```
Use a compiler's actual execution std/runtime/LLVM and matching target SDK,
with ordinary admitted build resources. The executable prints THREAD_FUTURE_OK.
The IR assertion must fail for a producer that erases the managed field address
through ptrtoint/inttoptr. A successful executable alone is not proof: it may
not move this object. After repair, optimization may forward the stored Bool
instead of rereading the tag; inspect the emitted ELF as well as the IR.
