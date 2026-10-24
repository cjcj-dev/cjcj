# Reference producer finite checks

The `.cj` fixtures and `read_chir.cj` are unchanged source inputs from
`af00841cb5e0c6243bfe5894fa2c594b9c882e4f:tests/finalizer_registration`.
`run.mjs` carries its CHIR assertions into the current script format. Run only
under the normal remote workflow and the assigned CPU/memory scope:

```
node test/reference_producer/run.mjs <installed-cjc> <new-output> <product-chir-reader>
```

Build the reader from `read_chir.cj` using the actual candidate CHIR package
archive and its normal dependencies. Passing no reader runs frontend checks
only; it does not grant serialization roundtrip coverage.

The fixtures use a minimal core solely for CHIR checks: root/derived/delegated
constructor edges, finalizable constant batches, temporary finalizers, shared
identity and non-finalizable/scalar controls, at O0/O2 before and after CHIR
optimization. Every compile records its own exit/signal and original output.
Missing artifacts remain NOT_RUN. Reader checks consume the binary CHIR emitted
by that same compiler. Minimal fixtures are not used for core IR or runtime
qualification.

Real code generation, core method publication, weak/final reference fields,
volatile queue fields and runtime loading must use the full fixed std0dbd
native graph with the fixed R0e/N installation. Preserve the existing full-graph
failure and build cache. Rebuild and install the complete standard library;
neither these tests nor an old std archive can substitute for that result.

The product cut removes the root-return registration call in
`Translator.Visit(AstFuncDecl)`; rebuild the candidate CHIR/compiler normally,
then rerun the same fixtures and reader. Root/derived/constant-finalizer targets
must reject, while the scalar-fold and plain-constant-materialization assertions
remain valid. The const_plain case also checks the root constructor, so its
overall cut status is FAIL; only its separate materialization check is an
independent control. Restore the
fixed source and rebuild before recovery. A crash or early compilation error
does not count as a precise target assertion failure.

After running all three arms with the actual product reader, use
`verify-arms.mjs candidate/results.json cut/results.json restored/results.json
new-comparison.json`. It requires all 32 inputs, successful compilation before
the assertions, the expected target rejections, all four scalar/plain control
checks, and six binary-CHIR reader executions per arm. Reader exit 1 counts only
with its reached target marker; signals and earlier failures reject the arm.
This is a prepared check, not a record of an executed test.
