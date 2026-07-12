package cjcj::sema

import std.collection.*
import std.sort.*
import cjcj::ast.*
import cjcj::ast.{GCBlames, TyVarEnv}
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine

func IsGenericParamExistInUpperBounds(gTy: GenericsTy, upper: Ty): Bool {
    if (!Ty.IsTyCorrect(upper)) {
        return false
    }
    let genericDecl = gTy.decl.getOrThrow()
    let visited = HashSet<Ptr<Ty>>()
    visited.add(Ptr<Ty>(gTy))
    let queue = ArrayList<Ty>()
    queue.add(upper)
    var index: Int64 = 0
    while (index < queue.size) {
        let curTy = queue[index]
        index++
        if (Ptr<Ty>(curTy) == Ptr<Ty>(gTy)) {
            return true
        }
        let curKey = Ptr<Ty>(curTy)
        if (visited.contains(curKey)) {
            continue
        }
        visited.add(curKey)
        for (arg in curTy.typeArgs) {
            if (!arg.IsGeneric()) {
                queue.add(arg)
                continue
            }
            let genericTy = (arg as GenericsTy).getOrThrow()
            if (Ptr<Ty>(genericTy) == Ptr<Ty>(gTy)) {
                return true
            }
            let upperGenericDecl = genericTy.decl.getOrThrow()
            if (upperGenericDecl.outerDecl != genericDecl.outerDecl) {
                continue
            }
            for (it in genericTy.upperBounds) {
                queue.add(it)
            }
        }
    }
    return false
}

func AreUpperBoundsDirectlyRecursive(visitedGenerics: HashSet<Ptr<GenericsTy>>, upperBound: Ty): Bool {
    if (!upperBound.IsGeneric()) {
        return false
    }
    let genericTy = (upperBound as GenericsTy).getOrThrow()
    if (visitedGenerics.contains(Ptr<GenericsTy>(genericTy))) {
        return true
    }
    let visited = HashSet<Ptr<GenericsTy>>()
    for (value in visitedGenerics) {
        visited.add(value)
    }
    visited.add(Ptr<GenericsTy>(genericTy))
    for (it in genericTy.upperBounds) {
        if (AreUpperBoundsDirectlyRecursive(visited, it)) {
            return true
        }
    }
    return false
}

func CheckAndReduceUpperBounds(typeManager: TypeManager, genericTy: GenericsTy,
    upperBounds: TySet): Bool {
    if (!Ty.AreTysCorrect(upperBounds.values)) {
        return false
    }
    if (upperBounds.Size() <= 1) {
        return true
    }
    let meetRes = MeetAsVisibleTy(typeManager, upperBounds)
    if (let ErrOrTy.TY(maxCommonChildTy) <- meetRes) {
        for (it in upperBounds.values) {
            if (Ptr<Ty>(it) != Ptr<Ty>(maxCommonChildTy)) {
                var index: Int64 = 0
                while (index < genericTy.upperBounds.size) {
                    if (Ptr<Ty>(genericTy.upperBounds[index]) == Ptr<Ty>(it)) {
                        genericTy.upperBounds.remove(at: index)
                        break
                    }
                    index++
                }
            }
        }
        return true
    }
    genericTy.isUpperBoundLegal = false
    genericTy.upperBounds.clear()
    return false
}

func ValidRecursiveConstraintCheck(diag: BasicDiagnosticEngine, generic: Generic): Bool {
    for (it in generic.typeParameters) {
        if (let Some(itTy) <- it.GetTy()) {
            let genericTy = (itTy as GenericsTy) ?? continue
            for (upper in genericTy.upperBounds) {
                if (upper.IsGeneric() &&
                    AreUpperBoundsDirectlyRecursive(HashSet<Ptr<GenericsTy>>(), upper)) {
                    let upperGenericTy = (upper as GenericsTy).getOrThrow()
                    upperGenericTy.isUpperBoundLegal = false
                    let genericDecl = genericTy.decl.getOrThrow()
                    let builder = DiagnoseRefactor(diag,
                        BasicDiagKindRefactor.sema_generic_param_directly_recursive, genericDecl,
                        arguments: [genericDecl.identifier.Val(), upperGenericTy.String()])
                    builder.Emit()
                    return false
                }
                if (!upper.IsClassLike() && IsGenericParamExistInUpperBounds(genericTy, upper)) {
                    genericTy.isUpperBoundLegal = false
                    let genericDecl = genericTy.decl.getOrThrow()
                    let builder = DiagnoseRefactor(diag,
                        BasicDiagKindRefactor.sema_generic_param_exist_in_class_irrelevant_upperbound_recursively,
                        genericDecl, arguments: [genericDecl.identifier.Val(), upper.String()])
                    builder.Emit()
                    return false
                }
            }
        }
    }
    return true
}

