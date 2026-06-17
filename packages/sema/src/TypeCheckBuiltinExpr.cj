package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.DiagKind as BasicDiagKind
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.DiagArgument as BasicDiagArgument
import cangjie_compiler::basic.Position as BasicPosition

private func ToBasicPosition(pos: Position): BasicPosition {
    return BasicPosition(pos.fileID, pos.line, pos.column)
}

private func DiagOld(diag: BasicDiagnosticEngine, node: Node, kind: BasicDiagKind): Unit {
    let _ = diag.Diagnose(ToBasicPosition(node.begin), ToBasicPosition(node.end), kind)
}

private func StringDiagArgs(values: Array<String>): Array<BasicDiagArgument> {
    let args = ArrayList<BasicDiagArgument>()
    for (value in values) {
        args.add(BasicDiagArgument(value))
    }
    return args.toArray()
}

private func DiagOldStrings(diag: BasicDiagnosticEngine, node: Node, kind: BasicDiagKind,
    values: Array<String>): Unit {
    let _ = diag.Diagnose(ToBasicPosition(node.begin), ToBasicPosition(node.end), kind, args: StringDiagArgs(values))
}

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

private func IsSizedArrayFunctionInitializer(typeManager: TypeManager, arrayExpr: ArrayExpr): Bool {
    if (arrayExpr.args.size != 2) {
        return false
    }
    if (let Some(_) <- arrayExpr.initFunc) {
        return true
    }
    if (!arrayExpr.args[1].name.Empty()) {
        return false
    }
    if (let None <- arrayExpr.typeNode) {
        return false
    }
    let arrayTy = arrayExpr.typeNode.getOrThrow().GetTy() ?? TypeManager.GetInvalidTy()
    if (let None <- (arrayTy as ArrayTy)) {
        return false
    }
    let rawArrayTy = (arrayTy as ArrayTy).getOrThrow()
    let secondTy = FuncArgTy(arrayExpr.args[1])
    let sizeTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
    if (rawArrayTy.typeArgs.isEmpty() || rawArrayTy.typeArgs[0].IsInvalid()) {
        if (let Some(funcTy) <- (secondTy as FuncTy)) {
            return funcTy.paramTys.size == 1 && typeManager.IsSubtype(funcTy.paramTys[0], sizeTy)
        }
        return false
    }
    let elemTy = GetArrayElementTy(typeManager, rawArrayTy)
    if (typeManager.CheckTypeCompatibility(elemTy, secondTy) != TypeCompatibility.INCOMPATIBLE) {
        return false
    }
    let expectedFuncTy = typeManager.GetFunctionTy([sizeTy], elemTy)
    return typeManager.CheckTypeCompatibility(expectedFuncTy, secondTy) != TypeCompatibility.INCOMPATIBLE
}

