package cjcj::sema.NativeFFI.Java.BeforeTypeCheck

import cjcj::ast.Package
import cjcj::modules.SemaImportManager
import cjcj::sema.TypeManager

// C++ src/Sema/NativeFFI/Java/BeforeTypeCheck/PreTypeCheck.cpp:14-18.
public func PrepareTypeCheck(pkg: Package, importManager: SemaImportManager, typeManager: TypeManager): Unit {
    let jim = JavaInteropManager(importManager, typeManager)
    jim.Process(pkg)
}
