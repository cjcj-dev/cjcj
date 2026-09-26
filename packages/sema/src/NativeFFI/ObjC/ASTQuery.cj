package cjcj::sema.NativeFFI.ObjC

import cjcj::ast.*
import cjcj::modules.SemaImportManager
import cjcj::utils.{NATIVE_HANDLE_GETTER_IDENT, NATIVE_HANDLE_IDENT}
import std.collection.ArrayList
import cjcj::utils.{CJC_ABORT, CJC_ASSERT, CJC_NULLPTR_CHECK, OBJ_C_BLOCK_IDENT, OBJ_C_FUNC_IDENT,
    OBJ_C_ID_IDENT, OBJ_C_LANG_PACKAGE_IDENT, OBJ_C_POINTER_IDENT}

// Upstream a51ced71, ObjC/Utils/ASTQuery.cpp: IsObjCImplRegistryCompanion / GetOwnerClass.
public func IsObjCImplRegistryCompanion(decl: Decl): Bool {
    return decl.TestAttr(Attribute.OBJ_C_IMPL_REGISTRY_COMPANION)
}

public func IsObjCImplMovedMemberProxy(decl: Decl): Bool {
    return decl.TestAttr(Attribute.OBJ_C_IMPL_MOVED_MEMBER_PROXY)
}

public func GetOwnerClass(decl: Decl): Option<ClassDecl> {
    if (let Some(outer) <- decl.outerDecl) {
        return outer as ClassDecl
    }
    return None
}

public func IsObjCImplRegistryCompanionField(decl: Decl): Bool {
    return decl.identifier.Val() == "$reg"
}

public func GetObjCImplRegCompanionField(impl: ClassDecl): Option<VarDecl> {
    for (member in impl.GetMemberDecls()) {
        if (let Some(field) <- (member as VarDecl)) {
            if (IsObjCImplRegistryCompanionField(field)) {
                return Some(field)
            }
        }
    }
    return None
}

private func IsObjCPointerImpl(structDecl: StructDecl): Bool {
    if (structDecl.fullPackageName != OBJ_C_LANG_PACKAGE_IDENT) { return false }
    if (structDecl.identifier.Val() != OBJ_C_POINTER_IDENT) { return false }
    return true
}

private func IsObjCFuncImpl(structDecl: StructDecl): Bool {
    if (structDecl.fullPackageName != OBJ_C_LANG_PACKAGE_IDENT) { return false }
    if (structDecl.identifier.Val() != OBJ_C_FUNC_IDENT) { return false }
    return true
}

private func IsObjCBlockImpl(decl: ClassDecl): Bool {
    if (decl.fullPackageName != OBJ_C_LANG_PACKAGE_IDENT) { return false }
    if (decl.identifier.Val() != OBJ_C_BLOCK_IDENT) { return false }
    return true
}

public func IsObjCCompatible(ty: Ty): Bool {
    match (ty.kind) {
        case TypeKind.TYPE_UNIT | TypeKind.TYPE_INT8 | TypeKind.TYPE_INT16 | TypeKind.TYPE_INT32 | TypeKind.TYPE_INT64 |
            TypeKind.TYPE_INT_NATIVE | TypeKind.TYPE_IDEAL_INT | TypeKind.TYPE_UINT8 | TypeKind.TYPE_UINT16 | TypeKind.TYPE_UINT32 |
            TypeKind.TYPE_UINT64 | TypeKind.TYPE_UINT_NATIVE | TypeKind.TYPE_FLOAT32 | TypeKind.TYPE_FLOAT64 | TypeKind.TYPE_IDEAL_FLOAT |
            TypeKind.TYPE_BOOLEAN => return true
        case TypeKind.TYPE_STRUCT =>
            if (IsObjCPointer(ty)) { CJC_ASSERT(ty.typeArgs.size == 1); return IsObjCCompatible(ty.typeArgs[0]) }
            if (Ty.IsCStructType(ty)) { return true }
            if (IsObjCFunc(ty)) {
                CJC_ASSERT(ty.typeArgs.size == 1); let tyArg = ty.typeArgs[0]
                if (!tyArg.IsFunc() || tyArg.IsCFunc()) { return false }
                for (arg in tyArg.typeArgs) { if (!IsObjCCompatible(arg)) { return false } }
                return true
            }
            return false
        case TypeKind.TYPE_CLASS | TypeKind.TYPE_INTERFACE =>
            if (IsObjCMirror(ty) || IsObjCImpl(ty)) { return true }
            if (IsObjCBlock(ty)) {
                CJC_ASSERT(ty.typeArgs.size == 1); let tyArg = ty.typeArgs[0]
                if (!tyArg.IsFunc() || tyArg.IsCFunc()) { return false }
                for (arg in tyArg.typeArgs) { if (!IsObjCCompatible(arg)) { return false } }
                return true
            }
            return false
        case TypeKind.TYPE_ENUM =>
            if (!ty.IsCoreOptionType()) { return false }
            CJC_ASSERT(ty.typeArgs.size == 1)
            if (IsObjCMirror(ty.typeArgs[0]) || IsObjCImpl(ty.typeArgs[0])) { return true }
        case TypeKind.TYPE_FUNC => if (ty.IsCFunc()) { return true }
        case TypeKind.TYPE_CSTRING => if (ty.IsCString()) { return true }
        case TypeKind.TYPE_POINTER => return true
        case _ => return false
    }
    return false
}

