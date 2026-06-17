package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::basic.{
    DiagnosticEngine as BasicDiagnosticEngine,
    DiagArgument as BasicDiagArgument,
    DiagKind as BasicDiagKind,
    DiagKindRefactor as BasicDiagKindRefactor
}

private func typeListContainsTy(values: ArrayList<Ty>, ty: Ty): Bool {
    for (value in values) {
        if (SameTy(value, ty)) {
            return true
        }
    }
    return false
}

private func exprTarget(expr: Expr): Option<Decl> {
    if (let Some(refExpr) <- (expr as RefExpr)) {
        if (let Some(target) <- refExpr.ref.target) {
            return Some(target)
        }
        if (!refExpr.ref.targets.isEmpty()) {
            return Some(refExpr.ref.targets[0])
        }
    } else if (let Some(memberAccess) <- (expr as MemberAccess)) {
        if (let Some(target) <- memberAccess.target) {
            return Some(target)
        }
        if (!memberAccess.targets.isEmpty()) {
            return Some(memberAccess.targets[0])
        }
    }
    return None
}

private func exprInstantiationTys(expr: Expr): ArrayList<Ty> {
    let out = ArrayList<Ty>()
    if (let Some(nameRef) <- (expr as NameReferenceExpr)) {
        for (ty in nameRef.instTys) {
            out.add(ty)
        }
        if (!out.isEmpty()) {
            return out
        }
    }
    for (typeArg in expr.GetTypeArgs()) {
        if (let Some(ty) <- typeArg.GetTy()) {
            out.add(ty)
        }
    }
    return out
}

private func filteredTypeArgsForTarget(target: Decl, typeArgs: ArrayList<Type>): ArrayList<Type> {
    let out = ArrayList<Type>()
    if (let Some(aliasDecl) <- (target as TypeAliasDecl)) {
        let unusedTys = TypeCheckDeclGetUnusedTysInTypeAlias(aliasDecl)
        for (typeArg in typeArgs) {
            if (let Some(ty) <- typeArg.GetTy()) {
                if (!typeListContainsTy(unusedTys, ty)) {
                    out.add(typeArg)
                }
            } else {
                out.add(typeArg)
            }
        }
        return out
    }
    for (typeArg in typeArgs) {
        out.add(typeArg)
    }
    return out
}

private func emitGenericArgumentNoMatch(diag: Option<BasicDiagnosticEngine>, node: Node): Unit {
    if (let Some(diagEngine) <- diag) {
        diagEngine.DiagnoseRefactor(BasicDiagKindRefactor.sema_generic_argument_no_match, node.begin)
    }
}

private func emitGenericConstraintMismatch(diag: Option<BasicDiagnosticEngine>, node: Node,
    declTy: Ty, instTy: Ty, upperBoundTy: Ty, constraint: GenericConstraint): Unit {
    if (let Some(diagEngine) <- diag) {
        let builder = diagEngine.Diagnose(node.begin, node.end,
            BasicDiagKind.sema_generic_type_argument_not_match_constraint,
            args: [BasicDiagArgument(declTy.String())])
        builder.AddNote(constraint.begin, BasicDiagKind.sema_which_constraint_not_match,
            args: [BasicDiagArgument(instTy.String()), BasicDiagArgument("'" + upperBoundTy.String() + "'")])
    }
}

public func CheckUpperBound(genericConstraint: GenericConstraint): Bool {
    if (let Some(refType) <- genericConstraint.refType) {
        if (!Ty.IsTyCorrect(refType.GetTy())) {
            return false
        }
    } else {
        return false
    }
    for (upperBound in genericConstraint.upperBounds) {
        if (!Ty.IsTyCorrect(upperBound.GetTy())) {
            return false
        }
    }
    return true
}

public func CheckGenericConstraints(generic: Generic): Bool {
    for (genericConstraint in generic.genericConstraints) {
        if (!CheckUpperBound(genericConstraint)) {
            return false
        }
        if (let Some(refType) <- genericConstraint.refType) {
            var found = false
            for (typeParameter in generic.typeParameters) {
                if (refType.ref.identifier.Val() == typeParameter.identifier.Val()) {
                    found = true
                    break
                }
            }
            if (!found) {
                return false
            }
        }
    }
    return true
}

public func CheckInstTyWithUpperbound(typeManager: TypeManager, typeMapping: TypeSubst): Bool {
    for (entry in typeMapping.entries) {
        let genericTy = entry.tyVar
        for (upperBound in genericTy.upperBounds) {
            let upperBoundTy = typeManager.GetInstantiatedTy(upperBound, typeMapping)
            if ((SameTy(entry.ty, upperBoundTy) && entry.ty.IsCType()) ||
                !typeManager.IsSubtype(entry.ty, upperBoundTy, implicitBoxed: true, allowOptionBox: false)) {
                return false
            }
        }
    }
    return true
}

