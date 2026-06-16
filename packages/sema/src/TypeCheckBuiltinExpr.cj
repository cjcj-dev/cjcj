package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor

private func InvalidExprTy(expr: Expr): Ty {
    let invalidTy = TypeManager.GetInvalidTy()
    expr.SetTy(invalidTy)
    return invalidTy
}

private func FuncArgTy(arg: FuncArg): Ty {
    if (let Some(ty) <- arg.GetTy()) {
        return ty
    }
    if (let Some(expr) <- arg.expr) {
        if (let Some(ty) <- expr.GetTy()) {
            arg.SetTy(ty)
            return ty
        }
    }
    let invalidTy = TypeManager.GetInvalidTy()
    arg.SetTy(invalidTy)
    return invalidTy
}

private func GetArrayElementTy(typeManager: TypeManager, arrayTy: ArrayTy): Ty {
    if (arrayTy.dims == 1u64) {
        if (!arrayTy.typeArgs.isEmpty()) {
            return arrayTy.typeArgs[0]
        }
        return TypeManager.GetInvalidTy()
    }
    if (arrayTy.typeArgs.isEmpty()) {
        return TypeManager.GetInvalidTy()
    }
    return typeManager.GetArrayTy(arrayTy.typeArgs[0], arrayTy.dims - 1u64)
}

private func IsBuiltinTypeAlias(decl: Decl, kind: TypeKind): Bool {
    if (let Some(aliasDecl) <- (decl as TypeAliasDecl)) {
        if (let Some(typeNode) <- aliasDecl.typeNode) {
            if (let Some(origTy) <- typeNode.GetTy()) {
                if (kind == TypeKind.TYPE_ANY) {
                    return origTy.kind == TypeKind.TYPE_ARRAY || origTy.kind == TypeKind.TYPE_POINTER ||
                        origTy.kind == TypeKind.TYPE_CSTRING || origTy.kind == TypeKind.TYPE_VARRAY
                }
                return origTy.kind == kind
            }
        }
    }
    return false
}

public func IsCallOfBuiltInType(ce: CallExpr, kind: TypeKind): Bool {
    if (let None <- ce.baseFunc) {
        return false
    }
    let baseFunc = ce.baseFunc.getOrThrow()
    if (let None <- baseFunc.GetTarget()) {
        return false
    }
    let baseTarget = GetRealTarget(baseFunc.GetTarget()).getOrThrow()
    if (IsBuiltinTypeAlias(baseTarget, kind)) {
        return true
    }
    if (let Some(builtinDecl) <- (baseTarget as BuiltInDecl)) {
        if (kind == TypeKind.TYPE_POINTER) {
            return builtinDecl.IsType(BuiltInType.POINTER)
        }
        if (kind == TypeKind.TYPE_CSTRING) {
            return builtinDecl.IsType(BuiltInType.CSTRING)
        }
        if (kind == TypeKind.TYPE_ARRAY) {
            return builtinDecl.IsType(BuiltInType.ARRAY)
        }
        if (kind == TypeKind.TYPE_VARRAY) {
            return builtinDecl.IsType(BuiltInType.VARRAY)
        }
    }
    return false
}

public func ChkArrayArgs(arrayExpr: ArrayExpr): Bool {
    if (arrayExpr.args.isEmpty()) {
        return true
    }
    if (!arrayExpr.args[0].name.Empty()) {
        return false
    }
    if (arrayExpr.args.size != 2) {
        return true
    }
    if (let Some(_) <- arrayExpr.initFunc) {
        return arrayExpr.args[1].name.Empty()
    }
    return arrayExpr.args[1].name.Empty() || arrayExpr.args[1].name.Val() == "repeat"
}

public func SynArrayLit(typeManager: TypeManager, arrayLit: ArrayLit): Ty {
    if (arrayLit.children.isEmpty()) {
        return InvalidExprTy(arrayLit)
    }
    let elemTys = ArrayList<Ty>()
    for (child in arrayLit.children) {
        if (let Some(ty) <- child.GetTy()) {
            if (!Ty.IsTyCorrect(ty)) {
                return InvalidExprTy(arrayLit)
            }
            elemTys.add(typeManager.ReplaceIdealTy(ty))
        } else {
            return InvalidExprTy(arrayLit)
        }
    }
    let elemTy = JoinCaseTysForBuiltin(typeManager, elemTys)
    let resultTy = typeManager.GetArrayTy(elemTy, 1u64)
    arrayLit.SetTy(resultTy)
    return resultTy
}

