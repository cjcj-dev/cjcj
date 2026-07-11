package cjcj::sema

import std.collection.*
import cjcj::ast.*
import cjcj::ast.{GCBlames, TyVarEnv}

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
