# Macro task regressions (#692, #693)

`generate_inputs.py` preserves the macro full-task, remainder, recursive type,
generic and ordinary/lambda inputs from #692. `run.py` executes the default
compiler and compares its real single-worker and parallel symbol sets.

#693 removes ASTAdapter/MangleModels, including StoreTy's partial publication.
The old adapter synchronization fixture, its qualification hook and adapter
cut are deleted with that mechanism. No fixture is installed in the product.
The original input cases are also exercised by `../mangle_direct_ast/run.py`,
which compares CJO names/export IDs and LLVM symbols across compiler arms.
Direct-AST producer and consumer cuts are in `../mangle_direct_ast/cut.py`.

Specification: upstream CompilerInstance.cpp:794-810 and BaseMangler.cpp:221-232.
