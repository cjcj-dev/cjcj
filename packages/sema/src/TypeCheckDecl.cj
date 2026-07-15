package cjcj::sema

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagArgument as BasicDiagArgument
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.Range as BasicRange

private func TypeCheckDeclEmitDiag(
    diag: BasicDiagnosticEngine,
    node: Node,
    kind: BasicDiagKind,
    args!: Array<BasicDiagArgument> = Array<BasicDiagArgument>()
): Unit {
    let builder = diag.Diagnose(node.begin, node.end, kind, args: args)
    builder.Emit()
}

private func TypeCheckDeclAddUniqueDecl(values: ArrayList<Decl>, decl: Decl): Unit {
    for (value in values) {
        if (SameDecl(value, decl)) {
            return
        }
    }
    values.add(decl)
}

private func TypeCheckDeclIdentifierRange(decl: Decl): BasicRange {
    let beginPos = decl.identifier.Begin()
    if (!beginPos.IsZero()) {
        let endPos = decl.identifier.End()
        if (!endPos.IsZero()) {
            return MakeRange(beginPos, endPos)
        }
    }
    return MakeRange(decl.begin, decl.end)
}

public func TypeCheckDeclDiagUnableToInferDecl(diag: BasicDiagnosticEngine, decl: Decl): Unit {
    let builder = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_unable_to_infer_decl,
        MakeRangeForDeclIdentifier(decl))
    builder.Emit()
}

private func TypeCheckDeclCopyTypeArgs(args: ArrayList<Ty>): Array<Ty> {
    let out = ArrayList<Ty>()
    for (arg in args) {
        out.add(arg)
    }
    return out.toArray()
}

private func TypeCheckDeclAccessRank(level: AccessLevel): Int64 {
    return match (level) {
        case AccessLevel.PRIVATE => 0
        case AccessLevel.INTERNAL => 1
        case AccessLevel.PROTECTED => 2
        case AccessLevel.PUBLIC => 3
    }
}

private func TypeCheckDeclIsCompatibleAccessLevel(srcLevel: AccessLevel, targetLevel: AccessLevel): Bool {
    return TypeCheckDeclAccessRank(srcLevel) <= TypeCheckDeclAccessRank(targetLevel)
}

private func TypeCheckDeclAddTypeArgsOfType(typeNodeOpt: Option<Type>, out: ArrayList<Type>): Unit {
    if (let None <- typeNodeOpt) {
        return
    }
    let typeNode = typeNodeOpt.getOrThrow()
    out.add(typeNode)
    if (let Some(refType) <- (typeNode as RefType)) {
        for (arg in refType.typeArguments) {
            TypeCheckDeclAddTypeArgsOfType(Some(arg), out)
        }
    } else if (let Some(qualifiedType) <- (typeNode as QualifiedType)) {
        for (arg in qualifiedType.typeArguments) {
            TypeCheckDeclAddTypeArgsOfType(Some(arg), out)
        }
    } else if (let Some(tupleType) <- (typeNode as TupleType)) {
        for (fieldType in tupleType.fieldTypes) {
            TypeCheckDeclAddTypeArgsOfType(Some(fieldType), out)
        }
    } else if (let Some(funcType) <- (typeNode as FuncType)) {
        for (paramType in funcType.paramTypes) {
            TypeCheckDeclAddTypeArgsOfType(Some(paramType), out)
        }
        TypeCheckDeclAddTypeArgsOfType(funcType.retType, out)
    } else if (let Some(optionType) <- (typeNode as OptionType)) {
        if (let Some(desugarType) <- optionType.desugarType) {
            TypeCheckDeclAddTypeArgsOfType(Some(desugarType), out)
        }
    }
}

public func TypeCheckDeclGetTypeArgsOfType(typeNode: Option<Type>): ArrayList<Type> {
    let out = ArrayList<Type>()
    TypeCheckDeclAddTypeArgsOfType(typeNode, out)
    return out
}

public func GetRevTypeMapping(params: ArrayList<Ty>, args: ArrayList<Ty>, revTyMap: MultiTypeSubst): Unit {
    if (args.size != params.size) {
        return
    }
    var idx: Int64 = 0
    while (idx < args.size) {
        let arg = args[idx]
        if (let Some(genericTy) <- (arg as GenericsTy)) {
            revTyMap.Put(genericTy, params[idx])
        } else if (let Some(decl) <- Ty.GetDeclPtrOfTy(arg)) {
            if (let Some(declTy) <- decl.GetTy()) {
                if (Ty.IsTyCorrect(declTy)) {
                    GetRevTypeMapping(declTy.typeArgs, arg.typeArgs, revTyMap)
                }
            }
        }
        idx++
    }
}

