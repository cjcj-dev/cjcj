# Five LLVM query regressions

`check-machine.mjs COMPILER_ELF MODE OUTPUT.json` checks the normally rebuilt
compiler itself. Modes are `baseline` (all ordinary), `candidate` (five direct),
and `cut` (only TypeOf ordinary). BuildNeg must remain ordinary in every mode.
For the TypeOf annotation cut run the **candidate** assertion too: only TypeOf
must fail; the cut classification is diagnostic, not the red assertion.

Compile `queries.cj` together with the selected product
`packages/codegen/src/LLVM.cj` and `progress.c`, linking that compiler's LLVM
library and its normally produced shim. There are no copied query declarations.
The fixture checks integer widths, context identity, pointer address spaces,
other native type kinds, a live managed object across eight explicit collections,
and collector progress during an ordinary blocking C2N call. Its query loop must
retain a managed poll in generated code. The `suppress-completion` argument is
the finite negative control for the query progress assertion; it must fail at
`LEAF_ASSERT query-gc-progress`, after the ordinary native control passed.

Compile/run `semantics.cj` through each independent normal `bin/cjc` install.
Expected stdout: `LLVM_LEAF_COMPILER_SEMANTICS_OK` followed by newline.
Also compile/run the separately frozen Fountain source and independent oracle.
These correctness runs are not a performance experiment or a full SDK gate.
