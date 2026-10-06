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

Diagnostic classification is separate from the target assertions. A compiler
exit of 1 without a recognized diagnostic is UNKNOWN_FAIL and stops the batch.
Invalid options and missing main remain ENTRY_FAILURE; ICE and abnormal exit
remain INTERNAL_OR_EXECUTION_FAILURE. The zero-position Array diagnostic is
TARGET_CONST_BAD_LOCATION only when the same error block contains the exact
const error, `==> :0:0:` and the VArray<Int64, $N> note, with generated/printed
error counts matching all error blocks. It passes the rejection identity check
and fails the call-site position check. Notes from another error or warning
cannot supply this identity. Normal diagnostics still require the Array hint
and fixture position. Successful baseline/cut compilations still fail the two
target assertions, and every assertion is printed independently.

The Array-specific CopyBasicInfo has a separate comments-fidelity obligation;
its location fields are also copied by the common InstantiateExpr tail. The
four const fixtures do not establish Array cloning. A clone marker test cannot
currently be admitted through this compiler CLI: enableAddCommentToAst defaults
to false (Option.cj:325), has no enabling assignment, and --dump-ast only sets
dumpAST (OptionAction.cj:212). CompileStrategy.cj:419 passes that false value to
the parser; ParseDecl.cj:127 consequently skips AttachCommentToFile. An AST dump
consumer alone does not prove comment production. No clone fixture or product
execution is supplied for this blocked obligation.

## Non-CLI Array clone metadata

`packages/compiler_unittest/src/ArrayCloneMetadata_test.cj` uses the public
CompilerInvocation with comments enabled, O2, STATIC_LIB and nonincremental
compilation through GENERIC_INSTANTIATION. Its single fixed source is parsed
from a real private file. It follows genericDecl/objectId to the clone and
checks the template Array<T>, clone Array<Int64>, token groups/positions,
node positions, children and PrintNode(clone) independently. Qualification
failures stop the comments arm; the marker is never relocated.

After a normal product build (retain target/release and runtime_shim objects):

```sh
python3 scripts/test_array_clone_metadata_unit.py --build-tree /absolute/product/tree \
  --sdk /absolute/private/host-sdk --out /absolute/private/metadata-evidence
```

This links only the test source to actual release archives. It does not build
product source or run the full unit suite. Each product comments cut requires
fresh archives and a new static test link. Only removing InstantiateArrayLit's
CopyBasicInfo call should fail clone_comments and clone_print_marker; all
controls must still pass. This is not a new CLI comment option.