public func CheckGenericDeclInstantiation(typeManager: TypeManager, decl: Option<Decl>, typeArgs: ArrayList<Ty>): Bool {
    if (let Some(value) <- decl) {
        if (!Ty.IsTyCorrect(value.GetTy())) {
            return false
        }
        let genericParams = GetDeclTypeParams(value)
        if (typeArgs.isEmpty() || genericParams.size != typeArgs.size) {
            return false
        }
        if (!typeManager.CheckGenericDeclInstantiation(Some(value), typeArgs)) {
            return false
        }
        let typeMapping = GenerateTypeMapping(value, typeArgs)
        return CheckInstTyWithUpperbound(typeManager, typeMapping)
    }
    return false
}

public func CheckGenericDeclInstantiation(typeManager: TypeManager, decl: Decl, typeArgs: ArrayList<Ty>): Bool {
    return CheckGenericDeclInstantiation(typeManager, Some(decl), typeArgs)
}

public func CheckGenericDeclInstantiation(typeManager: TypeManager, decl: Decl, typeNodes: ArrayList<Type>): Bool {
    let typeArgs = ArrayList<Ty>()
    for (typeNode in typeNodes) {
        if (let Some(ty) <- typeNode.GetTy()) {
            typeArgs.add(ty)
        } else {
            return false
        }
    }
    return CheckGenericDeclInstantiation(typeManager, decl, typeArgs)
}

public func GetGenericType(typeManager: TypeManager, decl: Decl, typeArgs: ArrayList<Type>): Ty {
    if (let Some(genericParamDecl) <- (decl as GenericParamDecl)) {
        let _ = genericParamDecl
        if (!typeArgs.isEmpty()) {
            if (let Some(ty) <- decl.GetTy()) {
                return ty
            }
            return TypeManager.GetInvalidTy()
        }
    }
    if (let Some(generic) <- decl.GetGeneric()) {
        if (generic.typeParameters.size != typeArgs.size) {
            if (let Some(ty) <- decl.GetTy()) {
                return ty
            }
            return TypeManager.GetInvalidTy()
        }
        let typeMapping = TypeSubst()
        for (idx in 0..typeArgs.size) {
            if (let Some(paramTy) <- generic.typeParameters[idx].GetTy()) {
                if (let Some(genTy) <- (paramTy as GenericsTy)) {
                    if (let Some(argTy) <- typeArgs[idx].GetTy()) {
                        typeMapping.Put(genTy, argTy)
                    }
                }
            }
        }
        if (let Some(declTy) <- decl.GetTy()) {
            return typeManager.GetInstantiatedTy(declTy, typeMapping)
        }
    }
    if (let Some(ty) <- decl.GetTy()) {
        return ty
    }
    return TypeManager.GetInvalidTy()
}

public func GenerateGenericTypeMapping(typeManager: TypeManager, expr: Expr): SubstPack {
    let typeMapping = SubstPack()
    if (let Some(memberAccess) <- (expr as MemberAccess)) {
        if (let Some(baseExpr) <- memberAccess.baseExpr) {
            if (let Some(baseTy) <- baseExpr.GetTy()) {
                typeManager.GenerateGenericMapping(typeMapping, baseTy)
            }
        }
    } else if (let Some(refExpr) <- (expr as RefExpr)) {
        if (let Some(target) <- refExpr.GetTarget()) {
            if (let Some(targetTy) <- target.GetTy()) {
                typeManager.GenerateGenericMapping(typeMapping, targetTy)
            }
        }
    }
    return typeMapping
}

