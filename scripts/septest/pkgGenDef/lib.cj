package pkgGenDef

// Generic function WITH a default parameter. On import, the compiler-synthesized
// default-param desugar function carries renamed generics (<T$0>); the importer must
// set its ownerFunc so the mangler can declare those generics (C++ ASTLoader.cpp:829-833).
public func gfn<T>(x: T, y!: T = x): T { return y }
