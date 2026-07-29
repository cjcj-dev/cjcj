package cjcj::sema.NativeFFI.ObjC

import cjcj::ast.*
import cjcj::modules.SemaImportManager
import cjcj::sema.MemberMap
import cjcj::utils.{CJC_ASSERT, CJC_NULLPTR_CHECK, NATIVE_HANDLE_GETTER_IDENT, NATIVE_HANDLE_IDENT,
    SYNTHETIC_CLASS_SUFFIX}

// C++ src/Sema/NativeFFI/ObjC/Utils/Common.cpp:22-36.
private func GetMirrorSuperClass(target: ClassLikeDecl): Option<ClassDecl> {
    if (let Some(classDecl) <- (target as ClassDecl)) {
        if (let Some(superClass) <- classDecl.GetSuperClassDecl()) {
            if (TypeMapper.IsObjCMirror(superClass.GetTy().getOrThrow())) {
                return Some(superClass)
            }
            if (TypeMapper.IsObjCImpl(superClass.GetTy().getOrThrow())) {
                return GetMirrorSuperClass(superClass)
            }
        }
    }
    return None
}

// C++ src/Sema/NativeFFI/ObjC/Utils/Common.cpp:48-62.
private func GenerateSyntheticClassFuncStub(synthetic: ClassDecl, fd: FuncDecl): Unit {
    let funcStub = (ASTCloner.Clone(fd) as FuncDecl).getOrThrow()
    var index: Int64 = 0
    while (index < funcStub.annotations.size) {
        if (funcStub.annotations[index].kind == AnnotationKind.FOREIGN_NAME) {
            funcStub.annotations.remove(at: index)
            break
        }
        index++
    }
    funcStub.outerDecl = Some(synthetic)
    synthetic.body.getOrThrow().decls.add(funcStub)
}

// C++ src/Sema/NativeFFI/ObjC/Utils/Common.cpp:64-78.
private func GenerateSyntheticClassPropStub(synthetic: ClassDecl, pd: PropDecl): Unit {
    let propStub = (ASTCloner.Clone(pd) as PropDecl).getOrThrow()
    var index: Int64 = 0
    while (index < propStub.annotations.size) {
        if (propStub.annotations[index].kind == AnnotationKind.FOREIGN_NAME) {
            propStub.annotations.remove(at: index)
            break
        }
        index++
    }
    propStub.outerDecl = Some(synthetic)
    synthetic.body.getOrThrow().decls.add(propStub)
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
        if (TypeMapper.IsObjCMirror(parentTy)) {
            return true
        }
    }
    return false
}

// C++ src/Sema/NativeFFI/ObjC/Utils/Common.cpp:119-130.
public func GetNativeVarHandle(target: ClassDecl): Option<VarDecl> {
    let targetTy = target.GetTy().getOrThrow()
    CJC_ASSERT(TypeMapper.IsObjCMirror(targetTy) || TypeMapper.IsObjCImpl(targetTy) ||
        TypeMapper.IsSyntheticWrapper(target) || TypeMapper.IsObjCFwdClass(target))

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
    CJC_ASSERT(TypeMapper.IsObjCMirror(targetTy) || TypeMapper.IsObjCImpl(targetTy) ||
        TypeMapper.IsSyntheticWrapper(target) || TypeMapper.IsObjCFwdClass(target))

    if (let Some(mirrorSuperClass) <- GetMirrorSuperClass(target)) {
        return GetNativeHandleGetter(mirrorSuperClass)
    }
    if (let Some(member) <- FindMirrorMember(NATIVE_HANDLE_GETTER_IDENT, target)) {
        return member as FuncDecl
    }
    return None
}

// C++ src/Sema/NativeFFI/ObjC/Utils/Common.cpp:155-165.
public func GetSyntheticWrapper(importManager: SemaImportManager, target: ClassLikeDecl): Option<ClassDecl> {
    CJC_ASSERT(TypeMapper.IsObjCMirror(target.GetTy().getOrThrow()))
    let synthetic = importManager.GetImportedDecl<ClassDecl>(target.fullPackageName,
        target.identifier.Val() + SYNTHETIC_CLASS_SUFFIX)
    CJC_NULLPTR_CHECK(synthetic)
    CJC_ASSERT(IsSyntheticWrapper(synthetic.getOrThrow()))
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

// C++ src/Sema/NativeFFI/ObjC/Utils/Common.cpp:178-181.
public func IsSyntheticWrapper(decl: Decl): Bool {
    return TypeMapper.IsSyntheticWrapper(decl.GetTy().getOrThrow())
}

// C++ src/Sema/NativeFFI/ObjC/Utils/Common.cpp:183-204.
public func GenerateSyntheticClassAbstractMemberImplStubs(synthetic: ClassDecl, members: MemberMap): Unit {
    for (entry in members.entries) {
        let decl = entry.signature.decl.getOrThrow()
        if (!decl.TestAttr(Attribute.ABSTRACT)) {
            continue
        }

        match (decl.astKind) {
            case ASTKind.FUNC_DECL =>
                GenerateSyntheticClassFuncStub(synthetic, (decl as FuncDecl).getOrThrow())
            case ASTKind.PROP_DECL =>
                GenerateSyntheticClassPropStub(synthetic, (decl as PropDecl).getOrThrow())
            case _ => continue
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/Utils/Common.cpp:206-212.
public func GetImplSuperClass(target: ClassDecl): Option<ClassDecl> {
    let superClass = target.GetSuperClassDecl()
    CJC_NULLPTR_CHECK(superClass)
    if (TypeMapper.IsObjCImpl(superClass.getOrThrow())) {
        return superClass
    }
    return None
}

// C++ src/Sema/NativeFFI/ObjC/Utils/Common.cpp:214-217.
public func HasImplSuperClass(target: ClassDecl): Bool {
    return GetImplSuperClass(target).isSome()
}