func CheckUpperBoundsLegalityRecursively(typeManager: TypeManager, upper: Ty): Bool {
    if (let Some(decl) <- Ty.GetDeclPtrOfTy(Some(upper))) {
        let typeArgs = upper.typeArgs
        if (!typeManager.CheckGenericDeclInstantiation(Some(decl), typeArgs)) {
            return false
        }
        for (it in typeArgs) {
            if (!CheckUpperBoundsLegalityRecursively(typeManager, it)) {
                return false
            }
        }
    }
    return true
}

func CheckUpperBoundsLegality(typeManager: TypeManager, generic: Generic): Bool {
    for (gp in generic.typeParameters) {
        if (let Some(gpTy) <- gp.GetTy()) {
            let genericsTy = (gpTy as GenericsTy) ?? return false
            for (upper in genericsTy.upperBounds) {
                if (!CheckUpperBoundsLegalityRecursively(typeManager, upper)) {
                    return false
                }
            }
        } else {
            return false
        }
    }
    return true
}

func SanityCheckForClassUpperBounds(typeManager: TypeManager, diag: BasicDiagnosticEngine,
    genericTy: GenericsTy, classUpperBounds: TySet): Unit {
    if (!CheckAndReduceUpperBounds(typeManager, genericTy, classUpperBounds)) {
        let diagInfo = Ty.GetTypesToStableStr(classUpperBounds.values, ", ")
        let genericDecl = genericTy.decl.getOrThrow()
        let builder = DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_multiple_class_upperbounds,
            genericDecl, arguments: [genericDecl.identifier.Val(), diagInfo])
        builder.Emit()
        genericDecl.EnableAttr(Attribute.IN_REFERENCE_CYCLE)
    }
}

func SanityCheckForOneGenericTy(typeManager: TypeManager, diag: BasicDiagnosticEngine,
    genericTy: GenericsTy): Unit {
    let classUpperBounds = TySet()
    var invalidUpperbound = false
    let sortedUpperTys = ArrayList<Ty>()
    for (upper in genericTy.upperBounds) {
        sortedUpperTys.add(upper)
    }
    sort(sortedUpperTys, by: { left: Ty, right: Ty =>
        if (CompTyByNames(Some(left), Some(right))) {
            Ordering.LT
        } else if (CompTyByNames(Some(right), Some(left))) {
            Ordering.GT
        } else {
            Ordering.EQ
        }
    }, stable: true)
    for (upper in sortedUpperTys) {
        if (upper.IsAny() || upper.IsCType()) {
            continue
        }
        if (upper.kind == TypeKind.TYPE_CLASS) {
            classUpperBounds.Add(upper)
        } else if (upper.kind != TypeKind.TYPE_INTERFACE) {
            let genericDecl = genericTy.decl.getOrThrow()
            let builder = DiagnoseRefactor(diag,
                BasicDiagKindRefactor.sema_upper_bound_must_be_class_or_interface, genericDecl,
                arguments: [upper.String(), genericTy.String()])
            builder.Emit()
            invalidUpperbound = true
        }
    }
    if (invalidUpperbound) {
        return
    }
    SanityCheckForClassUpperBounds(typeManager, diag, genericTy, classUpperBounds)
}

