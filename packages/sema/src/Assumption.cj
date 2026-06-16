package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*

public class GenericConstraintBlame {
    public var subTy: Ty
    public var upperBoundTy: Ty
    public var constraint: GenericConstraint

    public init(subTy: Ty, upperBoundTy: Ty, constraint: GenericConstraint) {
        this.subTy = subTy
        this.upperBoundTy = upperBoundTy
        this.constraint = constraint
    }
}

public class AssumptionSet {
    public let constraints: Constraint = Constraint()
    public let blames: ArrayList<GenericConstraintBlame> = ArrayList<GenericConstraintBlame>()

    public init() {}
}

private func addConstraint(collection: Constraint, subTy: Ty, upperBoundTy: Ty): Unit {
    if (let Some(subGen) <- (subTy as GenericsTy)) {
        var alreadyBound = false
        for (upper in subGen.upperBounds) {
            if (SameTy(upper, upperBoundTy)) {
                alreadyBound = true
                break
            }
        }
        if (!alreadyBound) {
            subGen.upperBounds.add(upperBoundTy)
        }
        let bounds = collection.GetOrCreate(subGen)
        bounds.ubs.Add(upperBoundTy)
    }
}

private func lookupConstraintCollection(subTy: Ty, baseTy: Ty, collection: Constraint): Bool {
    if (SameTy(subTy, baseTy)) {
        return true
    }
    if (let Some(subGen) <- (subTy as GenericsTy)) {
        for (entry in collection.entries) {
            if (SameTy(entry.tyVar, subGen)) {
                return entry.bounds.ubs.Contains(baseTy)
            }
        }
    }
    return false
}

private func upperBoundsValid(upperBounds: ArrayList<Type>): Bool {
    for (upper in upperBounds) {
        if (!Ty.IsTyCorrect(upper.GetTy())) {
            return false
        }
    }
    return true
}

private func performAssumeReferenceTypeUpperBound(typeManager: TypeManager, assumptionSet: AssumptionSet,
    referenceTypeUpperBound: Type, typeMapping: TypeSubst): Unit {
    if (let Some(upperBoundTy) <- referenceTypeUpperBound.GetTy()) {
        if (let Some(baseDecl) <- Ty.GetDeclPtrOfTy(upperBoundTy)) {
            if (Ty.IsTyCorrect(upperBoundTy) && upperBoundTy.HasGeneric()) {
                let substituteMap = typeManager.GetSubstituteMapping(upperBoundTy, typeMapping)
                Assumption(typeManager, assumptionSet, baseDecl, typeMapping: substituteMap)
            }
        }
    }
}

private func assumeOneUpperBound(typeManager: TypeManager, assumptionSet: AssumptionSet, upperBound: Type,
    typeMapping: TypeSubst): Unit {
    if (upperBound.astKind == ASTKind.REF_TYPE || upperBound.astKind == ASTKind.QUALIFIED_TYPE) {
        performAssumeReferenceTypeUpperBound(typeManager, assumptionSet, upperBound, typeMapping)
    }
}

private func performAssumptionForOneGenericConstraint(typeManager: TypeManager, assumptionSet: AssumptionSet,
    gc: GenericConstraint, typeMapping: TypeSubst): Unit {
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
                    if (!subTy.IsGeneric() || lookupConstraintCollection(subTy, baseTy, assumptionSet.constraints)) {
                        continue
                    }
                    addConstraint(assumptionSet.constraints, subTy, baseTy)
                    assumptionSet.blames.add(GenericConstraintBlame(subTy, baseTy, gc))
                    assumeOneUpperBound(typeManager, assumptionSet, upperBound, typeMapping)
                }
            }
        }
    }
}

public func Assumption(typeManager: TypeManager, assumptionSet: AssumptionSet, decl: Decl,
    typeMapping!: TypeSubst = TypeSubst()): Unit {
    if (let Some(generic) <- decl.GetGeneric()) {
        for (gc in generic.genericConstraints) {
            if (let Some(_) <- gc.refType) {
                if (!gc.upperBounds.isEmpty() && upperBoundsValid(gc.upperBounds)) {
                    performAssumptionForOneGenericConstraint(typeManager, assumptionSet, gc, typeMapping)
                }
            }
        }
    }
}