public func GetGenericTysToInstTysMapping(genericTy: Ty, instTy: Ty): TypeSubst {
    let mapping = TypeSubst()
    if (genericTy.typeArgs.size > instTy.typeArgs.size) {
        return mapping
    }
    var idx: Int64 = 0
    while (idx < genericTy.typeArgs.size) {
        mapping.Put((genericTy.typeArgs[idx] as GenericsTy).getOrThrow(), instTy.typeArgs[idx])
        idx++
    }
    return mapping
}

public func GetAllAssumptions(source: TyVarUB, newMap: TyVarUB): Unit {
    for ((genericKey, upperBounds) in source) {
        if (newMap.contains(genericKey)) {
            continue
        }
        let copiedUpperBounds = HashSet<Ptr<Ty>>()
        for (upperKey in upperBounds) {
            copiedUpperBounds.add(upperKey)
        }
        newMap[genericKey] = copiedUpperBounds
        for (upperKey in upperBounds) {
            if (let Some(decl) <- Ty.GetDeclPtrOfTy(upperKey.value)) {
                if (let Some(genericDecl) <- decl.GetGeneric()) {
                    GetAllAssumptions(genericDecl.assumptionCollection, newMap)
                }
            }
        }
    }
}

public func TypeCheckDeclInsertEnumConstructors(
    ctx: ASTContext,
    ed: EnumDecl,
    enableMacroInLsp!: Bool = false
): Unit {
    if (ed.IsCommonMatchedWithSpecific()) {
        return
    }
    for (ctor in ed.constructors) {
        if (ctor.astKind == ASTKind.VAR_DECL) {
            ctx.InsertEnumConstructor(ctor.identifier.Val(), 0u64, ctor, enableMacroInLsp: enableMacroInLsp)
        } else if (let Some(funcDecl) <- (ctor as FuncDecl)) {
            var arity: UInt64 = 0u64
            if (let Some(body) <- funcDecl.funcBody) {
                if (!body.paramLists.isEmpty()) {
                    arity = UInt64(body.paramLists[0].params.size)
                }
            }
            ctx.InsertEnumConstructor(funcDecl.identifier.Val(), arity, funcDecl, enableMacroInLsp: enableMacroInLsp)
        }
    }
}

public func TypeCheckDeclBuildEnumConstructorMap(
    ctx: ASTContext,
    enableMacroInLsp!: Bool = false
): Unit {
    if (let Some(pkg) <- ctx.curPackage) {
        for (file in pkg.files) {
            for (decl in file.decls) {
                if (let Some(enumDecl) <- (decl as EnumDecl)) {
                    TypeCheckDeclInsertEnumConstructors(ctx, enumDecl, enableMacroInLsp: enableMacroInLsp)
                }
            }
        }
    }
}

private func TypeCheckDeclContainsEnumDecl(values: ArrayList<EnumDecl>, decl: EnumDecl): Bool {
    for (value in values) {
        if (SameDecl(value, decl)) {
            return true
        }
    }
    return false
}

public func TypeCheckDeclBuildImportedEnumConstructorMap(
    ctx: ASTContext,
    enableMacroInLsp!: Bool = false
): Unit {
    let visited = ArrayList<EnumDecl>()
    if (let Some(pkg) <- ctx.curPackage) {
        for (file in pkg.files) {
            if (let None <- ctx.resolvedImportedDeclsMap.get(file.fileHash)) {
                continue
            }
            let fileMap = ctx.resolvedImportedDeclsMap.get(file.fileHash).getOrThrow()
            for (name in fileMap.keys()) {
                if (let Some(decls) <- fileMap.get(name)) {
                    for (decl in decls) {
                        if (let Some(enumDecl) <- (decl as EnumDecl)) {
                            if (!TypeCheckDeclContainsEnumDecl(visited, enumDecl)) {
                                visited.add(enumDecl)
                                TypeCheckDeclInsertEnumConstructors(ctx, enumDecl, enableMacroInLsp: enableMacroInLsp)
                            }
                        }
                    }
                }
            }
        }
    }
}