func AssumptionSanityCheck(typeManager: TypeManager, diag: BasicDiagnosticEngine, generic: Generic): Unit {
    if (!ValidRecursiveConstraintCheck(diag, generic)) {
        return
    }
    for (it in generic.typeParameters) {
        if (let Some(itTy) <- it.GetTy()) {
            let genericTy = (itTy as GenericsTy) ?? continue
            SanityCheckForOneGenericTy(typeManager, diag, genericTy)
        }
    }
}

func ExposeGenericUpperBounds(ctx: ASTContext, generic: Generic): Unit {
    for (it in generic.typeParameters) {
        if (let Some(itTy) <- it.GetTy()) {
            let genericTy = (itTy as GenericsTy) ?? continue
            let exposedUpperBounds = HashSet<Ptr<Ty>>()
            for (upper in genericTy.upperBounds) {
                exposedUpperBounds.add(Ptr<Ty>(upper))
            }
            let queue = ArrayList<GenericsTy>()
            queue.add(genericTy)
            let visited = HashSet<Ptr<GenericsTy>>()
            var index: Int64 = 0
            while (index < queue.size) {
                let gTy = queue[index]
                index++
                let genericKey = Ptr<GenericsTy>(gTy)
                if (visited.contains(genericKey)) {
                    continue
                }
                visited.add(genericKey)
                for (upper in gTy.upperBounds) {
                    if (let Some(upperGenericTy) <- (upper as GenericsTy)) {
                        queue.add(upperGenericTy)
                    } else {
                        exposedUpperBounds.add(Ptr<Ty>(upper))
                        let sourceGenericKey = Ptr<Ty>(gTy)
                        let upperKey = Ptr<Ty>(upper)
                        if (!ctx.gcBlames.contains(sourceGenericKey)) {
                            ctx.gcBlames[sourceGenericKey] = HashMap<Ptr<Ty>, HashSet<Node>>()
                        }
                        if (!ctx.gcBlames[sourceGenericKey].contains(upperKey)) {
                            ctx.gcBlames[sourceGenericKey][upperKey] = HashSet<Node>()
                        }
                        let destinationGenericKey = Ptr<Ty>(genericTy)
                        if (!ctx.gcBlames.contains(destinationGenericKey)) {
                            ctx.gcBlames[destinationGenericKey] = HashMap<Ptr<Ty>, HashSet<Node>>()
                        }
                        if (!ctx.gcBlames[destinationGenericKey].contains(upperKey)) {
                            ctx.gcBlames[destinationGenericKey][upperKey] = HashSet<Node>()
                        }
                        for (blame in ctx.gcBlames[sourceGenericKey][upperKey]) {
                            ctx.gcBlames[destinationGenericKey][upperKey].add(blame)
                        }
                    }
                }
            }
            let _ = exposedUpperBounds.remove(Ptr<Ty>(genericTy))
            genericTy.upperBounds.clear()
            for (upper in exposedUpperBounds) {
                genericTy.upperBounds.add(upper.value)
            }
        }
    }
}

private func AddConstraint(typeConstraintCollection: TyVarEnv, subTy: Ty, upperBoundTy: Ty): Unit {
    if (let Some(subGen) <- (subTy as GenericsTy)) {
        var foundUpperBound = false
        for (upper in subGen.upperBounds) {
            if (Ptr<Ty>(upper) == Ptr<Ty>(upperBoundTy)) {
                foundUpperBound = true
                break
            }
        }
        if (!foundUpperBound) {
            subGen.upperBounds.add(upperBoundTy)
        }
        let key = Ptr<GenericsTy>(subGen)
        if (let Some(upperBounds) <- typeConstraintCollection.get(key)) {
            upperBounds.add(Ptr<Ty>(upperBoundTy))
        } else {
            let upperBounds = HashSet<Ptr<Ty>>()
            upperBounds.add(Ptr<Ty>(upperBoundTy))
            typeConstraintCollection[key] = upperBounds
        }
    }
}

private func LookUpConstraintCollection(subTy: Ty, baseTy: Ty,
    typeConstraintCollection: TyVarEnv): Bool {
    if (Ptr<Ty>(subTy) == Ptr<Ty>(baseTy)) {
        return true
    }
    if (let Some(subGen) <- (subTy as GenericsTy)) {
        if (let Some(upperBounds) <- typeConstraintCollection.get(Ptr<GenericsTy>(subGen))) {
            return upperBounds.contains(Ptr<Ty>(baseTy))
        }
    }
    return false
}

