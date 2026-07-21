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
    var mapIdx: Int64 = 0
    while (mapIdx < source.entries.size) {
        target.Put(source.entries.KeyAt(mapIdx).value, source.entries.ValueAt(mapIdx))
        mapIdx++
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
    var mapIdx: Int64 = 0
    while (mapIdx < mapping.entries.size) {
        let tys = mapping.entries.ValueAt(mapIdx)
        let retained = SubstTySet()
        var tyIdx: Int64 = 0
        while (tyIdx < tys.size) {
            let mappedTy = tys.ValueAt(tyIdx)
            if (!genericListContainsTy(genericTys, mappedTy.value) ||
                typeListContainsTy(explicitTys, mappedTy.value)) {
                retained.add(mappedTy)
            }
            tyIdx++
        }
        mapping.entries.SetValueAt(mapIdx, retained)
        mapIdx++
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

public func GenerateTypeMappingForBaseExpr(typeManager: TypeManager, memberAccess: MemberAccess,
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

    let realBaseOpt = GetRealTarget(typeManager, baseExpr, baseExpr.GetTarget())
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
        GenerateTypeMappingForBaseExpr(typeManager, memberAccess, instMap)
    }
    return MultiTypeSubstToTypeSubst(instMap)
}

private func exprTarget(expr: Expr): Option<Decl> {
    if (let Some(refExpr) <- (expr as RefExpr)) {
        if (let Some(target) <- refExpr.ref.target) {
            return Some(target)
        }
        if (!refExpr.ref.targets.isEmpty()) {
            return refExpr.ref.targets[0]
        }
    } else if (let Some(memberAccess) <- (expr as MemberAccess)) {
        if (let Some(target) <- memberAccess.target) {
            return Some(target)
        }
        if (!memberAccess.targets.isEmpty()) {
            return match (memberAccess.targets[0]) {
                case Some(funcDecl) => Some(funcDecl)
                case None => None
            }
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
        let unusedTys = GetUnusedTysInTypeAlias(aliasDecl)
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

// C++ src/Sema/TypeCheckExpr.cpp:340-365 TypeCheckerImpl::HandleAlias.
private func HandleAlias(typeManager: TypeManager, expr: Expr, targets: ArrayList<Decl>): Unit {
    var idx: Int64 = 0
    while (idx < targets.size) {
        if (let Some(aliasDecl) <- (targets[idx] as TypeAliasDecl)) {
            if (let Some(_) <- aliasDecl.typeNode) {
                let innerTypeAliasTarget = GetLastTypeAliasTarget(aliasDecl)
                if (let Some(innerType) <- innerTypeAliasTarget.typeNode) {
                    if (let Some(realTarget) <- innerType.GetTarget()) {
                        targets[idx] = realTarget
                        if (let Some(reference) <- (expr as NameReferenceExpr)) {
                            let wasEmpty = reference.typeArguments.isEmpty()
                            let typeMapping = GenerateTypeMappingForTypeAliasUse(typeManager, aliasDecl, reference)
                            SubstituteTypeArguments(typeManager, innerTypeAliasTarget,
                                reference.typeArguments, typeMapping)
                            let _ = UpdateInstTysWithTypeArgs(reference)
                            if (wasEmpty && !reference.typeArguments.isEmpty()) {
                                reference.compilerAddedTyArgs = true
                            }
                        }
                    }
                }
            }
        }
        idx++
    }
}

// C++ src/Sema/TypeCheckExpr.cpp:255-260 TypeCheckerImpl::GetRealTarget(Expr*, Decl*).
private func GetRealTarget(typeManager: TypeManager, expr: Expr, target: Option<Decl>): Option<Decl> {
    if (let None <- target) {
        return None
    }
    let targets = ArrayList<Decl>()
    targets.add(target.getOrThrow())
    HandleAlias(typeManager, expr, targets)
    return Some(targets[0])
}

public func getGenericConstraintDiagNode(checkNode: Node, typeNodes: ArrayList<Type>, instTy: Ty): Node {
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

private func GetTyArgsIndexMap(typeArgs: ArrayList<Ty>): HashMap<Ty, Int64> {
    let indexMap = HashMap<Ty, Int64>()
    for (idx in 0..typeArgs.size) {
        indexMap[typeArgs[idx]] = idx
    }
    return indexMap
}

private func emitIncompleteInstantiation(diag: Option<BasicDiagnosticEngine>, node: Node,
    genericTy: GenericsTy, instTy: Ty, isNothing: Bool): Unit {
    if (let Some(diagEngine) <- diag) {
        let typeString = if (isNothing) {
            "'Nothing'"
        } else {
            "interface or abstract class '" + instTy.String() + "'"
        }
        let builder = Diagnose(diagEngine, node,
            BasicDiagKind.sema_cannot_instantiated_by_incomplete_type,
            args: [BasicDiagArgument(genericTy.String()), BasicDiagArgument(typeString)])
        if (isNothing) {
            builder.AddNote("'Nothing' type has no members")
        }
        builder.Emit()
    }
}

public func CheckUpperBound(ctx: ASTContext, typeManager: TypeManager, diag: BasicDiagnosticEngine,
    genericConstraint: GenericConstraint): Unit {
    let _ = ctx
    if (let Some(refType) <- genericConstraint.refType) {
        let _ = TypeCheckTypeCheckReferenceTypeLegality(diag, typeManager, refType)
    }
    for (upperBound in genericConstraint.upperBounds) {
        let _ = TypeCheckTypeCheckReferenceTypeLegality(diag, typeManager, upperBound)
    }
}

public func CheckGenericConstraints(ctx: ASTContext, typeManager: TypeManager, diag: BasicDiagnosticEngine,
    generic: Generic): Unit {
    if (generic.genericConstraints.isEmpty()) {
        return
    }
    for (genericConstraint in generic.genericConstraints) {
        CheckUpperBound(ctx, typeManager, diag, genericConstraint)
        var found = false
        if (let None <- genericConstraint.refType) {
            continue
        }
        let refType = genericConstraint.refType.getOrThrow()
        for (typeParameter in generic.typeParameters) {
            if (refType.ref.identifier.Val() == typeParameter.identifier.Val()) {
                found = true
                break
            }
        }
        if (!found) {
            Diagnose(diag, refType, BasicDiagKind.sema_generics_type_variable_not_defined,
                args: [BasicDiagArgument(refType.ref.identifier.Val())]).Emit()
        }
    }
}

public func CheckInstTyWithUpperbound(typeManager: TypeManager, typeMapping: TypeSubst): Bool {
    var mapIdx: Int64 = 0
    while (mapIdx < typeMapping.entries.size) {
        let tyVar = typeMapping.entries.KeyAt(mapIdx)
        let ty = typeMapping.entries.ValueAt(mapIdx)
        let genericTy = tyVar.value
        for (upperBound in genericTy.upperBounds) {
            let upperBoundTy = typeManager.GetInstantiatedTy(upperBound, typeMapping)
            if ((SameTy(ty, upperBoundTy) && ty.IsCType()) ||
                !typeManager.IsSubtype(ty, upperBoundTy, implicitBoxed: true, allowOptionBox: false)) {
                return false
            }
        }
        mapIdx++
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
        let indexMap = GetTyArgsIndexMap(expr.instTys)
        let typeArgs = expr.GetTypeArgs()
        var mapIdx: Int64 = 0
        while (mapIdx < typeMapping.entries.size) {
            let tyVar = typeMapping.entries.KeyAt(mapIdx)
            let ty = typeMapping.entries.ValueAt(mapIdx)
            let genericTy = tyVar.value
            var satisfiesConstraints = true
            for (upperBound in genericTy.upperBounds) {
                let upperBoundTy = typeManager.GetInstantiatedTy(upperBound, typeMapping)
                if (!typeManager.IsSubtype(ty, upperBoundTy)) {
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
                mapIdx++
                continue
            }

            var isIncompleteInterface = false
            if (let Some(interfaceTy) <- (ty as InterfaceTy)) {
                if (let Some(interfaceDecl) <- interfaceTy.declPtr) {
                    let interfaceStaticMembers = ArrayList<Decl>()
                    collectStaticMembers(interfaceDecl, interfaceStaticMembers)
                    isIncompleteInterface = HasIncompleteStaticFuncOrProp(ctx, interfaceDecl, interfaceStaticMembers)
                } else {
                    isIncompleteInterface = true
                }
            }
            let isInstByNothing = ty.IsNothing()
            if (isIncompleteInterface || isInstByNothing) {
                let diagNode: Node = if (typeArgs.isEmpty()) { expr } else { typeArgs[indexMap[ty]] }
                emitIncompleteInstantiation(diag, diagNode, genericTy, ty, isInstByNothing)
                return false
            }
            mapIdx++
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
                        Diagnose(diagEngine, refType,
                            BasicDiagKind.sema_generics_type_variable_not_defined,
                            args: [BasicDiagArgument(refType.ref.identifier.Val())]).Emit()
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
        if (let Some(diagEngine) <- diag) {
            let diagPos = if (typeArgs.isEmpty()) { checkNode.begin } else { typeArgs[0].begin }
            DiagnoseRefactor(diagEngine, BasicDiagKindRefactor.sema_generic_argument_no_match,
                checkNode, diagPos).Emit()
        }
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
            if (let Some(diagEngine) <- diag) {
                let range = MakeRange(checkNode.begin,
                    if (checkNode.end.IsZero()) { checkNode.begin + 1 } else { checkNode.end })
                DiagnoseRefactor(diagEngine, BasicDiagKindRefactor.sema_generic_argument_no_match,
                    checkNode, range).Emit()
            }
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
                        if (let Some(diagEngine) <- diag) {
                            let builder = Diagnose(diagEngine, checkNode,
                                BasicDiagKind.sema_generic_type_argument_not_match_constraint,
                                args: [BasicDiagArgument(declTy.String())])
                            AddNote(builder, constraint, BasicDiagKind.sema_which_constraint_not_match,
                                args: [BasicDiagArgument(instTy.String()),
                                    BasicDiagArgument("'" + upperBoundTy.String() + "'")])
                            builder.Emit()
                        }
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
                if (let Some(diagEngine) <- diag) {
                    let end = if (checkNode.end.IsZero()) { checkNode.begin + 1 } else { checkNode.end }
                    DiagnoseRefactor(diagEngine, BasicDiagKindRefactor.sema_generic_argument_no_match,
                        checkNode, MakeRange(checkNode.begin, end)).Emit()
                }
                return false
            }
        }
        if (!Ty.IsTyCorrect(decl.GetTy())) {
            return false
        }
        let genericParams = GetDeclTypeParams(decl)
        if (typeArgs.isEmpty() || genericParams.size != typeArgs.size) {
            if (let Some(diagEngine) <- diag) {
                let range = MakeRange(checkNode.begin,
                    if (checkNode.end.IsZero()) { checkNode.begin + 1 } else { checkNode.end })
                DiagnoseRefactor(diagEngine, BasicDiagKindRefactor.sema_generic_argument_no_match,
                    checkNode, range).Emit()
            }
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
                        if (let Some(diagEngine) <- diag) {
                            let builder = Diagnose(diagEngine, diagNode,
                                BasicDiagKind.sema_generic_type_argument_not_match_constraint,
                                args: [BasicDiagArgument(declTy.String())])
                            AddNote(builder, constraint, BasicDiagKind.sema_which_constraint_not_match,
                                args: [BasicDiagArgument(instTy.String()),
                                    BasicDiagArgument("'" + upperBoundTy.String() + "'")])
                            builder.Emit()
                        }
                    }
                    return false
                }
            }
        }
        return true
    }

    public func CheckGenericExpr(expr: Expr): Unit {
        let targetOption = exprTarget(expr)
        if (let None <- targetOption) {
            return
        }
        let target = targetOption.getOrThrow()
        let realTarget = GetRealTarget(typeManager, expr, targetOption)
        let rawTypeArgs = expr.GetTypeArgs()
        let instTys = exprInstantiationTys(expr)
        if ((let None <- realTarget) || (rawTypeArgs.isEmpty() && instTys.isEmpty())) {
            return
        }
        let effectiveTypeArgs = filteredTypeArgsForTarget(target, rawTypeArgs)
        expr.SetTy(GetGenericType(typeManager, realTarget.getOrThrow(), effectiveTypeArgs))
        if (!CheckGenericDeclInstantiation(realTarget.getOrThrow(), effectiveTypeArgs, expr)) {
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