public func TypeCheckDeclCheckEntryFunc(diag: BasicDiagnosticEngine, fd: FuncDecl): Bool {
    if (!fd.TestAttr(Attribute.GLOBAL)) {
        return true
    }
    if (let Some(file) <- fd.curFile) {
        if (file.isCommon) {
            let builder = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_common_package_has_main,
                MakeRange(fd.begin, fd.end))
            builder.Emit()
        }
    } else {
        return true
    }

    if (let Some(body) <- fd.funcBody) {
        if (let Some(retType) <- body.retType) {
            if (let Some(retTy) <- retType.GetTy()) {
                if (Ty.IsTyCorrect(retTy) && !(retTy.IsInteger() || retTy.IsUnit())) {
                    TypeCheckDeclEmitDiag(diag, fd, BasicDiagKind.sema_unexpected_return_type_for_entry)
                    return false
                }
            }
        }
        if (body.paramLists.isEmpty()) {
            return true
        }
        let params = body.paramLists[0].params
        if (params.size > 1) {
            TypeCheckDeclEmitDiag(diag, fd, BasicDiagKind.sema_unexpected_param_for_entry)
            return false
        }
        if (params.size == 1) {
            if (let Some(paramTy) <- params[0].GetTy()) {
                let isArrayTy = paramTy.IsStructArray() && paramTy.typeArgs.size == 1
                let isArrayStringTy = isArrayTy && paramTy.typeArgs[0].IsString()
                if (!isArrayStringTy) {
                    TypeCheckDeclEmitDiag(diag, fd, BasicDiagKind.sema_unexpected_param_for_entry)
                    return false
                }
            } else {
                TypeCheckDeclEmitDiag(diag, fd, BasicDiagKind.sema_unexpected_param_for_entry)
                return false
            }
        }
    }
    return true
}

public func CheckStaticVarAccessNonStatic(diag: BasicDiagnosticEngine, vd: VarDecl): Unit {
    if (!vd.TestAttr(Attribute.STATIC)) {
        return
    }
    if (let None <- vd.initializer) {
        return
    }
    let walker = Walker(vd.initializer.getOrThrow(), visitPre: { node: Node =>
        if (let Some(refExpr) <- (node as RefExpr)) {
            if (let None <- refExpr.GetTarget()) {
                return VisitAction.SKIP_CHILDREN
            }
            let target = refExpr.GetTarget().getOrThrow()
            if (target.astKind == ASTKind.FUNC_DECL) {
                return VisitAction.SKIP_CHILDREN
            }
            var hasOuterDecl = false
            if (let Some(_) <- target.outerDecl) {
                hasOuterDecl = true
            }
            let invalidAccess = !refExpr.TestAttr(Attribute.COMPILER_ADD) && !target.IsStaticOrGlobal() &&
                !target.IsTypeDecl() && !target.TestAttr(Attribute.CONSTRUCTOR) &&
                !target.TestAttr(Attribute.ENUM_CONSTRUCTOR) && hasOuterDecl
            if (invalidAccess) {
                TypeCheckDeclEmitDiag(diag, vd, BasicDiagKind.sema_static_variable_cannot_access_non_static_member,
                    args: [BasicDiagArgument(refExpr.ref.identifier.Val())])
            }
        } else if (node.astKind == ASTKind.MEMBER_ACCESS || node.astKind == ASTKind.FUNC_BODY) {
            return VisitAction.SKIP_CHILDREN
        }
        VisitAction.WALK_CHILDREN
    })
    walker.Walk()
}

public func CheckPropDecl(pd: PropDecl, typeSynthesizer: (Type) -> Ty, declSynthesizer: (Decl) -> Ty,
    diag!: Option<BasicDiagnosticEngine> = None): Ty {
    if (pd.TestAttr(Attribute.IS_CHECK_VISITED)) {
        return pd.GetTy() ?? TypeManager.GetInvalidTy()
    }
    pd.EnableAttr(Attribute.IS_CHECK_VISITED)
    let redefModifier = FindModifier(pd, TokenKind.REDEF)
    let staticModifier = FindModifier(pd, TokenKind.STATIC)
    if (let Some(modifier) <- redefModifier) {
        if (let None <- staticModifier) {
            if (let Some(diagValue) <- diag) {
                TypeCheckDeclEmitDiag(diagValue, modifier, BasicDiagKind.sema_redef_modify_static_func,
                    args: [BasicDiagArgument("property")])
            }
            pd.SetTy(TypeManager.GetInvalidTy())
        }
    }
    let typeNode = pd.typeNode.getOrThrow()
    let _ = typeSynthesizer(typeNode)
    pd.SetTy(typeNode.GetTy() ?? TypeManager.GetInvalidTy())
    for (getter in pd.getters) {
        if (let Some(body) <- getter.funcBody) {
            if (!body.paramLists.isEmpty()) {
                if (!body.paramLists[0].params.isEmpty()) {
                    if (let Some(diagValue2) <- diag) {
                        TypeCheckDeclEmitDiag(diagValue2, getter, BasicDiagKind.sema_cannot_have_parameter,
                            args: [BasicDiagArgument("getter")])
                    }
                }
                if (body.paramLists.size > 1) {
                    if (let Some(diagValue3) <- diag) {
                        TypeCheckDeclEmitDiag(diagValue3, getter, BasicDiagKind.sema_cannot_currying,
                            args: [BasicDiagArgument("getter")])
                    }
                }
            }
        }
        let _ = declSynthesizer(getter)
    }
    for (setter in pd.setters) {
        if (let Some(body2) <- setter.funcBody) {
            if (body2.paramLists.size > 1) {
                if (let Some(diagValue4) <- diag) {
                    TypeCheckDeclEmitDiag(diagValue4, setter, BasicDiagKind.sema_cannot_currying,
                        args: [BasicDiagArgument("setter")])
                }
            }
        }
        let _ = declSynthesizer(setter)
    }
    return pd.GetTy() ?? TypeManager.GetInvalidTy()
}