// Upstream 1e741869, TypeMapper.cpp:304; type predicates live in ASTQuery.
public func IsObjCCompatibleFuncTy(ty: Ty): Bool {
    let fTy = ty as FuncTy
    if (fTy.isNone()) {
        return false
    }
    let value = fTy.getOrThrow()
    if (value.isC) {
        return false
    }
    if (!IsObjCCompatible(value.retTy)) {
        return false
    }
    for (argTy in value.paramTys) {
        if (!IsObjCCompatible(argTy)) {
            return false
        }
    }
    return true
}

public func IsObjCMirror(decl: Decl): Bool { return decl.TestAttr(Attribute.OBJ_C_MIRROR) }
public func IsObjCMirrorInterfaceHandleWrapper(decl: Decl): Bool { return decl.TestAttr(Attribute.OBJ_C_MIRROR_INTERFACE_HANDLE_WRAPPER) }
public func IsObjCMirrorSubtype(decl: Decl): Bool { let ty = decl.GetTy(); CJC_NULLPTR_CHECK(ty); return IsObjCMirrorSubtype(ty.getOrThrow()) }
public func IsObjCImpl(decl: Decl): Bool { return decl.TestAttr(Attribute.OBJ_C_IMPL) }

public func IsObjCMirrorSubtype(ty: Ty): Bool {
    if (let Some(it) <- (ty as InterfaceTy)) {
        return HasMirrorSuperInterface(it.declPtr.getOrThrow())
    }
    let ct = ty as ClassTy
    if (ct.isNone()) { return false }
    let value = ct.getOrThrow()
    let hasMirrorSuperInterface = HasMirrorSuperInterface(value.decl.getOrThrow())
    let parent = value.GetSuperClassTy()
    if (parent.isNone() || parent.getOrThrow().IsObject()) { return hasMirrorSuperInterface }
    return IsObjCMirrorSubtype(parent.getOrThrow()) || IsObjCMirror(parent.getOrThrow())
}

