package cjcj::sema

import std.collection.*
import cjcj::ast.*
import cjcj::basic.{
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

private func genericListContainsTy(values: ArrayList<GenericsTy>, ty: Ty): Bool {
    for (value in values) {
        if (SameTy(value, ty)) {
            return true
        }
    }
    return false
}

private func mergeTypeSubst(target: TypeSubst, source: TypeSubst): Unit {
    for (entry in source.entries) {
        target.Put(entry.tyVar, entry.ty)
    }
}

private func collectTypeArgTys(typeArgs: ArrayList<Type>): ArrayList<Ty> {
    let out = ArrayList<Ty>()
    for (typeArg in typeArgs) {
        if (let Some(ty) <- typeArg.GetTy()) {
            out.add(ty)
        }
    }
    return out
}

private func filterPromoteMappingForExplicitBaseArgs(mapping: MultiTypeSubst, realBase: Decl,
    baseTypeArgs: ArrayList<Type>): Unit {
    if (let None <- realBase.GetTy()) {
        return
    }
    let genericTys = GetAllGenericTys(realBase.GetTy().getOrThrow())
    let explicitTys = collectTypeArgTys(baseTypeArgs)
    for (entry in mapping.entries) {
        var idx: Int64 = 0
        while (idx < entry.tys.values.size) {
            let mappedTy = entry.tys.values[idx]
            if (genericListContainsTy(genericTys, mappedTy) && !typeListContainsTy(explicitTys, mappedTy)) {
                entry.tys.values.remove(at: idx)
            } else {
                idx++
            }
        }
    }
}

private func hasUpperBoundMapping(memberAccess: MemberAccess, target: Decl): Bool {
    for (entry in memberAccess.foundUpperBoundMap) {
        if (SameDecl(entry[0], target) && !entry[1].isEmpty()) {
            return true
        }
    }
    return false
}

private func isGenericUpperBoundCall(memberAccess: MemberAccess, target: Decl): Bool {
    if (let None <- memberAccess.baseExpr) {
        return false
    }
    let baseExpr = memberAccess.baseExpr.getOrThrow()
    if (let None <- baseExpr.GetTy()) {
        return false
    }
    if (!baseExpr.GetTy().getOrThrow().IsGeneric()) {
        return false
    }
    if (let None <- target.outerDecl) {
        return false
    }
    return hasUpperBoundMapping(memberAccess, target)
}

private func generateTypeMappingForUpperBounds(typeManager: TypeManager, memberAccess: MemberAccess,
    target: Decl, typeMapping: MultiTypeSubst): Unit {
    for (entry in memberAccess.foundUpperBoundMap) {
        if (SameDecl(entry[0], target)) {
            for (upper in entry[1]) {
                typeManager.GenerateGenericMapping(typeMapping, upper)
            }
            return
        }
    }
}

private func generateTypeMappingForUpperBounds(typeManager: TypeManager, memberAccess: MemberAccess,
    target: Decl, typeMapping: SubstPack): Unit {
    for (entry in memberAccess.foundUpperBoundMap) {
        if (SameDecl(entry[0], target)) {
            for (upper in entry[1]) {
                typeManager.GenerateGenericMapping(typeMapping, upper)
            }
            return
        }
    }
}

private func generateTypeMappingForBaseExpr(typeManager: TypeManager, memberAccess: MemberAccess,
    typeMapping: MultiTypeSubst): Unit {
    if (let None <- memberAccess.baseExpr) {
        return
    }
    let baseExpr = memberAccess.baseExpr.getOrThrow()
    if (let None <- baseExpr.GetTy()) {
        return
    }
    let baseTy = baseExpr.GetTy().getOrThrow()
    if (!Ty.IsTyCorrect(baseTy)) {
        return
    }
    if (IsThisOrSuper(baseExpr)) {
        typeManager.GenerateGenericMapping(typeMapping, baseTy)
        return
    }

    let realBaseOpt = GetRealTarget(baseExpr.GetTarget())
    if (let Some(realBase) <- realBaseOpt) {
        if (realBase.astKind == ASTKind.PACKAGE_DECL) {
            return
        }
        if (let Some(memberTarget) <- memberAccess.GetTarget()) {
            if (let Some(outerDecl) <- memberTarget.outerDecl) {
                if (realBase.IsTypeDecl() || realBase.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
                    if (let Some(outerTy) <- outerDecl.GetTy()) {
                        let promoteMapping = Promotion(typeManager).GetPromoteTypeMapping(baseTy, outerTy)
                        filterPromoteMappingForExplicitBaseArgs(promoteMapping, realBase, baseExpr.GetTypeArgs())
                        MergeMultiTypeSubsts(typeMapping, promoteMapping)
                    }
                    return
                }
            }
        }
    }

    typeManager.GenerateGenericMapping(typeMapping, baseTy)
}

private func generateTypeMappingForMemberAccess(typeManager: TypeManager, memberAccess: MemberAccess,
    target: Decl): TypeSubst {
    let instMap = MultiTypeSubst()
    if (memberAccess.isExposedAccess && isGenericUpperBoundCall(memberAccess, target)) {
        generateTypeMappingForUpperBounds(typeManager, memberAccess, target, instMap)
    } else {
        generateTypeMappingForBaseExpr(typeManager, memberAccess, instMap)
    }
    return MultiTypeSubstToTypeSubst(instMap)
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
        // GAP_TODO: emission blocked on sema TypeCheckCall call-path parity (spurious fires during self-compile; see C++ dtor auto-emit DiagnosticEngine.cpp:314)
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
        // GAP_TODO: emission blocked on sema TypeCheckCall call-path parity (spurious fires during self-compile; see C++ dtor auto-emit DiagnosticEngine.cpp:314)
    }
}

