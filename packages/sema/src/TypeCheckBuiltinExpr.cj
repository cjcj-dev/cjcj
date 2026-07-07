package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.DiagKind as BasicDiagKind
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.DiagArgument as BasicDiagArgument
import cangjie_compiler::basic.Position as BasicPosition
import cangjie_compiler::utils.CSTRING_NAME

private func ToBasicPosition(pos: Position): BasicPosition {
    return BasicPosition(pos.fileID, pos.line, pos.column)
}

private func DiagOld(diag: BasicDiagnosticEngine, node: Node, kind: BasicDiagKind): Unit {
    // GAP_TODO: emission blocked on sema TypeCheckCall call-path parity (spurious fires during self-compile; see C++ dtor auto-emit DiagnosticEngine.cpp:314)
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
    // GAP_TODO: emission blocked on sema TypeCheckCall call-path parity (spurious fires during self-compile; see C++ dtor auto-emit DiagnosticEngine.cpp:314)
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

private func GetArrayTypeByInterface(typeManager: TypeManager, arrayStruct: Option<StructDecl>,
    interfaceTy: Ty): Ty {
    let invalid = TypeManager.GetInvalidTy()
    if (let None <- arrayStruct) {
        return invalid
    }
    let arrTys = Promotion(typeManager).Downgrade(arrayStruct.getOrThrow().GetTy().getOrThrow(), interfaceTy)
    if (arrTys.values.isEmpty()) {
        return invalid
    }
    return arrTys.values[0]
}

private func IgnoreEmptyIntersection(baseArgs: ArrayList<Type>): Unit {
    var idx: Int64 = 0
    while (idx < baseArgs.size) {
        let isEmpty = if (let Some(argTy) <- baseArgs[idx].GetTy()) {
            if (let Some(intersectionTy) <- (argTy as IntersectionTy)) {
                intersectionTy.tys.isEmpty()
            } else {
                false
            }
        } else {
            false
        }
        if (isEmpty) {
            baseArgs.remove(at: idx)
        } else {
            idx++
        }
    }
}

private func DesugarPointerCall(typeManager: TypeManager, ctx: Option<ASTContext>, ce: CallExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Unit {
    let pointerExpr = PointerExpr()
    let typeNode = Type()
    pointerExpr.typeNode = typeNode
    if (let Some(context) <- ctx) {
        context.RemoveTypeCheckCache(pointerExpr)
        context.RemoveTypeCheckCache(typeNode)
    }
    let baseFunc = ce.baseFunc.getOrThrow()
    let baseFuncTy = if (let Some(baseTy) <- baseFunc.GetTy()) {
        typeManager.SubstituteTypeAliasInTy(baseTy)
    } else {
        TypeManager.GetInvalidTy()
    }
    let typeArgs = baseFuncTy.typeArgs
    let baseArgs = ArrayList<Type>()
    for (baseArg in baseFunc.GetTypeArgs()) {
        baseArgs.add(baseArg)
    }
    IgnoreEmptyIntersection(baseArgs)
    let usefulTypeArg = !typeArgs.isEmpty() && (!typeArgs[0].IsGeneric() || !baseArgs.isEmpty())
    let argTy = if (usefulTypeArg) {
        typeArgs[0]
    } else if (!baseArgs.isEmpty()) {
        baseArgs[0].GetTy() ?? TypeManager.GetInvalidTy()
    } else {
        TypeManager.GetInvalidTy()
    }
    typeNode.SetTy(typeManager.GetPointerTy(argTy))

    if (!ce.args.isEmpty()) {
        pointerExpr.arg = ce.args[0]
    }
    if (ce.args.size > 1) {
        if (let Some(diagValue) <- diag) {
            DiagOld(diagValue, ce, BasicDiagKind.sema_pointer_too_much_argument)
        }
    }
    ce.args.clear()
    pointerExpr.scopeName = ce.scopeName
    pointerExpr.sourceExpr = ce
    pointerExpr.begin = ce.begin
    pointerExpr.end = ce.end
    ce.desugarExpr = pointerExpr
    AddCurFile(ce, file: ce.curFile)
}

private func DesugarArrayCall(typeManager: TypeManager, ctx: Option<ASTContext>, ce: CallExpr): Unit {
    let arrayExpr = ArrayExpr()
    let typeNode = Type()
    arrayExpr.typeNode = typeNode
    if (let Some(context) <- ctx) {
        context.RemoveTypeCheckCache(arrayExpr)
        context.RemoveTypeCheckCache(typeNode)
    }
    let baseFunc = ce.baseFunc.getOrThrow()
    let baseFuncTy = if (let Some(baseTy) <- baseFunc.GetTy()) {
        typeManager.SubstituteTypeAliasInTy(baseTy)
    } else {
        TypeManager.GetInvalidTy()
    }
    let typeArgs = typeManager.GetTypeArgs(baseFuncTy)
    let baseArgs = ArrayList<Type>()
    for (baseArg in baseFunc.GetTypeArgs()) {
        baseArgs.add(baseArg)
    }
    IgnoreEmptyIntersection(baseArgs)
    if (let Some(varrTy) <- (baseFuncTy as VArrayTy)) {
        var argTy: Ty = TypeManager.GetInvalidTy()
        if (!typeArgs.isEmpty()) {
            argTy = typeArgs[0]
        }
        if (typeArgs[0].IsGeneric() && !baseArgs.isEmpty()) {
            argTy = baseArgs[0].GetTy() ?? TypeManager.GetInvalidTy()
        }
        typeNode.SetTy(typeManager.GetVArrayTy(argTy, varrTy.size))
        arrayExpr.isValueArray = true
    } else {
        let usefulTypeArg = !typeArgs.isEmpty() && (!typeArgs[0].IsGeneric() || !baseArgs.isEmpty())
        if (usefulTypeArg) {
            typeNode.SetTy(typeManager.GetArrayTy(typeArgs[0], 1u64))
        } else {
            let argTy = if (!baseArgs.isEmpty()) {
                baseArgs[0].GetTy() ?? TypeManager.GetInvalidTy()
            } else {
                TypeManager.GetInvalidTy()
            }
            typeNode.SetTy(typeManager.GetArrayTy(argTy, 1u64))
        }
    }
    for (arg in ce.args) {
        arrayExpr.args.add(arg)
    }
    ce.args.clear()
    arrayExpr.scopeName = ce.scopeName
    arrayExpr.sourceExpr = ce
    arrayExpr.begin = ce.begin
    arrayExpr.end = ce.end
    ce.desugarExpr = arrayExpr
    AddCurFile(ce, file: ce.curFile)
}

private func IsCollectionInterfaceTy(ty: Ty): Bool {
    if (let Some(interfaceTy) <- (ty as InterfaceTy)) {
        if (interfaceTy.typeArgs.size != 1) {
            return false
        }
        if (interfaceTy.name == "Collection") {
            return true
        }
        if (let Some(decl) <- interfaceTy.declPtr) {
            return decl.identifier.Val() == "Collection" || decl.identifier.GetRawText() == "Collection"
        }
    }
    return false
}

private func CollectionElementTy(typeManager: TypeManager, ty: Ty): Option<Ty> {
    if (IsCollectionInterfaceTy(ty)) {
        return Some(ty.typeArgs[0])
    }
    for (superTy in typeManager.GetAllSuperTys(ty).values) {
        if (IsCollectionInterfaceTy(superTy)) {
            return Some(superTy.typeArgs[0])
        }
    }
    return None
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

public func ChkArrayArgs(arrayExpr: ArrayExpr,
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
    if (let Some(_) <- arrayExpr.initFunc) {
        if (!arrayExpr.args[1].name.Empty()) {
            if (let Some(diagValue) <- diag) {
                DiagOld(diagValue, arrayExpr.args[1], BasicDiagKind.sema_array_second_arg_cannot_be_named)
            }
            return false
        }
        return true
    }
    if (arrayExpr.args[1].name.Val() != "repeat") {
        if (let Some(diagValue) <- diag) {
            DiagOld(diagValue, arrayExpr.args[1], BasicDiagKind.sema_array_second_wrong_named_arg)
        }
        return false
    }
    return true
}

public func AddArrayLitConstructor(arrayLit: ArrayLit): Unit {
    let decl = Ty.GetDeclPtrOfTy(arrayLit.GetTy())
    if (let None <- decl) {
        return
    }
    for (member in decl.getOrThrow().GetMemberDeclPtrs()) {
        if (let Some(funcDecl) <- (member as FuncDecl)) {
            if (!IsInstanceConstructor(funcDecl)) {
                continue
            }
            if (let None <- funcDecl.funcBody) {
                continue
            }
            let funcBody = funcDecl.funcBody.getOrThrow()
            if (funcBody.paramLists.isEmpty() || funcBody.paramLists[0].params.size != 3) {
                continue
            }
            let firstParamTy = funcBody.paramLists[0].params[0].GetTy() ?? TypeManager.GetInvalidTy()
            if (Ty.IsTyCorrect(firstParamTy) && firstParamTy.IsArray()) {
                arrayLit.initFunc = Some(funcDecl)
                return
            }
        }
    }
}

public func SynArrayLit(typeManager: TypeManager, arrayLit: ArrayLit): Ty {
    return SynArrayLit(typeManager, arrayLit, None)
}

public func SynArrayLit(typeManager: TypeManager, arrayLit: ArrayLit, arrayStruct: Option<StructDecl>): Ty {
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
    let elemTy = JoinCaseTysForBuiltin(typeManager, elemTys, arrayLit.curFile)
    if (let None <- arrayStruct) {
        return InvalidExprTy(arrayLit)
    }
    let resultTy = typeManager.GetStructTy(arrayStruct.getOrThrow(), [elemTy])
    arrayLit.SetTy(resultTy)
    AddArrayLitConstructor(arrayLit)
    return resultTy
}

public func ChkArrayLit(typeManager: TypeManager, target: Ty, arrayLit: ArrayLit,
    arrayStruct!: Option<StructDecl> = None): Bool {
    var targetTy = UnboxOptionType(target)
    arrayLit.SetTy(TypeManager.GetInvalidTy())
    if (targetTy.IsInterface()) {
        targetTy = GetArrayTypeByInterface(typeManager, arrayStruct, targetTy)
        if (targetTy.IsInvalid()) {
            if (arrayLit.children.isEmpty()) {
                return false
            }
            let synTy = SynArrayLit(typeManager, arrayLit, arrayStruct)
            return typeManager.IsSubtype(synTy, target)
        }
    } else if (!Ty.IsTyCorrect(targetTy) || (!targetTy.IsStructArray() && (let None <- (targetTy as VArrayTy)))) {
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
    return ChkSingleArgArrayExpr(typeManager, target, arrayExpr, diag: None)
}

public func ChkSingleArgArrayExpr(typeManager: TypeManager, target: Ty, arrayExpr: ArrayExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (let None <- arrayExpr.typeNode) {
        return false
    }
    if (arrayExpr.args.size != 1) {
        return false
    }
    let arrayTy = arrayExpr.typeNode.getOrThrow().GetTy() ?? TypeManager.GetInvalidTy()
    if (let Some(rawArrayTy) <- (arrayTy as ArrayTy)) {
        let argElemTyOpt = CollectionElementTy(typeManager, FuncArgTy(arrayExpr.args[0]))
        if (let None <- argElemTyOpt) {
            if (let Some(diagValue) <- diag) {
                DiagOld(diagValue, arrayExpr.args[0], BasicDiagKind.sema_array_single_element_type_error)
            }
            arrayExpr.SetTy(TypeManager.GetInvalidTy())
            return false
        }
        let argElemTy = argElemTyOpt.getOrThrow()
        if (rawArrayTy.typeArgs.isEmpty() || rawArrayTy.typeArgs[0].IsInvalid()) {
            arrayExpr.SetTy(typeManager.GetArrayTy(argElemTy, rawArrayTy.dims))
        } else {
            let elemTy = GetArrayElementTy(typeManager, rawArrayTy)
            if (typeManager.CheckTypeCompatibility(elemTy, argElemTy) == TypeCompatibility.INCOMPATIBLE) {
                if (let Some(diagValue) <- diag) {
                    DiagOld(diagValue, arrayExpr.args[0], BasicDiagKind.sema_array_single_element_type_error)
                }
                arrayExpr.SetTy(TypeManager.GetInvalidTy())
                return false
            }
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
        ok = ChkSingleArgArrayExpr(typeManager, targetTy, arrayExpr, diag: diag)
    } else if (arrayExpr.args.size == 2) {
        ok = ChkSizedArrayExpr(typeManager, targetTy, arrayExpr)
    } else {
        if (let Some(diagValue) <- diag) {
            DiagOld(diagValue, arrayExpr, BasicDiagKind.sema_array_too_much_argument)
        }
        ok = false
    }
    if (!ChkArrayArgs(arrayExpr, diag: diag)) {
        ok = false
    }
    if (ok && Ty.IsTyCorrect(arrayExpr.GetTy()) && !Ty.IsTyCorrect(arrayExpr.typeNode.getOrThrow().GetTy())) {
        arrayExpr.typeNode.getOrThrow().SetTy(arrayExpr.GetTy().getOrThrow())
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

public func ChkVArrayArg(typeManager: TypeManager, arrayExpr: ArrayExpr,
    checker!: Option<CallArgChecker> = None, diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (arrayExpr.args.size != 1) {
        if (let Some(diagValue) <- diag) {
            let builder = diagValue.DiagnoseRefactor(BasicDiagKindRefactor.sema_varray_args_number_mismatch,
                MakeRange(arrayExpr.leftParenPos, arrayExpr.rightParenPos + 1))
            builder.Emit()
        }
        return false
    }
    if (let None <- arrayExpr.typeNode) {
        return false
    }
    if (let Some(varrayTy) <- ((arrayExpr.typeNode.getOrThrow().GetTy() ?? TypeManager.GetInvalidTy()) as VArrayTy)) {
        if (varrayTy.typeArgs.isEmpty()) {
            return false
        }
        let arg = arrayExpr.args[0]
        var ret = false
        if (arrayExpr.args[0].name.Empty()) {
            let sizeTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
            let expected = typeManager.GetFunctionTy([sizeTy], varrayTy.typeArgs[0])
            if (let Some(check) <- checker) {
                ret = check(expected, arg)
            } else {
                let argTy = FuncArgTy(arg)
                ret = typeManager.CheckTypeCompatibility(expected, argTy) != TypeCompatibility.INCOMPATIBLE
            }
        } else {
            if (arg.name.Val() != "repeat") {
                if (let Some(diagValue) <- diag) {
                    let builder = diagValue.Diagnose(ToBasicPosition(arg.begin), ToBasicPosition(arg.end),
                        BasicDiagKind.sema_unknown_named_argument, args: [BasicDiagArgument(arg.name.Val())])
                    builder.AddNote("expect the name of the named parameter is 'item'")
                    builder.Emit()
                }
                return false
            }
            if (let Some(check) <- checker) {
                ret = check(varrayTy.typeArgs[0], arg)
            } else {
                let argTy = FuncArgTy(arg)
                ret = typeManager.CheckTypeCompatibility(varrayTy.typeArgs[0], argTy) !=
                    TypeCompatibility.INCOMPATIBLE
            }
        }
        if (Ty.IsTyCorrect(arrayExpr.GetTy()) && !Ty.IsTyCorrect(arrayExpr.typeNode.getOrThrow().GetTy())) {
            arrayExpr.typeNode.getOrThrow().SetTy(arrayExpr.GetTy().getOrThrow())
        }
        return ret
    }
    return false
}

public func ChkVArrayExpr(typeManager: TypeManager, target: Ty, arrayExpr: ArrayExpr,
    checker!: Option<CallArgChecker> = None, diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (let None <- arrayExpr.typeNode) {
        return false
    }
    let targetTy = UnboxOptionType(target)
    let arrayTy = arrayExpr.typeNode.getOrThrow().GetTy() ?? TypeManager.GetInvalidTy()
    if (!Ty.IsTyCorrect(arrayTy) || (let None <- (arrayTy as VArrayTy))) {
        arrayExpr.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    if (!ChkVArrayArg(typeManager, arrayExpr, checker: checker, diag: diag)) {
        arrayExpr.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    if (!typeManager.IsSubtype(arrayTy, targetTy)) {
        if (let Some(diagValue) <- diag) {
            let builder = diagValue.DiagnoseRefactor(BasicDiagKindRefactor.sema_mismatched_types,
                MakeRange(arrayExpr.begin, arrayExpr.end))
            builder.AddMainHintArguments([targetTy.String(), arrayTy.String()])
            builder.Emit()
        }
        arrayExpr.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    arrayExpr.SetTy(arrayTy)
    return true
}

public func SynVArrayExpr(typeManager: TypeManager, arrayExpr: ArrayExpr,
    checker!: Option<CallArgChecker> = None, diag!: Option<BasicDiagnosticEngine> = None): Ty {
    if (let None <- arrayExpr.typeNode) {
        return InvalidExprTy(arrayExpr)
    }
    let arrayTy = arrayExpr.typeNode.getOrThrow().GetTy() ?? TypeManager.GetInvalidTy()
    if (!Ty.IsTyCorrect(arrayTy) || (let None <- (arrayTy as VArrayTy))) {
        return InvalidExprTy(arrayExpr)
    }
    arrayExpr.SetTy(arrayTy)
    if (!ChkVArrayArg(typeManager, arrayExpr, checker: checker, diag: diag)) {
        return InvalidExprTy(arrayExpr)
    }
    return arrayExpr.GetTy() ?? TypeManager.GetInvalidTy()
}

public func ChkPointerExpr(typeManager: TypeManager, target: Ty, pointerExpr: PointerExpr,
    typeChecker!: Option<(Ty, Type) -> Bool> = None, typeSynthesizer!: Option<(Type) -> Ty> = None,
    argSynthesizer!: Option<(FuncArg) -> Ty> = None,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (let None <- pointerExpr.typeNode) {
        return false
    }
    var ret = true
    let targetTy = UnboxOptionType(target)
    let pointerTypeNode = pointerExpr.typeNode.getOrThrow()
    if (!targetTy.typeArgs.isEmpty() && Ty.IsTyCorrect(targetTy.typeArgs[0]) &&
        (!Ty.IsTyCorrect(pointerTypeNode.GetTy().getOrThrow().typeArgs[0]) ||
            pointerTypeNode.GetTy().getOrThrow().HasGeneric())) {
        pointerTypeNode.SetTy(targetTy)
    }
    if (Ty.IsTyCorrect(targetTy)) {
        if (let Some(check) <- typeChecker) {
            ret = check(targetTy, pointerTypeNode)
        } else {
            ret = typeManager.IsSubtype(pointerTypeNode.GetTy() ?? TypeManager.GetInvalidTy(), targetTy)
        }
    } else if (let Some(synthesize) <- typeSynthesizer) {
        pointerTypeNode.SetTy(synthesize(pointerTypeNode))
    }
    pointerExpr.SetTy(pointerTypeNode.GetTy() ?? TypeManager.GetInvalidTy())
    if (!Ty.IsTyCorrect(pointerExpr.GetTy())) {
        if (let Some(diagValue) <- diag) {
            DiagOld(diagValue, pointerExpr, BasicDiagKind.sema_pointer_unknow_generic_type)
        }
        return false
    } else if (!ret) {
        if (let Some(diagValue2) <- diag) {
            DiagMismatchedTypesWithFoundTy(diagValue2, pointerExpr.sourceExpr.getOrThrow(), targetTy,
                pointerExpr.GetTy().getOrThrow())
        }
    }
    if (let Some(arg) <- pointerExpr.arg) {
        let argTy = if (let Some(synthesizeArg) <- argSynthesizer) {
            synthesizeArg(arg)
        } else {
            FuncArgTy(arg)
        }
        if (!Ty.IsTyCorrect(argTy) || (!argTy.IsPointer() && !argTy.IsCFunc())) {
            if (let Some(diagValue) <- diag) {
                if (!CanSkipDiag(arg)) {
                    DiagOld(diagValue, pointerExpr, BasicDiagKind.sema_pointer_single_element_type_error)
                }
            }
            return false
        }
        if (!arg.name.Empty()) {
            if (let Some(diagValue) <- diag) {
                DiagOldStrings(diagValue, arg, BasicDiagKind.sema_unknown_named_argument, [arg.name.Val()])
            }
            return false
        }
    }
    if (Ty.IsTyCorrect(targetTy) && !typeManager.IsSubtype(pointerExpr.GetTy().getOrThrow(), targetTy)) {
        if (let Some(diagValue) <- diag) {
            let builder = diagValue.DiagnoseRefactor(BasicDiagKindRefactor.sema_mismatched_types,
                MakeRange(pointerExpr.begin, pointerExpr.end))
            builder.AddMainHintArguments([target.String(), Ty.ToString(pointerExpr.GetTy())])
            builder.Emit()
        }
        return false
    }
    return ret
}

public func SynPointerExpr(typeManager: TypeManager, pointerExpr: PointerExpr,
    typeSynthesizer!: Option<(Type) -> Ty> = None, argSynthesizer!: Option<(FuncArg) -> Ty> = None,
    diag!: Option<BasicDiagnosticEngine> = None): Ty {
    if (ChkPointerExpr(typeManager, TypeManager.GetInvalidTy(), pointerExpr, typeSynthesizer: typeSynthesizer,
        argSynthesizer: argSynthesizer, diag: diag)) {
        return pointerExpr.GetTy() ?? TypeManager.GetInvalidTy()
    }
    return InvalidExprTy(pointerExpr)
}

public func SynCFuncCall(typeManager: TypeManager, ce: CallExpr,
    argSynthesizer!: Option<(FuncArg) -> Ty> = None, diag!: Option<BasicDiagnosticEngine> = None): Bool {
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
    let argTy = if (let Some(synthesizeArg) <- argSynthesizer) {
        synthesizeArg(ce.args[0])
    } else {
        FuncArgTy(ce.args[0])
    }
    if (!Ty.IsTyCorrect(argTy)) {
        ce.SetTy(TypeManager.GetInvalidTy())
        return false
    }
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

public func ChkCStringCall(typeManager: TypeManager, target: Ty, ce: CallExpr,
    checker!: Option<CallArgChecker> = None, diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (!IsCallOfBuiltInType(ce, TypeKind.TYPE_CSTRING)) {
        return false
    }
    let cptrTy = typeManager.GetPointerTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UINT8))
    if (ce.args.size != 1) {
        if (let Some(diagValue) <- diag) {
            DiagWrongNumberOfArguments(diagValue, ce, [cptrTy])
        }
        ce.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    let argOk = if (let Some(check) <- checker) {
        check(cptrTy, ce.args[0])
    } else {
        typeManager.CheckTypeCompatibility(cptrTy, FuncArgTy(ce.args[0])) != TypeCompatibility.INCOMPATIBLE
    }
    if (!argOk) {
        ce.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    let targetTy = UnboxOptionType(target)
    if (Ty.IsTyCorrect(targetTy) && !targetTy.IsCString() && !targetTy.IsCType()) {
        if (let Some(diagValue2) <- diag) {
            DiagMismatchedTypesWithFoundTy(diagValue2, ce, target.String(), CSTRING_NAME)
        }
        ce.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    ce.SetTy(TypeManager.GetCStringTy())
    return true
}

public func ChkArrayCall(typeManager: TypeManager, ctx: Option<ASTContext>, target: Ty, ce: CallExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (!IsCallOfBuiltInType(ce, TypeKind.TYPE_ARRAY)) {
        ce.SetTy(TypeManager.GetNonNullTy(ce.GetTy() ?? TypeManager.GetInvalidTy()))
        return false
    }
    var resultTy: Ty = TypeManager.GetInvalidTy()
    DesugarArrayCall(typeManager, ctx, ce)
    let arrayExpr = (ce.desugarExpr.getOrThrow() as ArrayExpr).getOrThrow()
    let ret = if (target.IsInvalid()) {
        resultTy = SynArrayExpr(typeManager, arrayExpr, diag: diag)
        Ty.IsTyCorrect(resultTy)
    } else {
        let checked = ChkArrayExpr(typeManager, target, arrayExpr, diag: diag)
        resultTy = arrayExpr.GetTy() ?? TypeManager.GetInvalidTy()
        checked
    }
    if (!ret) {
        RecoverCallFromArrayExpr(ce)
    }
    ce.SetTy(resultTy)
    return ret
}

public func ChkVArrayCall(typeManager: TypeManager, ctx: Option<ASTContext>, target: Ty, ce: CallExpr,
    checker!: Option<CallArgChecker> = None, diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (!IsCallOfBuiltInType(ce, TypeKind.TYPE_VARRAY)) {
        return false
    }
    var resultTy: Ty = TypeManager.GetInvalidTy()
    DesugarArrayCall(typeManager, ctx, ce)
    let arrayExpr = (ce.desugarExpr.getOrThrow() as ArrayExpr).getOrThrow()
    let ret = if (target.IsInvalid()) {
        resultTy = SynVArrayExpr(typeManager, arrayExpr, checker: checker, diag: diag)
        Ty.IsTyCorrect(resultTy)
    } else {
        let checked = ChkVArrayExpr(typeManager, target, arrayExpr, checker: checker, diag: diag)
        resultTy = arrayExpr.GetTy() ?? TypeManager.GetInvalidTy()
        checked
    }
    if (!ret) {
        RecoverCallFromArrayExpr(ce)
    }
    ce.SetTy(resultTy)
    return ret
}

public func ChkPointerCall(typeManager: TypeManager, ctx: Option<ASTContext>, target: Ty, ce: CallExpr,
    typeChecker!: Option<(Ty, Type) -> Bool> = None, typeSynthesizer!: Option<(Type) -> Ty> = None,
    argSynthesizer!: Option<(FuncArg) -> Ty> = None,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (!IsCallOfBuiltInType(ce, TypeKind.TYPE_POINTER)) {
        return false
    }
    var resultTy: Ty = TypeManager.GetInvalidTy()
    DesugarPointerCall(typeManager, ctx, ce, diag: diag)
    let pointerExpr = (ce.desugarExpr.getOrThrow() as PointerExpr).getOrThrow()
    let ret = if (target.IsInvalid()) {
        resultTy = SynPointerExpr(typeManager, pointerExpr, typeSynthesizer: typeSynthesizer,
            argSynthesizer: argSynthesizer, diag: diag)
        Ty.IsTyCorrect(resultTy)
    } else {
        let checked = ChkPointerExpr(typeManager, target, pointerExpr, typeChecker: typeChecker,
            argSynthesizer: argSynthesizer, diag: diag)
        resultTy = pointerExpr.GetTy() ?? TypeManager.GetInvalidTy()
        checked
    }
    if (!ret) {
        if (let Some(arg) <- pointerExpr.arg) {
            ce.args.add(arg)
        }
        ce.desugarExpr = None
    }
    ce.SetTy(resultTy)
    return ret
}

public func ChkCFuncCall(typeManager: TypeManager, target: Ty, ce: CallExpr,
    argSynthesizer!: Option<(FuncArg) -> Ty> = None, diag!: Option<BasicDiagnosticEngine> = None): Bool {
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
    let ok = SynCFuncCall(typeManager, ce, argSynthesizer: argSynthesizer, diag: diag)
    if (!ok) {
        ce.SetTy(TypeManager.GetInvalidTy())
    }
    return ok
}

public func ChkBuiltinCall(typeManager: TypeManager, ctx: Option<ASTContext>, target: Ty, ce: CallExpr,
    diag!: Option<BasicDiagnosticEngine> = None, checker!: Option<CallArgChecker> = None,
    typeChecker!: Option<(Ty, Type) -> Bool> = None, typeSynthesizer!: Option<(Type) -> Ty> = None,
    argSynthesizer!: Option<(FuncArg) -> Ty> = None): Bool {
    if (ChkPointerCall(typeManager, ctx, target, ce, typeChecker: typeChecker,
        typeSynthesizer: typeSynthesizer, argSynthesizer: argSynthesizer, diag: diag)) {
        return true
    }
    if (ChkCStringCall(typeManager, target, ce, checker: checker, diag: diag)) {
        return true
    }
    if (ChkArrayCall(typeManager, ctx, target, ce, diag: diag)) {
        return true
    }
    if (ChkVArrayCall(typeManager, ctx, target, ce, checker: checker, diag: diag)) {
        return true
    }
    if (ChkCFuncCall(typeManager, target, ce, argSynthesizer: argSynthesizer, diag: diag)) {
        return true
    }
    return false
}

private func JoinCaseTysForBuiltin(typeManager: TypeManager, tys: ArrayList<Ty>, curFile: Option<File>): Ty {
    if (tys.isEmpty()) {
        return TypeManager.GetInvalidTy()
    }
    let tySet = TySet()
    for (ty in tys) {
        tySet.Add(ty)
    }
    return JoinAsVisibleTy(typeManager, tySet, curFile: curFile)
}

public func SelfhostPortStatus_TypeCheckBuiltinExpr(): Bool {
    return true
}
