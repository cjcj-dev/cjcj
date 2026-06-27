package cangjie_compiler::utils

// PORT-DEFERRED: CastASTTests.cpp and CastTyTests.cpp validate C++ template instantiation,
// dynamic_cast/static_cast parity, and generated C++ include tables. The selfhost does not expose an
// equivalent RTTI/template casting surface in package utils, and the tested AST/Ty owners are downstream
// packages that depend on utils.
