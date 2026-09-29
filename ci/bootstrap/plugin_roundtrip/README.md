# CHIR plugin round-trip regression

Specification: upstream `src/CHIR/Transformation/ExecutePlugin.cpp:101-118`
and `src/CHIR/CHIR.cpp:1225-1252`. These tests run the real compiler CLI.

Build `../flatbuffer_borrowing_plugin.cj` with an **official host compiler**:
`cjc ../flatbuffer_borrowing_plugin.cj --output-type=dylib -o libpass.so`.
Build two variants with the same host and flags:

* `libreject.so`: replace `PluginResult(data, size, size > 4)` with
  `PluginResult(data, size, false)`; retain the cleanup callback.
* `libmissing.so`: omit `freeSerializedMemory` and its `@C` annotation.

Keep the normal fixture's snapshot and both printed boolean assertions.
The compiler executable's `../runtime/lib/<host>/libcangjie-runtime.so`
and the runtime selected by `LD_LIBRARY_PATH` must be the **same path**.
Use the matching official std libraries and the compiler's LLVM dependencies.
Do not build the plugins using a coloured SDK with an official host runtime.

Run into a new output directory:

```sh
python3 run.py --compiler /absolute/bin/cjcj-stage1 \
  --plugin /absolute/libpass.so --reject-plugin /absolute/libreject.so \
  --missing-free-plugin /absolute/libmissing.so --output /absolute/results
```

`results.json` records each command, return code, assertion and input binary
hash. Success requires an actual `.a` output. The runner evaluates all target
assertions even when the CLI fails. Run each arm in a separate directory;
within an arm the cases run in sequence to retain one compiler process at a
time and one unambiguous per-case log.

## Read-only product-state assertions

Successful compilation alone does not observe restored extension registration.
`relations.py` is a GDB script that reads the actual extension collections after
each iteration of `StringToCHIRPtr`, before later phases can conceal a missing
registration. It makes no inferior function calls and writes no product state.
It obtains the target type from the real getter's return register. Its JSON
records definition and owner addresses, type, collection contents and membership.

This observer is for the x86_64 official-host O1 build. Before reuse, inspect
`objdump -d --disassemble=<symbol>` for:

* `CustomType.GetCustomTypeDef`: object field `0x20`.
* `BuiltinType.AddExtend`: collection field `0x20`.
* `CustomTypeDef.AddExtend`: collection field `0xc0`.
* `ArrayList.add`: raw array `0x8`, slice offset `0x10`, capacity `0x18`,
  size `0x20`; reference elements start at raw-array offset `0x10`.
* Official HRT `IdleBarrier.ReadReference`: low 48 address bits. The observer
  rejects headers that require forwarding resolution; such a run is invalid.

The two classification arms cover Int/Float/Boolean/Rune/Unit/CString and
Struct/Class/Enum targets. CPointer canonicalization in the unchanged
`GetBuiltinTypeWithVTable` helper is explicitly recorded outside this observer's
type scope; it is not claimed as a validated relation. All input extensions are
still included in the census, and missing observations fail the script.

```sh
export RELATION_JSON=/absolute/relations.json
# Set the same SDK, runtime and LLVM environment as the ordinary CLI run.
gdb -q -batch -ex 'set pagination off' -ex 'set print thread-events off' \
  -ex 'handle SIGSEGV nostop noprint pass' \
  -ex 'handle SIGBUS nostop noprint pass' -x relations.py \
  --args /absolute/bin/cjcj-stage1 builtin.cj -O0 --output-type=staticlib \
  --output-dir /absolute/observed-output --plugin /absolute/libpass.so
```

Repeat for `custom.cj`. Delete only one product `AddExtend(definition)` call
per cut build. The builtin cut must fail only builtin membership assertions;
the custom cut must fail only custom membership assertions. Plain CLI controls
must remain successful. Restore the retained original compiler for the recovery
arm, and bind all results to ELF and dependency hashes.

`success_gate.py` observes the actual `ExecuteCjPlugins` return value and
whether `StringToCHIRPtr` returned. Use the same GDB command, changing `-x`, and
set `GATE_JSON` and `GATE_MODE=pass|reject|missing`. Its expected states are
respectively `(restored=1, result=true)`, `(restored=0, result=false)`, and
`(restored=1, result=false)`. Pair it with the CLI callback assertions above.