public func ChkArrayLit(typeManager: TypeManager, target: Ty, arrayLit: ArrayLit): Bool {
    let targetTy = UnboxOptionType(target)
    if (!Ty.IsTyCorrect(targetTy) || (!targetTy.IsArray() && !targetTy.IsStructArray() && !targetTy.IsInterface() &&
        (let None <- (targetTy as VArrayTy)))) {
        arrayLit.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    if (arrayLit.children.isEmpty()) {
        arrayLit.SetTy(targetTy)
        return true
    }
    var elemTy: Ty = TypeManager.GetInvalidTy()
    var hasElementTy = false
    if (targetTy.typeArgs.size >= 1) {
        elemTy = targetTy.typeArgs[0]
        hasElementTy = true
    }
    if (!hasElementTy) {
        let synTy = SynArrayLit(typeManager, arrayLit)
        return typeManager.CheckTypeCompatibility(targetTy, synTy) != TypeCompatibility.INCOMPATIBLE
    }
    if (let Some(varrayTy) <- (targetTy as VArrayTy)) {
        if (varrayTy.size != arrayLit.children.size) {
            arrayLit.SetTy(TypeManager.GetInvalidTy())
            return false
        }
    }
    for (child in arrayLit.children) {
        if (let Some(childTy) <- child.GetTy()) {
            if (typeManager.CheckTypeCompatibility(elemTy, childTy) == TypeCompatibility.INCOMPATIBLE) {
                arrayLit.SetTy(TypeManager.GetInvalidTy())
                return false
            }
        } else {
            arrayLit.SetTy(TypeManager.GetInvalidTy())
            return false
        }
    }
    arrayLit.SetTy(targetTy)
    return true
}

public func ChkSizedArrayElement(typeManager: TypeManager, elemTargetTy: Ty, arrayExpr: ArrayExpr): Bool {
    if (arrayExpr.args.size != 2) {
        return false
    }
    let secondTy = FuncArgTy(arrayExpr.args[1])
    if (typeManager.CheckTypeCompatibility(elemTargetTy, secondTy) != TypeCompatibility.INCOMPATIBLE) {
        arrayExpr.initFunc = None
        return true
    }
    let sizeTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
    let expectedFuncTy = typeManager.GetFunctionTy([sizeTy], elemTargetTy)
    return typeManager.CheckTypeCompatibility(expectedFuncTy, secondTy) != TypeCompatibility.INCOMPATIBLE
}

public func ChkSizedArrayExpr(typeManager: TypeManager, target: Ty, arrayExpr: ArrayExpr): Bool {
    if (let None <- arrayExpr.typeNode) {
        return false
    }
    if (arrayExpr.args.size != 2) {
        return false
    }
    let arrayTy = arrayExpr.typeNode.getOrThrow().GetTy() ?? TypeManager.GetInvalidTy()
    if (let None <- (arrayTy as ArrayTy)) {
        return false
    }
    let rawArrayTy = (arrayTy as ArrayTy).getOrThrow()
    let sizeTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
    if (typeManager.CheckTypeCompatibility(sizeTy, FuncArgTy(arrayExpr.args[0])) == TypeCompatibility.INCOMPATIBLE) {
        return false
    }
    if (rawArrayTy.typeArgs.isEmpty() || rawArrayTy.typeArgs[0].IsInvalid()) {
        let secondTy = FuncArgTy(arrayExpr.args[1])
        if (let Some(funcTy) <- (secondTy as FuncTy)) {
            if (funcTy.paramTys.size == 1 && typeManager.IsSubtype(sizeTy, funcTy.paramTys[0])) {
                arrayExpr.SetTy(typeManager.GetArrayTy(funcTy.retTy, rawArrayTy.dims))
                return target.IsInvalid() ||
                    typeManager.CheckTypeCompatibility(target, arrayExpr.GetTy().getOrThrow()) !=
                    TypeCompatibility.INCOMPATIBLE
            }
        }
        arrayExpr.SetTy(typeManager.GetArrayTy(secondTy, rawArrayTy.dims))
        return target.IsInvalid() ||
            typeManager.CheckTypeCompatibility(target, arrayExpr.GetTy().getOrThrow()) != TypeCompatibility.INCOMPATIBLE
    }
    let elemTy = GetArrayElementTy(typeManager, rawArrayTy)
    if (!ChkSizedArrayElement(typeManager, elemTy, arrayExpr)) {
        return false
    }
    arrayExpr.SetTy(rawArrayTy)
    if (!target.IsInvalid()) {
        return typeManager.CheckTypeCompatibility(target, rawArrayTy) != TypeCompatibility.INCOMPATIBLE
    }
    return true
}

public func ChkSingleArgArrayExpr(typeManager: TypeManager, target: Ty, arrayExpr: ArrayExpr): Bool {
    if (let None <- arrayExpr.typeNode) {
        return false
    }
    if (arrayExpr.args.size != 1) {
        return false
    }
    let arrayTy = arrayExpr.typeNode.getOrThrow().GetTy() ?? TypeManager.GetInvalidTy()
    if (let Some(rawArrayTy) <- (arrayTy as ArrayTy)) {
        if (rawArrayTy.typeArgs.isEmpty() || rawArrayTy.typeArgs[0].IsInvalid()) {
            let elemTy = FuncArgTy(arrayExpr.args[0])
            arrayExpr.SetTy(typeManager.GetArrayTy(elemTy, rawArrayTy.dims))
        } else {
            arrayExpr.SetTy(rawArrayTy)
        }
        return target.IsInvalid() ||
            typeManager.CheckTypeCompatibility(target, arrayExpr.GetTy().getOrThrow()) != TypeCompatibility.INCOMPATIBLE
    }
    return false
}

public func ChkArrayExpr(typeManager: TypeManager, target: Ty, arrayExpr: ArrayExpr): Bool {
    if (let None <- arrayExpr.typeNode) {
        return false
    }
    let targetTy = UnboxOptionType(target)
    let arrayTy = arrayExpr.typeNode.getOrThrow().GetTy() ?? TypeManager.GetInvalidTy()
    if (let None <- (arrayTy as ArrayTy)) {
        arrayExpr.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    arrayExpr.SetTy(arrayTy)
    var ok = true
    if (arrayExpr.args.isEmpty()) {
        ok = targetTy.IsInvalid() || typeManager.CheckTypeCompatibility(targetTy, arrayTy) != TypeCompatibility.INCOMPATIBLE
    } else if (arrayExpr.args.size == 1) {
        ok = ChkSingleArgArrayExpr(typeManager, targetTy, arrayExpr)
    } else if (arrayExpr.args.size == 2) {
        ok = ChkSizedArrayExpr(typeManager, targetTy, arrayExpr)
    } else {
        ok = false
    }
    if (!ChkArrayArgs(arrayExpr)) {
        ok = false
    }
    if (!ok) {
        arrayExpr.SetTy(TypeManager.GetInvalidTy())
    }
    return ok
}

public func SynArrayExpr(typeManager: TypeManager, arrayExpr: ArrayExpr): Ty {
    if (ChkArrayExpr(typeManager, TypeManager.GetInvalidTy(), arrayExpr)) {
        return arrayExpr.GetTy() ?? TypeManager.GetInvalidTy()
    }
    return InvalidExprTy(arrayExpr)
}

public func ChkVArrayArg(typeManager: TypeManager, arrayExpr: ArrayExpr): Bool {
    if (arrayExpr.args.size != 1) {
        return false
    }
    if (let None <- arrayExpr.typeNode) {
        return false
    }
    if (let Some(varrayTy) <- ((arrayExpr.typeNode.getOrThrow().GetTy() ?? TypeManager.GetInvalidTy()) as VArrayTy)) {
        if (varrayTy.typeArgs.isEmpty()) {
            return false
        }
        let argTy = FuncArgTy(arrayExpr.args[0])
        if (arrayExpr.args[0].name.Empty()) {
            let sizeTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
            let expected = typeManager.GetFunctionTy([sizeTy], varrayTy.typeArgs[0])
            return typeManager.CheckTypeCompatibility(expected, argTy) != TypeCompatibility.INCOMPATIBLE
        }
        if (arrayExpr.args[0].name.Val() != "repeat") {
            return false
        }
        return typeManager.CheckTypeCompatibility(varrayTy.typeArgs[0], argTy) != TypeCompatibility.INCOMPATIBLE
    }
    return false
}

public func ChkVArrayExpr(typeManager: TypeManager, target: Ty, arrayExpr: ArrayExpr): Bool {
    if (let None <- arrayExpr.typeNode) {
        return false
    }
    let targetTy = UnboxOptionType(target)
    let arrayTy = arrayExpr.typeNode.getOrThrow().GetTy() ?? TypeManager.GetInvalidTy()
    if (let None <- (arrayTy as VArrayTy)) {
        return false
    }
    arrayExpr.SetTy(arrayTy)
    if (!ChkVArrayArg(typeManager, arrayExpr)) {
        return false
    }
    if (!targetTy.IsInvalid() && typeManager.CheckTypeCompatibility(targetTy, arrayTy) == TypeCompatibility.INCOMPATIBLE) {
        arrayExpr.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    return true
}

public func SynVArrayExpr(typeManager: TypeManager, arrayExpr: ArrayExpr): Ty {
    if (ChkVArrayExpr(typeManager, TypeManager.GetInvalidTy(), arrayExpr)) {
        return arrayExpr.GetTy() ?? TypeManager.GetInvalidTy()
    }
    return InvalidExprTy(arrayExpr)
}

public func ChkPointerExpr(typeManager: TypeManager, target: Ty, pointerExpr: PointerExpr): Bool {
    if (let None <- pointerExpr.typeNode) {
        return false
    }
    let pointerTy = pointerExpr.typeNode.getOrThrow().GetTy() ?? TypeManager.GetInvalidTy()
    if (!pointerTy.IsPointer()) {
        pointerExpr.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    pointerExpr.SetTy(pointerTy)
    if (let Some(arg) <- pointerExpr.arg) {
        let argTy = FuncArgTy(arg)
        if (!argTy.IsPointer() && !argTy.IsCFunc()) {
            pointerExpr.SetTy(TypeManager.GetInvalidTy())
            return false
        }
        if (!arg.name.Empty()) {
            pointerExpr.SetTy(TypeManager.GetInvalidTy())
            return false
        }
    }
    let targetTy = UnboxOptionType(target)
    if (!targetTy.IsInvalid() && typeManager.CheckTypeCompatibility(targetTy, pointerTy) == TypeCompatibility.INCOMPATIBLE) {
        pointerExpr.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    return true
}

public func SynPointerExpr(typeManager: TypeManager, pointerExpr: PointerExpr): Ty {
    if (ChkPointerExpr(typeManager, TypeManager.GetInvalidTy(), pointerExpr)) {
        return pointerExpr.GetTy() ?? TypeManager.GetInvalidTy()
    }
    return InvalidExprTy(pointerExpr)
}

public func SynCFuncCall(typeManager: TypeManager, ce: CallExpr): Bool {
    if (let None <- ce.baseFunc) {
        ce.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    let baseTy = ce.baseFunc.getOrThrow().GetTy() ?? TypeManager.GetInvalidTy()
    ce.SetTy(baseTy)
    if (!baseTy.IsCFunc()) {
        ce.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    if (ce.args.size != 1) {
        ce.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    let argTy = FuncArgTy(ce.args[0])
    if (!ce.args[0].name.Empty() || !argTy.IsPointer()) {
        ce.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    let _ = typeManager
    return true
}

public func ChkCStringCall(typeManager: TypeManager, target: Ty, ce: CallExpr): Bool {
    if (!IsCallOfBuiltInType(ce, TypeKind.TYPE_CSTRING)) {
        return false
    }
    let cptrTy = typeManager.GetPointerTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UINT8))
    if (ce.args.size != 1) {
        ce.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    if (typeManager.CheckTypeCompatibility(cptrTy, FuncArgTy(ce.args[0])) == TypeCompatibility.INCOMPATIBLE) {
        ce.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    let targetTy = UnboxOptionType(target)
    if (Ty.IsTyCorrect(targetTy) && !targetTy.IsCString() && !targetTy.IsCType() && !targetTy.IsInvalid()) {
        ce.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    ce.SetTy(TypeManager.GetCStringTy())
    return true
}

public func ChkArrayCall(typeManager: TypeManager, target: Ty, ce: CallExpr): Bool {
    if (!IsCallOfBuiltInType(ce, TypeKind.TYPE_ARRAY)) {
        return false
    }
    let arrayExpr = ArrayExpr()
    arrayExpr.typeNode = TypeNodeFromCallBase(ce)
    for (arg in ce.args) {
        arrayExpr.args.add(arg)
    }
    let ok = if (target.IsInvalid()) {
        Ty.IsTyCorrect(SynArrayExpr(typeManager, arrayExpr))
    } else {
        ChkArrayExpr(typeManager, target, arrayExpr)
    }
    if (ok) {
        ce.desugarExpr = arrayExpr
        ce.SetTy(arrayExpr.GetTy() ?? TypeManager.GetInvalidTy())
        return true
    }
    ce.SetTy(TypeManager.GetInvalidTy())
    return false
}

public func ChkVArrayCall(typeManager: TypeManager, target: Ty, ce: CallExpr): Bool {
    if (!IsCallOfBuiltInType(ce, TypeKind.TYPE_VARRAY)) {
        return false
    }
    let arrayExpr = ArrayExpr()
    arrayExpr.typeNode = TypeNodeFromCallBase(ce)
    for (arg in ce.args) {
        arrayExpr.args.add(arg)
    }
    let ok = if (target.IsInvalid()) {
        Ty.IsTyCorrect(SynVArrayExpr(typeManager, arrayExpr))
    } else {
        ChkVArrayExpr(typeManager, target, arrayExpr)
    }
    if (ok) {
        ce.desugarExpr = arrayExpr
        ce.SetTy(arrayExpr.GetTy() ?? TypeManager.GetInvalidTy())
        return true
    }
    ce.SetTy(TypeManager.GetInvalidTy())
    return false
}

public func ChkPointerCall(typeManager: TypeManager, target: Ty, ce: CallExpr): Bool {
    if (!IsCallOfBuiltInType(ce, TypeKind.TYPE_POINTER)) {
        return false
    }
    let pointerExpr = PointerExpr()
    pointerExpr.typeNode = TypeNodeFromCallBase(ce)
    if (!ce.args.isEmpty()) {
        pointerExpr.arg = ce.args[0]
    }
    let ok = if (target.IsInvalid()) {
        Ty.IsTyCorrect(SynPointerExpr(typeManager, pointerExpr))
    } else {
        ChkPointerExpr(typeManager, target, pointerExpr)
    }
    if (ok) {
        ce.desugarExpr = pointerExpr
        ce.SetTy(pointerExpr.GetTy() ?? TypeManager.GetInvalidTy())
        return true
    }
    ce.SetTy(TypeManager.GetInvalidTy())
    return false
}

public func ChkCFuncCall(typeManager: TypeManager, target: Ty, ce: CallExpr): Bool {
    if (let None <- ce.baseFunc) {
        return false
    }
    let baseTarget = ce.baseFunc.getOrThrow().GetTarget()
    if (let None <- baseTarget) {
        return false
    }
    let realTarget = GetRealTarget(baseTarget).getOrThrow()
    if (let Some(builtinDecl) <- (realTarget as BuiltInDecl)) {
        if (!builtinDecl.IsType(BuiltInType.CFUNC)) {
            return false
        }
    } else {
        return false
    }
    if (!target.IsInvalid() && !target.IsCFunc()) {
        ce.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    ce.baseFunc.getOrThrow().SetTarget(realTarget)
    return SynCFuncCall(typeManager, ce)
}

public func ChkBuiltinCall(typeManager: TypeManager, target: Ty, ce: CallExpr): Bool {
    if (ChkPointerCall(typeManager, target, ce)) {
        return true
    }
    if (ChkCStringCall(typeManager, target, ce)) {
        return true
    }
    if (ChkArrayCall(typeManager, target, ce)) {
        return true
    }
    if (ChkVArrayCall(typeManager, target, ce)) {
        return true
    }
    if (ChkCFuncCall(typeManager, target, ce)) {
        return true
    }
    return false
}

private func TypeNodeFromCallBase(ce: CallExpr): Option<Type> {
    if (let None <- ce.baseFunc) {
        return None
    }
    let typeNode = RefType()
    let base = ce.baseFunc.getOrThrow()
    if (let Some(ty) <- base.GetTy()) {
        typeNode.SetTy(ty)
    } else if (let Some(target) <- base.GetTarget()) {
        if (let Some(targetTy) <- target.GetTy()) {
            typeNode.SetTy(targetTy)
        }
    }
    typeNode.begin = base.begin
    typeNode.end = base.end
    return typeNode
}

private func JoinCaseTysForBuiltin(typeManager: TypeManager, tys: ArrayList<Ty>): Ty {
    if (tys.isEmpty()) {
        return TypeManager.GetInvalidTy()
    }
    var out = tys[0]
    var idx: Int64 = 1
    while (idx < tys.size) {
        out = Join(typeManager, out, tys[idx])
        idx++
    }
    return out
}

public func ChkBuiltinCallWithDiag(diag: BasicDiagnosticEngine, typeManager: TypeManager, target: Ty,
    ce: CallExpr): Bool {
    let ok = ChkBuiltinCall(typeManager, target, ce)
    if (!ok && ce.ShouldDiagnose()) {
        SemaDiag(diag, BasicDiagKindRefactor.sema_mismatched_types, ce)
    }
    return ok
}

public func SelfhostPortStatus_TypeCheckBuiltinExpr(): Bool {
    return true
}