public func ChkArrayArgs(typeManager: TypeManager, arrayExpr: ArrayExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (arrayExpr.args.isEmpty()) {
        return true
    }
    if (!arrayExpr.args[0].name.Empty()) {
        if (let Some(diagValue) <- diag) {
            DiagOld(diagValue, arrayExpr.args[0], BasicDiagKind.sema_array_first_arg_cannot_be_named)
        }
        return false
    }
    if (arrayExpr.args.size != 2) {
        return true
    }
    if (IsSizedArrayFunctionInitializer(typeManager, arrayExpr)) {
        if (!arrayExpr.args[1].name.Empty()) {
            if (let Some(diagValue) <- diag) {
                DiagOld(diagValue, arrayExpr.args[1], BasicDiagKind.sema_array_second_arg_cannot_be_named)
            }
            return false
        }
        return true
    }
    if (arrayExpr.args[1].name.Empty() || arrayExpr.args[1].name.Val() != "repeat") {
        if (let Some(diagValue) <- diag) {
            DiagOld(diagValue, arrayExpr.args[1], BasicDiagKind.sema_array_second_wrong_named_arg)
        }
        return false
    }
    return true
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
            if (funcTy.paramTys.size == 1 && typeManager.IsSubtype(funcTy.paramTys[0], sizeTy)) {
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

public func ChkArrayExpr(typeManager: TypeManager, target: Ty, arrayExpr: ArrayExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
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
        if (let Some(diagValue) <- diag) {
            DiagOld(diagValue, arrayExpr, BasicDiagKind.sema_array_too_much_argument)
        }
        ok = false
    }
    if (!ChkArrayArgs(typeManager, arrayExpr, diag: diag)) {
        ok = false
    }
    if (!ok) {
        arrayExpr.SetTy(TypeManager.GetInvalidTy())
    }
    return ok
}

public func SynArrayExpr(typeManager: TypeManager, arrayExpr: ArrayExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Ty {
    if (ChkArrayExpr(typeManager, TypeManager.GetInvalidTy(), arrayExpr, diag: diag)) {
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

private func CanInferPointerTyFromTarget(pointerTy: Ty, targetTy: Ty): Bool {
    if (!targetTy.IsPointer() || targetTy.typeArgs.isEmpty() || !Ty.IsTyCorrect(targetTy.typeArgs[0])) {
        return false
    }
    if (!pointerTy.IsPointer() || pointerTy.typeArgs.isEmpty()) {
        return false
    }
    return !Ty.IsTyCorrect(pointerTy.typeArgs[0]) || pointerTy.HasGeneric()
}

public func ChkPointerExpr(typeManager: TypeManager, target: Ty, pointerExpr: PointerExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (let None <- pointerExpr.typeNode) {
        return false
    }
    let targetTy = UnboxOptionType(target)
    let pointerTypeNode = pointerExpr.typeNode.getOrThrow()
    var pointerTy = pointerTypeNode.GetTy() ?? TypeManager.GetInvalidTy()
    if (CanInferPointerTyFromTarget(pointerTy, targetTy)) {
        pointerTy = targetTy
        pointerTypeNode.SetTy(pointerTy)
    }
    if (!pointerTy.IsPointer()) {
        if (!Ty.IsTyCorrect(pointerTy)) {
            if (let Some(diagValue) <- diag) {
                DiagOld(diagValue, pointerExpr, BasicDiagKind.sema_pointer_unknow_generic_type)
            }
        }
        pointerExpr.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    pointerExpr.SetTy(pointerTy)
    if (let Some(arg) <- pointerExpr.arg) {
        let argTy = FuncArgTy(arg)
        if (!argTy.IsPointer() && !argTy.IsCFunc()) {
            if (let Some(diagValue) <- diag) {
                DiagOld(diagValue, pointerExpr, BasicDiagKind.sema_pointer_single_element_type_error)
            }
            pointerExpr.SetTy(TypeManager.GetInvalidTy())
            return false
        }
        if (!arg.name.Empty()) {
            if (let Some(diagValue) <- diag) {
                DiagOldStrings(diagValue, arg, BasicDiagKind.sema_unknown_named_argument, [arg.name.Val()])
            }
            pointerExpr.SetTy(TypeManager.GetInvalidTy())
            return false
        }
    }
    if (!targetTy.IsInvalid() && typeManager.CheckTypeCompatibility(targetTy, pointerTy) == TypeCompatibility.INCOMPATIBLE) {
        if (let Some(diagValue) <- diag) {
            SemaDiag(diagValue, BasicDiagKindRefactor.sema_mismatched_types, pointerExpr)
        }
        pointerExpr.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    return true
}

public func SynPointerExpr(typeManager: TypeManager, pointerExpr: PointerExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Ty {
    if (ChkPointerExpr(typeManager, TypeManager.GetInvalidTy(), pointerExpr, diag: diag)) {
        return pointerExpr.GetTy() ?? TypeManager.GetInvalidTy()
    }
    return InvalidExprTy(pointerExpr)
}

public func SynCFuncCall(typeManager: TypeManager, ce: CallExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (let None <- ce.baseFunc) {
        ce.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    let base = ce.baseFunc.getOrThrow()
    if (let None <- (base as RefExpr)) {
        ce.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    let baseTy = base.GetTy() ?? TypeManager.GetInvalidTy()
    ce.SetTy(baseTy)
    if (!baseTy.IsCFunc()) {
        ce.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    if (ce.args.size != 1) {
        if (let Some(diagValue) <- diag) {
            DiagOld(diagValue, base, BasicDiagKind.sema_cfunc_too_many_arguments)
        }
        ce.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    let argTy = FuncArgTy(ce.args[0])
    var valid = true
    if (!ce.args[0].name.Empty()) {
        if (let Some(diagValue) <- diag) {
            DiagOldStrings(diagValue, ce.args[0], BasicDiagKind.sema_unknown_named_argument,
                [ce.args[0].name.Val()])
        }
        valid = false
    }
    if (argTy.IsPointer()) {
        ce.SetTy(baseTy)
        let _ = typeManager
        return valid
    }
    if (let Some(diagValue) <- diag) {
        DiagOld(diagValue, ce.args[0], BasicDiagKind.sema_cfunc_ctor_must_be_cpointer)
    }
    ce.SetTy(TypeManager.GetInvalidTy())
    let _ = typeManager
    return false
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

public func ChkArrayCall(typeManager: TypeManager, target: Ty, ce: CallExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (!IsCallOfBuiltInType(ce, TypeKind.TYPE_ARRAY)) {
        return false
    }
    let arrayExpr = ArrayExpr()
    arrayExpr.typeNode = TypeNodeFromCallBase(ce)
    for (arg in ce.args) {
        arrayExpr.args.add(arg)
    }
    let ok = if (target.IsInvalid()) {
        Ty.IsTyCorrect(SynArrayExpr(typeManager, arrayExpr, diag: diag))
    } else {
        ChkArrayExpr(typeManager, target, arrayExpr, diag: diag)
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

public func ChkPointerCall(typeManager: TypeManager, target: Ty, ce: CallExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (!IsCallOfBuiltInType(ce, TypeKind.TYPE_POINTER)) {
        return false
    }
    let pointerExpr = PointerExpr()
    pointerExpr.typeNode = TypeNodeFromCallBase(ce)
    if (!ce.args.isEmpty()) {
        pointerExpr.arg = ce.args[0]
    }
    if (ce.args.size > 1) {
        if (let Some(diagValue) <- diag) {
            DiagOld(diagValue, ce, BasicDiagKind.sema_pointer_too_much_argument)
        }
    }
    let ok = if (target.IsInvalid()) {
        Ty.IsTyCorrect(SynPointerExpr(typeManager, pointerExpr, diag: diag))
    } else {
        ChkPointerExpr(typeManager, target, pointerExpr, diag: diag)
    }
    if (ok) {
        ce.desugarExpr = pointerExpr
        ce.SetTy(pointerExpr.GetTy() ?? TypeManager.GetInvalidTy())
        return true
    }
    ce.SetTy(TypeManager.GetInvalidTy())
    return false
}

public func ChkCFuncCall(typeManager: TypeManager, target: Ty, ce: CallExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
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
    let ok = SynCFuncCall(typeManager, ce, diag: diag)
    if (!ok) {
        ce.SetTy(TypeManager.GetInvalidTy())
    }
    return ok
}

public func ChkBuiltinCall(typeManager: TypeManager, target: Ty, ce: CallExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (ChkPointerCall(typeManager, target, ce, diag: diag)) {
        return true
    }
    if (ChkCStringCall(typeManager, target, ce)) {
        return true
    }
    if (ChkArrayCall(typeManager, target, ce, diag: diag)) {
        return true
    }
    if (ChkVArrayCall(typeManager, target, ce)) {
        return true
    }
    if (ChkCFuncCall(typeManager, target, ce, diag: diag)) {
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
    let ok = ChkBuiltinCall(typeManager, target, ce, diag: Some(diag))
    if (!ok && ce.ShouldDiagnose()) {
        SemaDiag(diag, BasicDiagKindRefactor.sema_mismatched_types, ce)
    }
    return ok
}

public func SelfhostPortStatus_TypeCheckBuiltinExpr(): Bool {
    return true
}