public func TypeCheckDeclCheckOperatorOverloadFunc(diag: BasicDiagnosticEngine, fd: FuncDecl): Bool {
    if (fd.op == TokenKind.ILLEGAL || fd.op == TokenKind.LPAREN) {
        return true
    }
    if (let Some(rawTy) <- fd.GetTy()) {
        if (let Some(funcTy) <- (rawTy as FuncTy)) {
            if (!Ty.IsTyCorrect(funcTy)) {
                return true
            }
            if (fd.op == TokenKind.LSQUARE) {
                return TypeCheckDeclCheckIndexOperatorOverload(diag, fd, funcTy)
            }
            if (funcTy.paramTys.size == 0) {
                if (!IsUnaryOperator(fd.op)) {
                    TypeCheckDeclEmitDiag(diag, fd, BasicDiagKind.sema_operator_overload_invalid_num_parameter,
                        args: [BasicDiagArgument(fd.identifier.Val())])
                    return false
                }
                if (let Some(outer) <- fd.outerDecl) {
                    if (let Some(baseTy) <- outer.GetTy()) {
                        if (IsBuiltinUnaryExpr(fd.op, baseTy)) {
                            TypeCheckDeclEmitDiag(diag, fd,
                                BasicDiagKind.sema_operator_overload_built_in_unary_operator,
                                args: [BasicDiagArgument(fd.identifier.Val()), BasicDiagArgument(baseTy.String())])
                            return false
                        }
                    }
                }
                return true
            }
            if (funcTy.paramTys.size == 1) {
                if (!IsBinaryOperator(fd.op)) {
                    TypeCheckDeclEmitDiag(diag, fd, BasicDiagKind.sema_operator_overload_invalid_num_parameter,
                        args: [BasicDiagArgument(fd.identifier.Val())])
                    return false
                }
                if (fd.fullPackageName != "std.core") {
                    if (let Some(outer) <- fd.outerDecl) {
                        if (let Some(baseTy) <- outer.GetTy()) {
                            if (IsBuiltinBinaryExpr(fd.op, baseTy, funcTy.paramTys[0])) {
                                TypeCheckDeclEmitDiag(diag, fd,
                                    BasicDiagKind.sema_operator_overload_built_in_binary_operator,
                                    args: [
                                        BasicDiagArgument(fd.identifier.Val()),
                                        BasicDiagArgument(baseTy.String()),
                                        BasicDiagArgument(funcTy.paramTys[0].String())
                                    ])
                                return false
                            }
                        }
                    }
                }
                return true
            }
        } else {
            return true
        }
    } else {
        return true
    }
    TypeCheckDeclEmitDiag(diag, fd, BasicDiagKind.sema_operator_overload_invalid_num_parameter,
        args: [BasicDiagArgument(fd.identifier.Val())])
    return false
}