private func IsUpperBoundsValid(upperBounds: ArrayList<Type>): Bool {
    for (upper in upperBounds) {
        if (!Ty.IsTyCorrect(upper.GetTy())) {
            return false
        }
    }
    return true
}

private func PerformAssumeReferenceTypeUpperBound(typeManager: TypeManager,
    typeConstraintCollection: TyVarEnv, blames: GCBlames, referenceTypeUpperBound: Type,
    typeMapping: TypeSubst): Unit {
    if (let Some(upperBoundTy) <- referenceTypeUpperBound.GetTy()) {
        if (let Some(baseDecl) <- Ty.GetDeclPtrOfTy(upperBoundTy)) {
            if (Ty.IsTyCorrect(upperBoundTy) && upperBoundTy.HasGeneric()) {
                let substituteMap = typeManager.GetSubstituteMapping(upperBoundTy, typeMapping)
                Assumption(typeManager, typeConstraintCollection, blames, baseDecl,
                    typeMapping: substituteMap)
            }
        }
    }
}

private func AssumeOneUpperBound(typeManager: TypeManager, typeConstraintCollection: TyVarEnv,
    blames: GCBlames, upperBound: Type, typeMapping: TypeSubst): Unit {
    if (upperBound.astKind == ASTKind.REF_TYPE || upperBound.astKind == ASTKind.QUALIFIED_TYPE) {
        PerformAssumeReferenceTypeUpperBound(typeManager, typeConstraintCollection, blames, upperBound,
            typeMapping)
    }
}

private func PerformAssumptionForOneGenericConstraint(typeManager: TypeManager,
    typeConstraintCollection: TyVarEnv, blames: GCBlames, gc: GenericConstraint,
    typeMapping: TypeSubst): Unit {
    if (let Some(refType) <- gc.refType) {
        if (let Some(subTypeTy) <- refType.GetTy()) {
            if (!Ty.IsTyCorrect(subTypeTy)) {
                return
            }
            let subTy = typeManager.GetInstantiatedTy(subTypeTy, typeMapping)
            for (upperBound in gc.upperBounds) {
                if (let Some(upperBoundTy) <- upperBound.GetTy()) {
                    if (!Ty.IsTyCorrect(upperBoundTy)) {
                        continue
                    }
                    let baseTy = typeManager.GetInstantiatedTy(upperBoundTy, typeMapping)
                    if (!subTy.IsGeneric() ||
                        LookUpConstraintCollection(subTy, baseTy, typeConstraintCollection)) {
                        continue
                    }
                    AddConstraint(typeConstraintCollection, subTy, baseTy)
                    let subKey = Ptr<Ty>(subTy)
                    let upperKey = Ptr<Ty>(baseTy)
                    if (!blames.contains(subKey)) {
                        blames[subKey] = HashMap<Ptr<Ty>, HashSet<Node>>()
                    }
                    let upperToBlames = blames[subKey]
                    if (!upperToBlames.contains(upperKey)) {
                        upperToBlames[upperKey] = HashSet<Node>()
                    }
                    upperToBlames[upperKey].add(gc)
                    AssumeOneUpperBound(typeManager, typeConstraintCollection, blames, upperBound,
                        typeMapping)
                }
            }
        }
    }
}

public func Assumption(typeManager: TypeManager, typeConstraintCollection: TyVarEnv,
    blames: GCBlames, decl: Decl, typeMapping!: TypeSubst = TypeSubst()): Unit {
    if (let Some(generic) <- decl.GetGeneric()) {
        for (gc in generic.genericConstraints) {
            if (let Some(_) <- gc.refType) {
                if (!gc.upperBounds.isEmpty() && IsUpperBoundsValid(gc.upperBounds)) {
                    PerformAssumptionForOneGenericConstraint(typeManager, typeConstraintCollection, blames,
                        gc, typeMapping)
                }
            }
        }
    }
}
