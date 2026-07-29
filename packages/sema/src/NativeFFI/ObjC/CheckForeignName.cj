package cjcj::sema.NativeFFI.ObjC

import cjcj::ast.*
import cjcj::basic.DiagKindRefactor
import cjcj::sema.NativeFFI.GetForeignNameAnnotation

// C++ src/Sema/NativeFFI/ObjC/TypeCheck/CheckForeignName.cpp:22-37.
private func MustHaveForeignName(member: Decl): Bool {
    if (!member.IsFunc()) {
        return false
    }

    let fd = (member as FuncDecl).getOrThrow()
    if (fd.funcBody.isNone()) {
        return false
    }
    let funcBody = fd.funcBody.getOrThrow()
    if (funcBody.paramLists.isEmpty() || funcBody.paramLists[0].params.isEmpty()) {
        return false
    }

    return funcBody.paramLists[0].params.size > 1
}

// C++ src/Sema/NativeFFI/ObjC/TypeCheck/CheckForeignName.cpp:39-42.
private func HasForeignName(member: Decl): Bool {
    return GetForeignNameAnnotation(member).isSome()
}

public class CheckForeignName <: Handler<TypeCheckContext> {
    // C++ src/Sema/NativeFFI/ObjC/TypeCheck/CheckForeignName.cpp:46-72.
    public func HandleImpl(ctx: TypeCheckContext): Unit {
        let targetKind = if (TypeMapper.IsObjCMirror(ctx.target)) { "@ObjCMirror" } else { "@ObjCImpl" }
        for (memberDecl in ctx.target.GetMemberDeclPtrs()) {
            if (memberDecl.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }

            if (TypeMapper.IsObjCImpl(ctx.target.GetTy().getOrThrow()) &&
                !memberDecl.TestAttr(Attribute.PUBLIC)) {
                continue
            }

            if (!MustHaveForeignName(memberDecl) || HasForeignName(memberDecl)) {
                continue
            }

            memberDecl.EnableAttr(Attribute.IS_BROKEN)
            ctx.target.EnableAttr(Attribute.HAS_BROKEN)
            if (memberDecl.TestAttr(Attribute.CONSTRUCTOR)) {
                DiagnoseRefactor(ctx.diag, DiagKindRefactor.sema_objc_ctor_must_have_foreign_name,
                    memberDecl, targetKind).Emit()
            } else {
                DiagnoseRefactor(ctx.diag, DiagKindRefactor.sema_objc_method_must_have_foreign_name,
                    memberDecl, targetKind, memberDecl.identifier.Val()).Emit()
            }
        }
    }
}