public func TypeCheckDeclCheckIndexOperatorOverload(
    diag: BasicDiagnosticEngine,
    fd: FuncDecl,
    funcTy: FuncTy
): Bool {
    let _ = funcTy
    if (let None <- fd.funcBody) {
        return true
    }
    let body = fd.funcBody.getOrThrow()
    if (body.paramLists.isEmpty()) {
        TypeCheckDeclEmitDiag(diag, fd, BasicDiagKind.sema_operator_overload_invalid_num_parameter,
            args: [BasicDiagArgument(fd.identifier.Val())])
        return false
    }
    let params = body.paramLists[0].params
    if (params.isEmpty()) {
        TypeCheckDeclEmitDiag(diag, fd, BasicDiagKind.sema_operator_overload_invalid_num_parameter,
            args: [BasicDiagArgument(fd.identifier.Val())])
        return false
    }
    if (!params[params.size - 1].isNamedParam) {
        return true
    }
    var valid = true
    let invalidNamedParams = ArrayList<FuncParam>()
    for (param in params) {
        if (param.isNamedParam && param.identifier.Val() != "value") {
            valid = false
            invalidNamedParams.add(param)
        }
    }
    if (!invalidNamedParams.isEmpty()) {
        let first = invalidNamedParams[0]
        let builder = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_invalid_subscript_assign_parameter,
            TypeCheckDeclIdentifierRange(first))
        var idx: Int64 = 1
        while (idx < invalidNamedParams.size) {
            builder.AddHint(TypeCheckDeclIdentifierRange(invalidNamedParams[idx]))
            idx++
        }
        builder.Emit()
    }
    if (params.size <= 1) {
        let builder = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_invalid_subscript_assign_parameter_num,
            TypeCheckDeclIdentifierRange(fd))
        builder.Emit()
        valid = false
    }
    if (valid && Ty.IsTyCorrect(fd.GetTy())) {
        if (let Some(realFuncTy) <- (fd.GetTy().getOrThrow() as FuncTy)) {
            if (!realFuncTy.retTy.IsUnit()) {
                let range = if (let Some(retType) <- body.retType) {
                    MakeRange(retType.begin, retType.end)
                } else {
                    TypeCheckDeclIdentifierRange(fd)
                }
                let builder = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_invalid_subscript_assign_return, range)
                builder.Emit()
                valid = false
            }
        }
    }
    return valid
}

public func TypeCheckDeclSynchronizeTypeAndInitializer(
    tm: TypeManager,
    vd: VarDeclAbstract,
    diag!: Option<BasicDiagnosticEngine> = None,
    checker!: Option<(Ty, Expr) -> Bool> = None
): Ty {
    if (let Some(typeNode) <- vd.typeNode) {
        if (let Some(typeTy) <- typeNode.GetTy()) {
            if (Ty.IsTyCorrect(typeTy)) {
                vd.SetTy(typeTy)
                if (let Some(initializer) <- vd.initializer) {
                    if (typeTy.IsRune() && IsSingleRuneStringLiteral(initializer)) {
                        initializer.SetTy(typeTy)
                    } else if (typeTy.kind == TypeKind.TYPE_UINT8 && IsSingleByteStringLiteral(initializer)) {
                        initializer.SetTy(typeTy)
                        if (let Some(lit) <- (initializer as LitConstExpr)) {
                            let _ = ChkLitConstExprRange(lit, diag: diag)
                        }
                    } else if (let Some(check) <- checker) {
                        let _ = check(typeTy, initializer)
                    }
                }
                return typeTy
            }
        }
        vd.SetTy(TypeManager.GetInvalidTy())
        return TypeManager.GetInvalidTy()
    }
    if (let Some(initializer) <- vd.initializer) {
        if (let Some(initTy) <- initializer.GetTy()) {
            if (let Some(thisTy) <- (initTy as ClassThisTy)) {
                if (let Some(decl) <- thisTy.declPtr) {
                    let classTy = tm.GetClassTy(decl, TypeCheckDeclCopyTypeArgs(thisTy.typeArgs))
                    vd.SetTy(classTy)
                    return classTy
                }
            }
            if (let Some(funcTy) <- (initTy as FuncTy)) {
                if (funcTy.isC && funcTy.hasVariableLenArg) {
                    vd.SetTy(TypeManager.GetInvalidTy())
                    if (let Some(diagValue) <- diag) {
                        if (vd.ShouldDiagnose() && !CanSkipDiag(initializer)) {
                            TypeCheckDeclEmitDiag(diagValue, initializer,
                                BasicDiagKind.sema_cfunc_var_cannot_have_var_param)
                        }
                    }
                    return TypeManager.GetInvalidTy()
                }
            }
            vd.SetTy(initTy)
            return initTy
        }
    }
    return TypeManager.GetInvalidTy()
}

