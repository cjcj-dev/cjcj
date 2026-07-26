package cjcj::sema.NativeFFI.ObjC

import cjcj::ast.*
import cjcj::utils.{CJC_ASSERT, NATIVE_HANDLE_GETTER_IDENT}

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

// C++ src/Sema/NativeFFI/ObjC/Utils/Common.cpp:82-91.
public func FindMirrorMember(mirrorMemberIdent: String, target: InheritableDecl): Option<Decl> {
    for (memberDecl in target.GetMemberDeclPtrs()) {
        if (memberDecl.identifier == mirrorMemberIdent) {
            return Some(memberDecl)
        }
    }
    return None
}

// C++ src/Sema/NativeFFI/ObjC/Utils/Common.cpp:142-153.
public func GetNativeHandleGetter(target: ClassLikeDecl): Option<FuncDecl> {
    let targetTy = target.GetTy().getOrThrow()
    CJC_ASSERT(TypeMapper.IsObjCMirror(targetTy) || TypeMapper.IsObjCImpl(targetTy) ||
        TypeMapper.IsSyntheticWrapper(target) || TypeMapper.IsObjCFwdClass(target))

    if (let Some(mirrorSuperClass) <- GetMirrorSuperClass(target)) {
        return GetNativeHandleGetter(mirrorSuperClass)
    }
    return FindMirrorMember(NATIVE_HANDLE_GETTER_IDENT, target) as FuncDecl
}
