package cjcj::sema.NativeFFI.Java

import std.collection.ArrayList
import cjcj::ast.*
import cjcj::utils.CJC_ASSERT

// C++ src/Sema/NativeFFI/Java/Utils.cpp:32-38.
public func GetMirrorReferenceWrapperNameFromClassLike(mirrorDecl: ClassLikeDecl): String {
    let wrapperNameSuffix = "$impl"
    CJC_ASSERT(mirrorDecl.IsInterfaceDecl() || mirrorDecl.IsAbstractClass())
    CJC_ASSERT(IsMirror(mirrorDecl))
    return mirrorDecl.identifier.Val() + wrapperNameSuffix
}

// C++ src/Sema/NativeFFI/Java/Utils.cpp:40-45.
public func GetImplRegistryCompanionClassName(javaImplDecl: ClassLikeDecl): String {
    let wrapperNameSuffix = "$reg"
    CJC_ASSERT(IsImpl(javaImplDecl))
    return javaImplDecl.identifier.Val() + wrapperNameSuffix
}

// C++ src/Sema/NativeFFI/Java/Utils.cpp:47-57.
public func GetJavaMirrors(file: File): ArrayList<ClassLikeDecl> {
    let mirrors = ArrayList<ClassLikeDecl>()
    for (decl in file.decls) {
        if (IsMirror(decl)) {
            let mirror = decl as ClassLikeDecl
            CJC_ASSERT(mirror.isSome())
            mirrors.add(mirror.getOrThrow())
        }
    }
    return mirrors
}

// C++ src/Sema/NativeFFI/Java/Utils.cpp:59-67.
public func GetJavaMirrors(pkg: Package): ArrayList<ClassLikeDecl> {
    let mirrors = ArrayList<ClassLikeDecl>()
    for (file in pkg.files) {
        for (mirror in GetJavaMirrors(file)) {
            mirrors.add(mirror)
        }
    }
    return mirrors
}

// C++ src/Sema/NativeFFI/Java/Utils.cpp:69-80.
public func GetJavaImpls(file: File): ArrayList<ClassDecl> {
    let impls = ArrayList<ClassDecl>()
    for (decl in file.decls) {
        if (IsImpl(decl)) {
            if (let Some(impl) <- (decl as ClassDecl)) {
                impls.add(impl)
            }
        }
    }
    return impls
}

// C++ src/Sema/NativeFFI/Java/Utils.cpp:82-90.
public func GetJavaImpls(pkg: Package): ArrayList<ClassDecl> {
    let impls = ArrayList<ClassDecl>()
    for (file in pkg.files) {
        for (impl in GetJavaImpls(file)) {
            impls.add(impl)
        }
    }
    return impls
}