public func TypeCheckDeclSetEnumElementTy(
    tm: TypeManager,
    constructor: Decl,
    diag!: Option<BasicDiagnosticEngine> = None
): Ty {
    if (!constructor.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
        return constructor.GetTy() ?? TypeManager.GetInvalidTy()
    }
    if (Ty.IsTyCorrect(constructor.GetTy())) {
        return constructor.GetTy().getOrThrow()
    }
    if (constructor.astKind == ASTKind.VAR_DECL) {
        if (let Some(outer) <- constructor.outerDecl) {
            if (let Some(outerTy) <- outer.GetTy()) {
                constructor.SetTy(outerTy)
                return outerTy
            }
        }
        constructor.SetTy(TypeManager.GetInvalidTy())
        return TypeManager.GetInvalidTy()
    }
    if (let Some(funcDecl) <- (constructor as FuncDecl)) {
        return TypeCheckDeclSetEnumElementTyForFunc(tm, funcDecl, diag: diag)
    }
    if (let Some(diagValue) <- diag) {
        TypeCheckDeclEmitDiag(diagValue, constructor, BasicDiagKind.sema_invalid_constructor_in_enum)
    }
    constructor.SetTy(TypeManager.GetInvalidTy())
    return TypeManager.GetInvalidTy()
}

private func TypeCheckDeclCheckEnumFuncDeclIsCStructParam(diag: BasicDiagnosticEngine, funcDecl: FuncDecl): Unit {
    if (let None <- funcDecl.funcBody) {
        return
    }
    let body = funcDecl.funcBody.getOrThrow()
    if (body.paramLists.isEmpty()) {
        return
    }
    for (param in body.paramLists[0].params) {
        if (let Some(paramTy) <- param.GetTy()) {
            if (Ty.IsCStructType(paramTy)) {
                if (let Some(structTy) <- (paramTy as StructTy)) {
                    if (let Some(decl) <- structTy.declPtr) {
                        if (decl.identifier.Val() != "String") {
                            if (let Some(outer) <- funcDecl.outerDecl) {
                                TypeCheckDeclEmitDiag(diag, funcDecl,
                                    BasicDiagKind.sema_enum_pattern_func_param_cty_error,
                                    args: [
                                        BasicDiagArgument(funcDecl.identifier.Val()),
                                        BasicDiagArgument(outer.identifier.Val())
                                    ])
                            }
                        }
                    }
                }
            }
        }
    }
}

public func TypeCheckDeclSetEnumElementTyForFunc(
    tm: TypeManager,
    funcDecl: FuncDecl,
    diag!: Option<BasicDiagnosticEngine> = None
): Ty {
    if (let None <- funcDecl.outerDecl) {
        funcDecl.SetTy(TypeManager.GetInvalidTy())
        return TypeManager.GetInvalidTy()
    }
    if (let None <- funcDecl.funcBody) {
        funcDecl.SetTy(TypeManager.GetInvalidTy())
        return TypeManager.GetInvalidTy()
    }
    let body = funcDecl.funcBody.getOrThrow()
    if (body.paramLists.isEmpty()) {
        funcDecl.SetTy(TypeManager.GetInvalidTy())
        return TypeManager.GetInvalidTy()
    }
    let paramTys = ArrayList<Ty>()
    for (param in body.paramLists[0].params) {
        if (let Some(typeNode) <- param.typeNode) {
            if (let Some(paramTy) <- typeNode.GetTy()) {
                param.SetTy(paramTy)
                paramTys.add(paramTy)
            } else {
                paramTys.add(TypeManager.GetInvalidTy())
            }
        }
    }
    let retTy = funcDecl.outerDecl.getOrThrow().GetTy() ?? TypeManager.GetInvalidTy()
    let ctorTy = tm.GetFunctionTy(paramTys.toArray(), retTy)
    body.SetTy(ctorTy)
    funcDecl.SetTy(ctorTy)
    let retType = RefType()
    retType.SetTy(retTy)
    retType.begin = funcDecl.begin
    retType.end = funcDecl.end
    retType.EnableAttr(Attribute.COMPILER_ADD)
    body.retType = Some(retType)
    if (let Some(diagValue) <- diag) {
        let outer = funcDecl.outerDecl.getOrThrow()
        if (outer.TestAttr(Attribute.C)) {
            TypeCheckDeclEmitDiag(diagValue, funcDecl, BasicDiagKind.sema_enum_pattern_func_cty_error,
                args: [BasicDiagArgument(funcDecl.identifier.Val()), BasicDiagArgument(outer.identifier.Val())])
        } else {
            TypeCheckDeclCheckEnumFuncDeclIsCStructParam(diagValue, funcDecl)
        }
    }
    return ctorTy
}