extend TypeCheckerImpl {
    public func CheckUpperBound(ctx: ASTContext, genericConstraint: GenericConstraint): Unit {
        let _ = ctx
        if (let Some(diagEngine) <- diag) {
            if (let Some(refType) <- genericConstraint.refType) {
                let _ = TypeCheckTypeCheckReferenceTypeLegality(diagEngine, typeManager, refType)
            }
            for (upperBound in genericConstraint.upperBounds) {
                let _ = TypeCheckTypeCheckReferenceTypeLegality(diagEngine, typeManager, upperBound)
            }
        }
    }

    public func CheckGenericConstraints(ctx: ASTContext, generic: Generic): Unit {
        for (genericConstraint in generic.genericConstraints) {
            CheckUpperBound(ctx, genericConstraint)
            if (let Some(refType) <- genericConstraint.refType) {
                var found = false
                for (typeParameter in generic.typeParameters) {
                    if (refType.ref.identifier.Val() == typeParameter.identifier.Val()) {
                        found = true
                        break
                    }
                }
                if (!found) {
                    if (let Some(diagEngine) <- diag) {
                        diagEngine.Diagnose(refType.begin, refType.end,
                            BasicDiagKind.sema_generics_type_variable_not_defined,
                            args: [BasicDiagArgument(refType.ref.identifier.Val())])
                    }
                }
            }
        }
    }

    public func CheckCallGenericDeclInstantiation(decl: Option<Decl>, typeArgs: ArrayList<Type>,
        checkNode: Expr): Bool {
        if (let Some(targetDecl) <- decl) {
            let instTys = exprInstantiationTys(checkNode)
            if (instTys.isEmpty()) {
                for (typeArg in typeArgs) {
                    if (let Some(ty) <- typeArg.GetTy()) {
                        instTys.add(ty)
                    }
                }
            }
            if (let Some(generic) <- targetDecl.GetGeneric()) {
                if (generic.typeParameters.size == instTys.size) {
                    return true
                }
            }
        }
        emitGenericArgumentNoMatch(diag, checkNode)
        return false
    }

    public func CheckGenericDeclInstantiation(decl: Option<Decl>, typeArgs: ArrayList<Ty>,
        checkNode: Node): Bool {
        if (let None <- decl) {
            return false
        }
        let targetDecl = decl.getOrThrow()
        if (!Ty.IsTyCorrect(targetDecl.GetTy())) {
            return false
        }
        let genericParams = GetDeclTypeParams(targetDecl)
        if (typeArgs.isEmpty() || genericParams.size != typeArgs.size) {
            emitGenericArgumentNoMatch(diag, checkNode)
            return false
        }
        let genericDecl = targetDecl.GetGeneric()
        if (let None <- genericDecl) {
            return true
        }
        let instantiateMap = GenerateTypeMapping(targetDecl, typeArgs)
        for (constraint in genericDecl.getOrThrow().genericConstraints) {
            if (let None <- constraint.refType) {
                return false
            }
            let refType = constraint.refType.getOrThrow()
            if (!Ty.IsTyCorrect(refType.GetTy())) {
                return false
            }
            let instTy = typeManager.GetInstantiatedTy(refType.GetTy().getOrThrow(), instantiateMap)
            if (!Ty.IsTyCorrect(instTy)) {
                return false
            }
            if (let Some(genTy) <- (instTy as GenericsTy)) {
                if (!genTy.isUpperBoundLegal) {
                    continue
                }
            }
            for (upperBound in constraint.upperBounds) {
                if (!Ty.IsTyCorrect(upperBound.GetTy())) {
                    return false
                }
                let upperBoundTy = typeManager.GetInstantiatedTy(upperBound.GetTy().getOrThrow(), instantiateMap)
                if (!Ty.IsTyCorrect(upperBoundTy)) {
                    return false
                }
                let sameTyButCType = SameTy(instTy, upperBoundTy) && instTy.IsCType()
                if (!typeManager.IsSubtype(instTy, upperBoundTy, implicitBoxed: true, allowOptionBox: false) ||
                    sameTyButCType) {
                    if (let Some(declTy) <- targetDecl.GetTy()) {
                        emitGenericConstraintMismatch(diag, checkNode, declTy, instTy, upperBoundTy, constraint)
                    }
                    return false
                }
            }
        }
        return true
    }

    public func CheckGenericDeclInstantiation(decl: Decl, typeArgs: ArrayList<Ty>, checkNode: Node): Bool {
        return CheckGenericDeclInstantiation(Some(decl), typeArgs, checkNode)
    }

    public func CheckGenericExpr(expr: Expr): Unit {
        if (let None <- exprTarget(expr)) {
            return
        }
        let target = exprTarget(expr).getOrThrow()
        let realTarget = GetRealTarget(target)
        let rawTypeArgs = expr.GetTypeArgs()
        let instTys = exprInstantiationTys(expr)
        if (rawTypeArgs.isEmpty() && instTys.isEmpty()) {
            return
        }
        let effectiveTypeArgs = filteredTypeArgsForTarget(target, rawTypeArgs)
        expr.SetTy(GetGenericType(typeManager, realTarget, effectiveTypeArgs))
        let checkTys = if (!instTys.isEmpty()) { instTys } else { exprInstantiationTys(expr) }
        if (!CheckGenericDeclInstantiation(Some(realTarget), checkTys, expr)) {
            expr.SetTy(TypeManager.GetInvalidTy())
        }
    }

    public func GenerateGenericTypeMapping(ctx: ASTContext, expr: Expr): SubstPack {
        let _ = ctx
        return GenerateGenericTypeMapping(typeManager, expr)
    }
}
