package cjcj::sema.NativeFFI

import cjcj::ast.*
import cjcj::modules.SemaImportManager
import cjcj::sema.{GenerateTypeMapping, TypeManager}

// Upstream fbf15ec8, src/Sema/NativeFFI/Utils.cpp:494-512.
public func CreateZeroValue(importManager: SemaImportManager, typeManager: TypeManager, ty: Ty): Expr {
    let decl = importManager.GetCoreDecl<FuncDecl>("zeroValue").getOrThrow()
    let call = CallExpr()
    let ref = CreateRefExpr(decl)
    ref.instTys.add(ty)
    ref.SetTy(typeManager.GetInstantiatedTy(decl.GetTy().getOrThrow(), GenerateTypeMapping(decl, ref.instTys)))
    call.baseFunc = Some(ref)
    call.SetTy(ty)
    call.callKind = CallKind.CALL_INTRINSIC_FUNCTION
    call.resolvedFunction = Some(decl)
    return call
}