public func CheckEnumDecl(diag: BasicDiagnosticEngine, tm: TypeManager, enumDecl: EnumDecl,
    typeSynthesizer: (Type) -> Ty, declSynthesizer: (Decl) -> Ty): Ty {
    if (enumDecl.TestAttr(Attribute.IS_CHECK_VISITED)) {
        return enumDecl.GetTy() ?? TypeManager.GetInvalidTy()
    }
    enumDecl.EnableAttr(Attribute.IS_CHECK_VISITED)
    for (interfaceType in enumDecl.inheritedTypes) {
        let _ = typeSynthesizer(interfaceType)
    }
    let _ = TypeCheckDeclCheckEnumInheritedTypes(diag, enumDecl)
    for (constructor in enumDecl.constructors) {
        let _ = TypeCheckAnnotationCheckAnnotations(diag, tm, constructor)
        let walker = Walker(constructor, visitPre: { node: Node =>
            if (let Some(typeNode) <- (node as Type)) {
                let _ = typeSynthesizer(typeNode)
                return VisitAction.SKIP_CHILDREN
            }
            VisitAction.WALK_CHILDREN
        })
        walker.Walk()
    }
    for (member in enumDecl.members) {
        if (let Some(funcDecl) <- (member as FuncDecl)) {
            let _ = declSynthesizer(funcDecl)
        } else if (let Some(propDecl) <- (member as PropDecl)) {
            let _ = declSynthesizer(propDecl)
            if (propDecl.isVar) {
                let range = if (let Some(modifier) <- FindModifier(propDecl, TokenKind.MUT)) {
                    MakeRange(modifier.begin, modifier.end)
                } else {
                    TypeCheckDeclIdentifierRange(propDecl)
                }
                let builder = diag.DiagnoseRefactor(
                    BasicDiagKindRefactor.sema_immutable_type_illegal_property,
                    range)
                builder.Emit()
            }
        }
    }
    return enumDecl.GetTy() ?? TypeManager.GetInvalidTy()
}

public func TypeCheckDeclGetUnusedTysInTypeAlias(tad: TypeAliasDecl): ArrayList<Ty> {
    let unused = ArrayList<Ty>()
    if (let None <- tad.generic) {
        return unused
    }
    if (let None <- tad.typeNode) {
        return unused
    }
    let typeNode = tad.typeNode.getOrThrow()
    if (Ty.IsInitialTy(typeNode.GetTy())) {
        return unused
    }
    let used = TypeCheckDeclCollectTyArgsRecursive(typeNode.GetTy() ?? TypeManager.GetInvalidTy())
    for (param in tad.generic.getOrThrow().typeParameters) {
        if (let Some(paramTy) <- param.GetTy()) {
            var found = false
            for (candidate in used) {
                if (SameTy(candidate, paramTy)) {
                    found = true
                    break
                }
            }
            if (!found) {
                unused.add(paramTy)
            }
        }
    }
    return unused
}

private func TypeCheckDeclCollectTyArgsRecursive(ty: Ty): ArrayList<Ty> {
    let out = ArrayList<Ty>()
    TypeCheckDeclCollectTyArgsInto(ty, out)
    return out
}

private func TypeCheckDeclCollectTyArgsInto(ty: Ty, out: ArrayList<Ty>): Unit {
    if (!Ty.IsTyCorrect(ty)) {
        return
    }
    for (arg in ty.typeArgs) {
        var exists = false
        for (value in out) {
            if (SameTy(value, arg)) {
                exists = true
                break
            }
        }
        if (!exists) {
            out.add(arg)
        }
        TypeCheckDeclCollectTyArgsInto(arg, out)
    }
}

public func TypeCheckDeclCollectNominalMembers(decl: Decl): ArrayList<Decl> {
    let out = ArrayList<Decl>()
    for (member in decl.GetMemberDecls()) {
        TypeCheckDeclAddUniqueDecl(out, member)
    }
    return out
}

public func CheckTypeAliasAccess(diag: BasicDiagnosticEngine, tad: TypeAliasDecl): Unit {
    if (tad.TestAttr(Attribute.PRIVATE)) {
        return
    }
    let tadLevel = GetAccessLevel(tad)
    let tadLevelStr = GetAccessLevelStr(tad)
    for (typeNode in TypeCheckDeclGetTypeArgsOfType(tad.typeNode)) {
        if (typeNode.astKind != ASTKind.REF_TYPE) {
            continue
        }
        if (let Some(refType) <- (typeNode as RefType)) {
            if (let Some(target) <- refType.ref.target) {
                if (target.astKind != ASTKind.GENERIC_PARAM_DECL &&
                    !TypeCheckDeclIsCompatibleAccessLevel(tadLevel, GetAccessLevel(target))) {
                    Diagnose(diag, tad, BasicDiagKind.sema_typealias_external_refer_internal,
                        args: [
                            BasicDiagArgument(tadLevelStr),
                            BasicDiagArgument(tad.identifier.Val()),
                            BasicDiagArgument(GetAccessLevelStr(target)),
                            BasicDiagArgument(target.identifier.Val())
                        ]).Emit()
                }
            }
        }
    }
}