public func IsObjCImpl(ty: Ty): Bool { if (let Some(value) <- (ty as ClassLikeTy)) { if (let Some(decl) <- value.commonDecl) { return IsObjCImpl(decl) } }; return false }
public func IsObjCMirror(ty: Ty): Bool { if (let Some(value) <- (ty as ClassLikeTy)) { if (let Some(decl) <- value.commonDecl) { return IsObjCMirror(decl) } }; return false }
public func IsObjCMirrorInterfaceHandleWrapper(ty: Ty): Bool { if (let Some(value) <- (ty as ClassLikeTy)) { if (let Some(decl) <- value.commonDecl) { return IsObjCMirrorInterfaceHandleWrapper(decl) } }; return false }
public func IsObjCObjectType(ty: Ty): Bool { if (ty.IsCoreOptionType()) { CJC_ASSERT(ty.typeArgs.size == 1); return IsObjCObjectType(ty.typeArgs[0]) }; return IsObjCMirror(ty) || IsObjCImpl(ty) || IsObjCMirrorInterfaceHandleWrapper(ty) }
public func IsObjCPointer(decl: Decl): Bool { if (let Some(value) <- (decl as StructDecl)) { return IsObjCPointerImpl(value) }; return false }
public func IsObjCPointer(ty: Ty): Bool { if (let Some(value) <- (ty as StructTy)) { if (let Some(decl) <- value.decl) { return IsObjCPointerImpl(decl) } }; return false }
public func IsObjCFunc(decl: Decl): Bool { if (let Some(value) <- (decl as StructDecl)) { return IsObjCFuncImpl(value) }; return false }
public func IsObjCFunc(ty: Ty): Bool { if (let Some(value) <- (ty as StructTy)) { if (let Some(decl) <- value.decl) { return IsObjCFuncImpl(decl) } }; return false }
public func IsObjCBlock(decl: Decl): Bool { if (let Some(value) <- (decl as ClassDecl)) { return IsObjCBlockImpl(value) }; return false }
public func IsObjCBlock(ty: Ty): Bool { if (let Some(value) <- (ty as ClassTy)) { if (let Some(decl) <- value.decl) { return IsObjCBlockImpl(decl) } }; return false }
public func IsObjCFuncOrBlock(decl: Decl): Bool { return IsObjCFunc(decl) || IsObjCBlock(decl) }
public func IsObjCFuncOrBlock(ty: Ty): Bool { return IsObjCFunc(ty) || IsObjCBlock(ty) }
public func IsObjCId(ty: Ty): Bool { if (let Some(value) <- (ty as InterfaceTy)) { if (let Some(decl) <- value.declPtr) { return IsObjCId(decl) } }; return false }
public func IsObjCId(decl: Decl): Bool { return decl.fullPackageName == OBJ_C_LANG_PACKAGE_IDENT && decl.identifier.Val() == OBJ_C_ID_IDENT }
// Upstream a51ced71, ObjC/Utils/ASTQuery.cpp:419-650.
public func IsNativeObjCIdMarker(ty: Ty): Bool {
    if (let Some(st) <- (ty as StructTy)) {
        if (let Some(decl) <- st.decl) {
            return decl.fullPackageName == "objc.internal" && decl.identifier.Val() == "NativeObjCIdMarker"
        }
    }
    return false
}

private func GetCtorParams(fd: FuncDecl): Option<ArrayList<FuncParam>> {
    if (!fd.TestAttr(Attribute.CONSTRUCTOR) || fd.funcBody.isNone() || fd.funcBody.getOrThrow().paramLists.isEmpty()) {
        return None
    }
    return Some(fd.funcBody.getOrThrow().paramLists[0].params)
}

private func IsNativeObjCIdMarkerParam(param: FuncParam): Bool {
    return Ty.IsTyCorrect(param.GetTy()) && IsNativeObjCIdMarker(param.GetTy().getOrThrow())
}

private func IsNativeHandleParam(param: FuncParam): Bool {
    return Ty.IsTyCorrect(param.GetTy()) && param.GetTy().getOrThrow().IsPointer()
}

private func HasNativeHandleBaseCtorSignature(fd: FuncDecl): Bool {
    if (let Some(params) <- GetCtorParams(fd)) { return params.size == 1 && IsNativeHandleParam(params[0]) }
    return false
}

private func HasObjCMirrorBaseCtorSignature(fd: FuncDecl): Bool {
    if (let Some(params) <- GetCtorParams(fd)) {
        return params.size == 2 && IsNativeHandleParam(params[0]) && IsNativeObjCIdMarkerParam(params[1])
    }
    return false
}

private func HasObjCImplBaseCtorSignature(fd: FuncDecl): Bool {
    if (let Some(params) <- GetCtorParams(fd)) {
        return params.size == 3 && IsNativeHandleParam(params[0]) && IsNativeObjCIdMarkerParam(params[2])
    }
    return false
}

public func GetFuncMember(decl: ClassDecl, predicate: (FuncDecl) -> Bool): Option<FuncDecl> {
    for (member in decl.GetMemberDeclPtrs()) {
        if (let Some(fd) <- (member as FuncDecl)) { if (predicate(fd)) { return Some(fd) } }
    }
    return None
}

private func IsLegacyObjCMirror(mirror: ClassDecl): Bool {
    return mirror.TestAttr(Attribute.IMPORTED) && GetFuncMember(mirror, HasObjCMirrorBaseCtorSignature).isNone()
}

