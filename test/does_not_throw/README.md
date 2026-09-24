# DOES_NOT_THROW regression

Run on kkk2 with a freshly built stage1 compiler and a private host SDK:

```
python3 test/does_not_throw/run.py --compiler /path/to/cjcj-stage1 --sdk /path/to/sdk-host --out /path/to/evidence
```

The two `objc` packages supply declarations needed to compile the fixture on Linux.
They do not implement or test the Objective-C ABI. The runner compiles them with
the official host compiler, then compiles `finalizers.cj` with the selected stage1
ELF. It inspects AST, CHIR and **unoptimized** LLVM bitcode from that compilation.

The mirror class, its derived mirror and the synthetic protocol wrapper must each
carry `nounwind`, without `readonly`, `readnone` or `willreturn`. Their actual
release calls remain present. The ordinary user finalizer must remain unmarked. A real `Int64.hashCode` call
positively checks that NO_SIDE_EFFECT still emits its three stronger promises.
Every assertion prints `EXECUTED`, including successful and non-fatal existence
checks. AST and CHIR values print `OBSERVED` so producer and consumer cuts can be
distinguished. A producer or consumer cut fails only the three `llvmNoUnwind`
assertions; compilation must still succeed.

`DoesNotThrowTest.independentAttributeRoundTrip` additionally checks CHIR index 38,
its name, bit encoding and serialization, including the independent
`NO_SIDE_EFFECT` positive control. Run with `cjpm test -m packages/chir
--filter '*DoesNotThrow*'` in the build environment.

The CJMapping forwarder finalizer's CLI entry is currently unavailable because
`enableInteropCJMapping` has no option setter. Its source attribute is ported;
dynamic coverage is explicitly deferred by the lane's advisor ruling 143212Z.