public func CheckTypeAlias(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    tad: TypeAliasDecl
): Unit {
    if (tad.TestAttr(Attribute.IS_CHECK_VISITED)) {
        return
    }
    tad.EnableAttr(Attribute.IS_CHECK_VISITED)
    if (let None <- tad.typeNode) {
        return
    }
    let typeNode = tad.typeNode.getOrThrow()
    if (!Ty.IsTyCorrect(typeNode.GetTy())) {
        return
    }
    CheckTypeAliasAccess(diag, tad)
    if (let Some(_) <- tad.generic) {
        let unusedTys = TypeCheckDeclGetUnusedTysInTypeAlias(tad)
        if (!unusedTys.isEmpty()) {
            Diagnose(diag, tad, BasicDiagKind.typealias_unused_type_parameters,
                args: [BasicDiagArgument(Ty.GetTypesToStr(unusedTys, ","))]).Emit()
        }
    }
    if (!typeNode.TestAttr(Attribute.IS_CHECK_VISITED)) {
        let _ = TypeCheckTypeCheckReferenceTypeLegality(diag, tm, typeNode)
    }
}

private func TypeCheckDeclAddSubtypeToInterface(interfaceDecl: InterfaceDecl, decl: Decl): Unit {
    for (value in interfaceDecl.subDecls) {
        if (SameDecl(value, decl)) {
            return
        }
    }
    interfaceDecl.subDecls.add(decl)
}

private func TypeCheckDeclCheckImplementedInterfaces(
    diag: BasicDiagnosticEngine,
    declKind: String,
    decl: InheritableDecl
): Bool {
    var valid = true
    for (interfaceType in decl.inheritedTypes) {
        var hasInterface = false
        if (let Some(target) <- Ty.GetDeclPtrOfTy(interfaceType.GetTy())) {
            if (let Some(interfaceDecl) <- (target as InterfaceDecl)) {
                TypeCheckClassLikeCheckSealedInheritance(diag, decl, interfaceType)
                TypeCheckDeclAddSubtypeToInterface(interfaceDecl, decl)
                hasInterface = true
            }
        }
        if (!hasInterface) {
            interfaceType.SetTy(TypeManager.GetInvalidTy())
            TypeCheckDeclEmitDiag(diag, decl, BasicDiagKind.sema_type_implement_non_interface,
                args: [BasicDiagArgument(declKind), BasicDiagArgument(decl.identifier.Val())])
            valid = false
        }
    }
    return valid
}

public func TypeCheckDeclCheckEnumInheritedTypes(diag: BasicDiagnosticEngine, enumDecl: EnumDecl): Bool {
    return TypeCheckDeclCheckImplementedInterfaces(diag, "enum", enumDecl)
}

public func TypeCheckDeclCheckEnumMemberRules(diag: BasicDiagnosticEngine, enumDecl: EnumDecl): Bool {
    var valid = true
    for (member in enumDecl.members) {
        if (let Some(propDecl) <- (member as PropDecl)) {
            if (propDecl.isVar) {
                let range = if (let Some(modifier) <- FindModifier(propDecl, TokenKind.MUT)) {
                    MakeRange(modifier.begin, modifier.end)
                } else {
                    TypeCheckDeclIdentifierRange(propDecl)
                }
                let builder = diag.DiagnoseRefactor(
                    BasicDiagKindRefactor.sema_immutable_type_illegal_property,
                    range)
                builder.Emit()
                valid = false
            }
        }
    }
    return valid
}

public func TypeCheckDeclCheckStructInheritedTypes(diag: BasicDiagnosticEngine, structDecl: StructDecl): Bool {
    var valid = TypeCheckDeclCheckImplementedInterfaces(diag, "struct", structDecl)
    if (let Some(structTy) <- structDecl.GetTy()) {
        if (Ty.IsCStructType(structTy)) {
            if (let Some(generic) <- structDecl.generic) {
                let builder = diag.Diagnose(generic.leftAnglePos,
                    BasicDiagKind.sema_cffi_cannot_have_type_param,
                    args: [BasicDiagArgument("struct with @C")])
                builder.Emit()
                valid = false
            }
            if (!structDecl.inheritedTypes.isEmpty()) {
                let builder = diag.DiagnoseRefactor(
                    BasicDiagKindRefactor.sema_cstruct_cannot_impl_interfaces,
                    TypeCheckDeclIdentifierRange(structDecl))
                builder.Emit()
                valid = false
            }
        }
    }
    return valid
}