public func HasNativeObjCIdMarkerParam(fd: FuncDecl): Bool {
    if (fd.funcBody.isNone() || fd.funcBody.getOrThrow().paramLists.isEmpty()) { return false }
    for (param in fd.funcBody.getOrThrow().paramLists[0].params) {
        if (IsNativeObjCIdMarkerParam(param)) { return true }
    }
    return false
}

public func IsObjCMirrorBaseCtor(fd: FuncDecl): Bool {
    if (let Some(owner) <- GetOwnerClass(fd)) {
        return IsObjCMirror(owner) && (HasObjCMirrorBaseCtorSignature(fd) ||
            (HasNativeHandleBaseCtorSignature(fd) && IsLegacyObjCMirror(owner)))
    }
    return false
}

public func IsObjCMirrorInterfaceHandleWrapperBaseCtor(fd: FuncDecl): Bool {
    if (let Some(owner) <- GetOwnerClass(fd)) {
        return IsObjCMirrorInterfaceHandleWrapper(owner) && HasNativeHandleBaseCtorSignature(fd)
    }
    return false
}

public func IsObjCImplRegCompanionBaseCtor(fd: FuncDecl): Bool {
    if (let Some(owner) <- GetOwnerClass(fd)) {
        return IsObjCImplRegistryCompanion(owner) && HasNativeHandleBaseCtorSignature(fd)
    }
    return false
}

public func IsObjCImplBaseCtor(fd: FuncDecl): Bool {
    if (let Some(owner) <- GetOwnerClass(fd)) { return IsObjCImpl(owner) && HasObjCImplBaseCtorSignature(fd) }
    return false
}

public func IsBaseCtor(fd: FuncDecl): Bool {
    return IsObjCImplBaseCtor(fd) || IsObjCMirrorBaseCtor(fd) ||
        IsObjCMirrorInterfaceHandleWrapperBaseCtor(fd) || IsObjCImplRegCompanionBaseCtor(fd)
}
public func GetBaseCtor(decl: ClassDecl): Option<FuncDecl> { return GetFuncMember(decl, IsBaseCtor) }
public func GetObjCMirrorBaseCtor(decl: ClassDecl): Option<FuncDecl> { return GetFuncMember(decl, IsObjCMirrorBaseCtor) }
public func GetObjCImplBaseCtor(decl: ClassDecl): Option<FuncDecl> { return GetFuncMember(decl, IsObjCImplBaseCtor) }
public func GetObjCMirrorInterfaceHandleWrapperBaseCtor(decl: ClassDecl): Option<FuncDecl> {
    return GetFuncMember(decl, IsObjCMirrorInterfaceHandleWrapperBaseCtor)
}
public func GetObjCImplRegCompanionBaseCtor(decl: ClassDecl): Option<FuncDecl> {
    return GetFuncMember(decl, IsObjCImplRegCompanionBaseCtor)
}
public func GetObjCImplRegistryCompanionSuperClass(decl: ClassDecl): Option<ClassDecl> {
    if (let Some(parent) <- decl.GetSuperClassDecl()) {
        if (IsObjCImplRegistryCompanion(parent)) { return Some(parent) }
    }
    return None
}

public func IsObjCImplRegDataCtor(fd: FuncDecl): Bool {
    if (let Some(params) <- GetCtorParams(fd)) {
        if (params.isEmpty()) { return false }
        if (let Some(tupleTy) <- (params[0].GetTy().getOrThrow() as TupleTy)) {
            if (tupleTy.typeArgs.size != 2) { return false }
            if (let Some(decl) <- Ty.GetDeclOfTy(tupleTy.typeArgs[1])) { return IsObjCImplRegistryCompanion(decl) }
        }
    }
    return false
}

public func GetObjCImplRegDataCtor(impl: ClassDecl, origin: FuncDecl): Option<FuncDecl> {
    CJC_ASSERT(!origin.funcBody.getOrThrow().paramLists.isEmpty())
    let originParams = origin.funcBody.getOrThrow().paramLists[0].params
    for (member in impl.GetMemberDeclPtrs()) {
        if (let Some(fd) <- (member as FuncDecl)) {
            if (!IsObjCImplRegDataCtor(fd)) { continue }
            CJC_ASSERT(!fd.funcBody.getOrThrow().paramLists.isEmpty())
            let params = fd.funcBody.getOrThrow().paramLists[0].params
            if (params.size != originParams.size + 1) { continue }
            var matched = true
            for (i in 1..params.size) {
                if (params[i].GetTy() != originParams[i - 1].GetTy()) { matched = false; break }
            }
            if (matched) { return Some(fd) }
        }
    }
    return None
}