private func getGenericConstraintDiagNode(checkNode: Node, typeNodes: ArrayList<Type>, instTy: Ty): Node {
    for (typeNode in typeNodes) {
        if (!typeNode.TestAttr(Attribute.COMPILER_ADD)) {
            if (let Some(typeNodeTy) <- typeNode.GetTy()) {
                if (SameTy(typeNodeTy, instTy)) {
                    return typeNode
                }
            }
        }
    }
    return checkNode
}

private func collectStaticMembers(decl: InheritableDecl, out: ArrayList<Decl>): Unit {
    for (member in decl.GetMemberDecls()) {
        if (member.IsFuncOrProp() && member.TestAttr(Attribute.STATIC)) {
            out.add(member)
        }
    }
    for (inheritedType in decl.inheritedTypes) {
        if (let Some(inheritedDecl) <- Ty.GetDeclPtrOfTy(inheritedType.GetTy())) {
            if (let Some(interfaceDecl) <- (inheritedDecl as InterfaceDecl)) {
                collectStaticMembers(interfaceDecl, out)
            }
        }
    }
}

private func getInstDiagNode(expr: NameReferenceExpr, instTy: Ty): Node {
    for (typeArg in expr.GetTypeArgs()) {
        if (!typeArg.TestAttr(Attribute.COMPILER_ADD)) {
            if (let Some(typeArgTy) <- typeArg.GetTy()) {
                if (SameTy(typeArgTy, instTy)) {
                    return typeArg
                }
            }
        }
    }
    return expr
}

private func emitIncompleteInstantiation(diag: Option<BasicDiagnosticEngine>, node: Node,
    genericTy: GenericsTy, instTy: Ty, isNothing: Bool): Unit {
    if (let Some(diagEngine) <- diag) {
        let typeString = if (isNothing) {
            "'Nothing'"
        } else {
            "interface or abstract class '" + instTy.String() + "'"
        }
        let builder = diagEngine.Diagnose(node.begin, node.end,
            BasicDiagKind.sema_cannot_instantiated_by_incomplete_type,
            args: [BasicDiagArgument(genericTy.String()), BasicDiagArgument(typeString)])
        if (isNothing) {
            builder.AddNote("'Nothing' type has no members")
        }
        // GAP_TODO: emission blocked on sema TypeCheckCall call-path parity (spurious fires during self-compile; see C++ dtor auto-emit DiagnosticEngine.cpp:314)
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
    let declOpt: Option<Decl> = decl
    return CheckGenericDeclInstantiation(typeManager, declOpt, typeArgs)
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
        if (let Some(target) <- memberAccess.GetTarget()) {
            if (memberAccess.isExposedAccess && isGenericUpperBoundCall(memberAccess, target)) {
                generateTypeMappingForUpperBounds(typeManager, memberAccess, target, typeMapping)
                return typeMapping
            }
        }
        GenerateTypeMappingForBaseExpr(typeManager, memberAccess, typeMapping)
    }
    return typeMapping
}

