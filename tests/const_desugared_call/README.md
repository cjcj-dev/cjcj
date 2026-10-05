# Repeated operator-call desugaring

Run `python3 run.py --compiler /absolute/cjcj-stage1 --sdk /absolute/host-sdk --out /absolute/results`.
The compiler must be built from the candidate source with its matching host libraries.
The runner copies the complete product ELF and invokes its `cjc-frontend --emit-chir=raw --output-type=staticlib`
entry through a same-directory alias, so backend generation cannot mask Sema diagnostics.

`empty`, `nonempty`, and `generic` call an instance with an Array-only `operator ()`
in a const function body. The compiler must reject the synthesized Array as
nonconstant and report the source call on line 9 with a nonzero column.
`control` exercises a scalar operator call without variadic desugaring.
Every assertion prints its result independently; a failed diagnostic assertion
cannot hide the source-position assertion. Each case has its own output directory.
The result records compiler/runtime hashes, actual compiler exit codes, affinity,
uptime, fixture hashes, and elapsed time. An internal compiler error is a failure.

Specification: upstream fdd47893726b186e30b342a9a33a15ec6b6221fe,
ConstEvaluationChecker.cpp:670, DesugarInTypeCheck.cpp:485/514,
PartialInstantiation.cpp:788. Tests require candidate/cut/restored execution;
source inspection alone does not establish coverage of each copied field.

The VISIBLE-only option table excludes `--typecheck`. `--emit-chir=raw` is a
visible GLOBAL option: ExecuteCompile runs through SEMA and CHIR, then skips
code generation and result saving. Entry failures stop all arms immediately.
Candidate/restored arms also stop on the first target failure; baseline/cut
arms use `--observe-failures` to collect authorized target observations.

The four fixtures are independent library packages, each with a public const
`invoke` function and no program entry. `--output-type=staticlib` sets
`outputMode=STATIC_LIB`; `CompileExecutable()` then returns false, so Sema's
`CheckWhetherHasProgramEntry` requires no main. `--emit-chir=raw` sets the
separate emit phase, without overriding that output mode. The frontend still
runs Sema, generic instantiation, mangling, CJO saving, AST-to-CHIR translation,
plugins (none requested), canonicalization, and RAW serialization. It then
skips backend generation and result saving; no linker, archive tool, external
symbol definitions, or native entry function are needed. Each case explicitly
writes its CHIR in its own output directory. The ordinary scalar control must
return zero through this complete path. Missing-main diagnostics are entry
failures in every arm, including baseline and deliberate cuts.
