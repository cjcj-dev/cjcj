# ObjC CPointer and internal constructor markers

Run the real stage1 compiler against fixture-only `objc.internal` / `objc.lang`
modules, then inspect its desugared AST. The modules are compiled by that same
stage1 and are not an Objective-C runtime. Linux results do not establish Darwin
execution or runtime glue correctness (cjcj#201).

```
CANGJIE_HOME=/absolute/private/sdk \
LD_LIBRARY_PATH=/absolute/private/sdk/runtime/lib/linux_x86_64_cjnative:/absolute/private/sdk/lib/linux_x86_64_cjnative:/absolute/private/sdk/third_party/llvm/lib \
  scripts/objc_cpointer_gate.sh /absolute/cjcj-stage1 /absolute/evidence \
  '^(CPointer|NonCompatible|Integer|PointerMirror|PointerChild|Mirror)\.'
```

The optional third argument selects assertion names with a regular expression;
omitting it runs every assertion. It does not change the compiler inputs. Each
fixture runs in parallel with a separate output directory and records the real
compiler exit status, AST, diagnostics, source hashes and compiler hash. The
compiler is built with the repository's `-O1` stage1 recipe, without test hooks.

The primary set checks pointer acceptance, rejection of an incompatible struct,
a plain integer control, marker formals for both mirror constructors, marker
actuals for `this` / `super` calls and returned-mirror wrapping. The additional
impl and NSString assertions remain available individually or in the full set.
No failing assertion is removed or treated as a success.

The stub module's generic bodies only make declarations serializable; they are
never executed as an ObjC runtime. The fixture compiler uses `--emit-chir=raw`.

For fault-injection arms, pass a fourth argument naming the green arm’s `import`
directory. The runner physically copies those exact modules and hashes them, so
only the compiler ELF changes between arms. Without that argument the modules
are built by the supplied compiler. Each compiler process has its own directory.
