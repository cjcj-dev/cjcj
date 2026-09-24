package cjcj::sema.NativeFFI.ObjC

import cjcj::ast.*
import cjcj::ast.AnnotationKind as AstAnnotationKind
import cjcj::modules.SemaImportManager
import cjcj::sema.MemberMap
import cjcj::utils.{CJC_ASSERT, CJC_NULLPTR_CHECK, NATIVE_HANDLE_GETTER_IDENT, NATIVE_HANDLE_IDENT}

// C++ src/Sema/NativeFFI/ObjC/Utils/Common.cpp:22-36.
private func GetMirrorSuperClass(target: ClassLikeDecl): Option<ClassDecl> {
    if (let Some(classDecl) <- (target as ClassDecl)) {
        if (let Some(superClass) <- classDecl.GetSuperClassDecl()) {
            if (IsObjCMirror(superClass.GetTy().getOrThrow())) {
                return Some(superClass)
            }
            if (IsObjCImpl(superClass.GetTy().getOrThrow())) {
                return GetMirrorSuperClass(superClass)
            }
        }
    }
    return None
}

// C++ src/Sema/NativeFFI/ObjC/Utils/Common.cpp:82-91.
public func FindMirrorMember(mirrorMemberIdent: String, target: InheritableDecl): Option<Decl> {
    for (memberDecl in target.GetMemberDeclPtrs()) {
        if (memberDecl.identifier == mirrorMemberIdent) {
            return Some(memberDecl)
        }
    }
    return None
}

// C++ src/Sema/NativeFFI/ObjC/Utils/Common.cpp:93-101.
public func FindMirrorMember(target: InheritableDecl, pred: (Decl) -> Bool): Option<Decl> {
    for (decl in target.GetMemberDeclPtrs()) {
        if (pred(decl)) {
            return Some(decl)
        }
    }
    return None
}

// C++ src/Sema/NativeFFI/ObjC/Utils/Common.cpp:103-106.
public func HasMirrorSuperClass(target: ClassLikeDecl): Bool {
    return GetMirrorSuperClass(target).isSome()
}

// C++ src/Sema/NativeFFI/ObjC/Utils/Common.cpp:108-117.
public func HasMirrorSuperInterface(target: ClassLikeDecl): Bool {
    for (parentTy in target.GetSuperInterfaceTys()) {
        if (IsObjCMirror(parentTy)) {
            return true
        }
    }
    return false
}

// C++ src/Sema/NativeFFI/ObjC/Utils/Common.cpp:119-130.
public func GetNativeVarHandle(target: ClassDecl): Option<VarDecl> {
    let targetTy = target.GetTy().getOrThrow()
    CJC_ASSERT(IsObjCMirror(targetTy) || IsObjCImpl(targetTy) ||
        IsObjCMirrorInterfaceHandleWrapper(target) || IsObjCFwdClass(target))

    if (let Some(mirrorSuperClass) <- GetMirrorSuperClass(target)) {
        return GetNativeVarHandle(mirrorSuperClass)
    }
    if (let Some(member) <- FindMirrorMember(NATIVE_HANDLE_IDENT, target)) {
        return member as VarDecl
    }
    return None
}

// C++ src/Sema/NativeFFI/ObjC/Utils/Common.cpp:132-140.
public func IsStaticInitMethod(node: Node): Bool {
    if (let Some(fd) <- (node as FuncDecl)) {
        return fd.TestAttr(Attribute.OBJ_C_INIT)
    }
    return false
}

// C++ src/Sema/NativeFFI/ObjC/Utils/Common.cpp:142-153.
public func GetNativeHandleGetter(target: ClassLikeDecl): Option<FuncDecl> {
    let targetTy = target.GetTy().getOrThrow()
    CJC_ASSERT(IsObjCMirror(targetTy) || IsObjCImpl(targetTy) ||
        IsObjCMirrorInterfaceHandleWrapper(target) || IsObjCFwdClass(target))

    if (let Some(mirrorSuperClass) <- GetMirrorSuperClass(target)) {
        return GetNativeHandleGetter(mirrorSuperClass)
    }
    if (let Some(member) <- FindMirrorMember(NATIVE_HANDLE_GETTER_IDENT, target)) {
        return member as FuncDecl
    }
    return None
}

// C++ src/Sema/NativeFFI/ObjC/Utils/Common.cpp:155-165.
public func GetObjCMirrorInterfaceHandleWrapper(importManager: SemaImportManager, target: ClassLikeDecl): Option<ClassDecl> {
    CJC_ASSERT(IsObjCMirror(target.GetTy().getOrThrow()))
    let synthetic = importManager.GetImportedDecl<ClassDecl>(target.fullPackageName,
        NameGenerator.GenerateHandleWrapperName(target))
    CJC_NULLPTR_CHECK(synthetic)
    CJC_ASSERT(IsObjCMirrorInterfaceHandleWrapper(synthetic.getOrThrow()))
    return synthetic
}

// C++ src/Sema/NativeFFI/ObjC/Utils/Common.cpp:167-176.
public func GetFinalizer(target: ClassDecl): Option<FuncDecl> {
    for (member in target.GetMemberDeclPtrs()) {
        if (member.TestAttr(Attribute.FINALIZER)) {
            return member as FuncDecl
        }
    }
    return None
}

// C++ src/Sema/NativeFFI/ObjC/Utils/Common.cpp:206-212.
public func GetImplSuperClass(target: ClassDecl): Option<ClassDecl> {
    let superClass = target.GetSuperClassDecl()
    CJC_NULLPTR_CHECK(superClass)
    if (IsObjCImpl(superClass.getOrThrow())) {
        return superClass
    }
    return None
}

// C++ src/Sema/NativeFFI/ObjC/Utils/Common.cpp:214-217.
public func HasImplSuperClass(target: ClassDecl): Bool {
    return GetImplSuperClass(target).isSome()
}