extend TypeCheckerImpl {
    private func candidateImplementsStaticRequirement(candidate: Decl, required: Decl): Bool {
        if (candidate.TestAttr(Attribute.ABSTRACT)) {
            return false
        }
        if (candidate.IsFunc() && required.IsFunc()) {
            return typeManager.PairIsOverrideOrImpl(candidate, required)
        }
        if (candidate.astKind == ASTKind.PROP_DECL && required.astKind == ASTKind.PROP_DECL) {
            return typeManager.PairIsOverrideOrImpl(candidate, required)
        }
        return false
    }

    private func HasIncompleteStaticFuncOrProp(ctx: ASTContext, decl: InheritableDecl,
        staticMembers: ArrayList<Decl>): Bool {
        if (!decl.TestAttr(Attribute.ABSTRACT) && decl.astKind != ASTKind.INTERFACE_DECL) {
            return false
        }
        for (staticMember in staticMembers) {
            let candidates = FieldLookup(ctx, Some(decl), staticMember.identifier.Val(),
                info: LookupInfo(file: decl.curFile))
            var found = false
            for (candidate in candidates) {
                if (candidateImplementsStaticRequirement(candidate, staticMember)) {
                    found = true
                    break
                }
            }
            if (!found) {
                return true
            }
        }
        return false
    }

    private func CheckInstTyWithUpperbound(ctx: ASTContext, typeMapping: TypeSubst,
        expr: NameReferenceExpr): Bool {
        if (typeMapping.IsEmpty()) {
            return true
        }
        for (entry in typeMapping.entries) {
            let genericTy = entry.tyVar
            var satisfiesConstraints = true
            for (upperBound in genericTy.upperBounds) {
                let upperBoundTy = typeManager.GetInstantiatedTy(upperBound, typeMapping)
                if (!typeManager.IsSubtype(entry.ty, upperBoundTy)) {
                    satisfiesConstraints = false
                    break
                }
            }
            if (!satisfiesConstraints) {
                return true
            }

            let staticMembers = ArrayList<Decl>()
            for (upperBound in genericTy.upperBounds) {
                if (let Some(upperDecl) <- Ty.GetDeclPtrOfTy(Some(upperBound))) {
                    if (let Some(inheritable) <- (upperDecl as InheritableDecl)) {
                        collectStaticMembers(inheritable, staticMembers)
                    }
                }
            }
            if (staticMembers.isEmpty()) {
                continue
            }

            var isIncompleteInterface = false
            if (let Some(interfaceTy) <- (entry.ty as InterfaceTy)) {
                if (let Some(interfaceDecl) <- interfaceTy.declPtr) {
                    let interfaceStaticMembers = ArrayList<Decl>()
                    collectStaticMembers(interfaceDecl, interfaceStaticMembers)
                    isIncompleteInterface = HasIncompleteStaticFuncOrProp(ctx, interfaceDecl, interfaceStaticMembers)
                } else {
                    isIncompleteInterface = true
                }
            }
            let isInstByNothing = entry.ty.IsNothing()
            if (isIncompleteInterface || isInstByNothing) {
                emitIncompleteInstantiation(diag, getInstDiagNode(expr, entry.ty), genericTy, entry.ty, isInstByNothing)
                return false
            }
        }
        return true
    }

    public func CheckInstTypeCompleteness(ctx: ASTContext, expr: NameReferenceExpr): Bool {
        if (let None <- exprTarget(expr)) {
            return true
        }
        var genericDecl = GetRealTarget(exprTarget(expr).getOrThrow())
        if (genericDecl.TestAttr(Attribute.CONSTRUCTOR)) {
            if (let Some(outer) <- genericDecl.outerDecl) {
                genericDecl = outer
            } else {
                return true
            }
        }
        let typeMapping = GenerateTypeMapping(genericDecl, expr.instTys)
        if (!CheckInstTyWithUpperbound(ctx, typeMapping, expr)) {
            return false
        }
        if (let Some(genericTy) <- genericDecl.GetTy()) {
            for (extendDecl in typeManager.GetAllExtendsByTy(genericTy)) {
                let extendMapping = GenerateTypeMapping(extendDecl, expr.instTys)
                if (!CheckInstTyWithUpperbound(ctx, extendMapping, expr)) {
                    return false
                }
            }
        }
        return true
    }

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
                        // GAP_TODO: emission blocked on sema TypeCheckCall call-path parity (spurious fires during self-compile; see C++ dtor auto-emit DiagnosticEngine.cpp:314)
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
        let instantiateMap = TypeSubst()
        if (let Some(memberAccess) <- (checkNode as MemberAccess)) {
            mergeTypeSubst(instantiateMap, generateTypeMappingForMemberAccess(typeManager, memberAccess, targetDecl))
        }
        mergeTypeSubst(instantiateMap, GenerateTypeMapping(targetDecl, typeArgs))
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
        let declOpt: Option<Decl> = decl
        return CheckGenericDeclInstantiation(declOpt, typeArgs, checkNode)
    }

    public func CheckGenericDeclInstantiation(decl: Decl, typeNodes: ArrayList<Type>, checkNode: Node): Bool {
        let typeArgs = ArrayList<Ty>()
        for (typeNode in typeNodes) {
            if (let Some(ty) <- typeNode.GetTy()) {
                typeArgs.add(ty)
            } else {
                emitGenericArgumentNoMatch(diag, checkNode)
                return false
            }
        }
        if (!Ty.IsTyCorrect(decl.GetTy())) {
            return false
        }
        let genericParams = GetDeclTypeParams(decl)
        if (typeArgs.isEmpty() || genericParams.size != typeArgs.size) {
            emitGenericArgumentNoMatch(diag, checkNode)
            return false
        }
        let genericDecl = decl.GetGeneric()
        if (let None <- genericDecl) {
            return true
        }
        let instantiateMap = TypeSubst()
        if (let Some(memberAccess) <- (checkNode as MemberAccess)) {
            mergeTypeSubst(instantiateMap, generateTypeMappingForMemberAccess(typeManager, memberAccess, decl))
        }
        mergeTypeSubst(instantiateMap, GenerateTypeMapping(decl, typeArgs))
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
                    if (let Some(declTy) <- decl.GetTy()) {
                        let diagNode = getGenericConstraintDiagNode(checkNode, typeNodes, instTy)
                        emitGenericConstraintMismatch(diag, diagNode, declTy, instTy, upperBoundTy, constraint)
                    }
                    return false
                }
            }
        }
        return true
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
        let realTargetOpt: Option<Decl> = realTarget
        if (!CheckGenericDeclInstantiation(realTargetOpt, checkTys, expr)) {
            expr.SetTy(TypeManager.GetInvalidTy())
        }
    }

    public func GenerateGenericTypeMapping(ctx: ASTContext, expr: Expr): SubstPack {
        let typeMapping = GenerateGenericTypeMapping(typeManager, expr)
        if (let Some(refExpr) <- (expr as RefExpr)) {
            if (let Some(symbol) <- GetCurStructSymbol(ctx, refExpr.scopeName)) {
                if (let Some(node) <- symbol.node) {
                    if (node.IsNominalDecl()) {
                        if (!Ty.IsTyCorrect(node.GetTy())) {
                            return typeMapping
                        }
                        typeManager.GenerateGenericMapping(typeMapping, node.GetTy().getOrThrow())
                    }
                }
            }
        }
        return typeMapping
    }
}