public func IsObjCImplUserCtor(fd: FuncDecl): Bool {
    return fd.TestAttr(Attribute.CONSTRUCTOR) && !IsObjCImplBaseCtor(fd) && !IsObjCImplRegDataCtor(fd)
}

// Upstream a51ced71, ASTQuery.cpp:674-694.
public func IsGeneratedMember(decl: Decl): Bool {
    if (decl.identifier.Val() == "$obj" || decl.identifier.Val() == "$getObjCClass") { return true }
    if (decl.identifier.Val() == "$getObj" || IsObjCImplRegistryCompanionField(decl)) { return true }
    if (decl.TestAttr(Attribute.HAS_INITED_FIELD)) { return true }
    if (let Some(fd) <- (decl as FuncDecl)) {
        return IsBaseCtor(fd) || IsObjCImplRegDataCtor(fd) || IsGeneratedStringConversion(fd)
    }
    return false
}

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
public func GetNativeHandleField(target: ClassDecl): Option<VarDecl> {
    var current: Option<ClassDecl> = Some(target)
    while (let Some(decl) <- current) {
        for (member in decl.GetMemberDeclPtrs()) {
            if (member.identifier.Val() == NATIVE_HANDLE_IDENT) {
                if (let Some(field) <- (member as VarDecl)) { return Some(field) }
            }
        }
        current = decl.GetSuperClassDecl()
    }
    return None
}

// C++ src/Sema/NativeFFI/ObjC/Utils/Common.cpp:132-140.
public func IsObjCInitMethod(fd: FuncDecl): Bool { return fd.TestAttr(Attribute.OBJ_C_INIT) }

// C++ src/Sema/NativeFFI/ObjC/Utils/Common.cpp:142-153.
public func IsNativeHandleGetter(decl: Decl): Bool {
    return decl.identifier.Val() == NATIVE_HANDLE_GETTER_IDENT
}

public func GetNativeHandleGetter(target: ClassLikeDecl): Option<FuncDecl> {
    var owner = target
    while (let Some(cd) <- (owner as ClassDecl)) {
        let parent = GetMirrorSuperClass(cd)
        if (parent.isNone()) { break }
        owner = parent.getOrThrow()
    }
    for (member in owner.GetMemberDeclPtrs()) {
        if (let Some(fd) <- (member as FuncDecl)) {
            if (IsNativeHandleGetter(fd)) { return Some(fd) }
        }
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

public func IsNSObject(decl: ClassDecl): Bool { return NameGenerator.GetObjCDeclName(decl) == "NSObject" }
public func IsNSString(decl: ClassDecl): Bool { return NameGenerator.GetObjCDeclName(decl) == "NSString" }
public func IsGeneratedNSStringCtor(fd: FuncDecl): Bool {
    if (fd.identifier.Val() != "init" || !fd.TestAttr(Attribute.CONSTRUCTOR) ||
        !fd.TestAttr(Attribute.COMPILER_ADD) || fd.funcBody.isNone() || fd.funcBody.getOrThrow().paramLists.isEmpty()) {
        return false
    }
    let params = fd.funcBody.getOrThrow().paramLists[0].params
    return params.size == 1 && params[0].typeNode.getOrThrow().symbol.getOrThrow().name == "String"
}
public func IsGeneratedNSObjectToString(fd: FuncDecl): Bool {
    if (fd.identifier.Val() != "toString" || !fd.TestAttr(Attribute.COMPILER_ADD) ||
        fd.funcBody.isNone() || fd.funcBody.getOrThrow().paramLists.isEmpty()) { return false }
    return fd.funcBody.getOrThrow().paramLists[0].params.isEmpty()
}
private func IsGeneratedStringConversion(fd: FuncDecl): Bool {
    let owner = GetOwnerClass(fd)
    if (owner.isNone()) { return false }
    return (IsNSString(owner.getOrThrow()) && IsGeneratedNSStringCtor(fd)) ||
        (IsNSObject(owner.getOrThrow()) && IsGeneratedNSObjectToString(fd))
}
