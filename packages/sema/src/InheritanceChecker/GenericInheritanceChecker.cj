package cangjie_compiler::sema.InheritanceChecker

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::basic.{DiagnosticEngine, DiagArgument, DiagKind, DiagKindRefactor, MakeRange}
import cangjie_compiler::sema.*
import cangjie_compiler::utils.{CJC_ABORT, CJC_ASSERT, CJC_NULLPTR_CHECK}

public func GetAllGenericUpperBounds(typeManager: TypeManager, decl: Decl): ArrayList<TySet> {
    if (let None <- decl.GetGeneric()) {
        return ArrayList<TySet>()
    }
    let generic = decl.GetGeneric().getOrThrow()
    let allUpperBounds = ArrayList<TySet>()
    for (typeParam in generic.typeParameters) {
        if (let None <- typeParam.GetTy()) {
            continue
        }
        let paramTy = typeParam.GetTy().getOrThrow()
        if (let None <- (paramTy as GenericsTy)) {
            continue
        }
        let genericTy = (paramTy as GenericsTy).getOrThrow()
        let tys = ArrayList<Ty>()
        for (upper in genericTy.upperBounds) {
            var foundUpper = false
            for (existingUpper in tys) {
                if (refEq(existingUpper, upper)) {
                    foundUpper = true
                    break
                }
            }
            if (!foundUpper) {
                tys.add(upper)
            }
        }
        let q = ArrayList<GenericsTy>()
        q.add(genericTy)
        let traversedTy = ArrayList<GenericsTy>()
        var qIdx: Int64 = 0
        while (qIdx < q.size) {
            let gTy = q[qIdx]
            qIdx++
            var traversed = false
            for (traversedGenericTy in traversedTy) {
                if (refEq(traversedGenericTy, gTy)) {
                    traversed = true
                    break
                }
            }
            if (traversed) {
                continue
            }
            traversedTy.add(gTy)
            for (upper in gTy.upperBounds) {
                if (upper.IsGeneric()) {
                    let upperGeneric = (upper as GenericsTy).getOrThrow()
                    q.add(upperGeneric)
                    var foundGenericUpper = false
                    for (existingGenericUpper in tys) {
                        if (refEq(existingGenericUpper, upper)) {
                            foundGenericUpper = true
                            break
                        }
                    }
                    if (!foundGenericUpper) {
                        tys.add(upper)
                    }
                }
            }
        }
        let upperBounds = TySet()
        if (tys.size > 1) {
            upperBounds.values.add(typeManager.GetIntersectionTy(tys.toArray()))
        } else {
            for (ty in tys) {
                upperBounds.values.add(ty)
            }
        }
        allUpperBounds.add(upperBounds)
    }
    return allUpperBounds
}

private func GetConstraintNodeByIndex(index: Int64, generic: Generic): Node {
    CJC_ASSERT(index < generic.typeParameters.size)
    let paramDecl = generic.typeParameters[index]
    let gTy = paramDecl.GetTy().getOrThrow()
    for (constraint in generic.genericConstraints) {
        CJC_NULLPTR_CHECK(constraint.refType)
        if (let Some(refTy) <- constraint.refType.getOrThrow().GetTy()) {
            if (refEq(refTy, gTy)) {
                return constraint
            }
        }
    }
    CJC_ABORT()
    return paramDecl
}

public func CheckGenericTypeBoundsMapped(
    parent: Decl,
    child: Decl,
    parentBounds: ArrayList<TySet>,
    childBounds: ArrayList<TySet>,
    diag: DiagnosticEngine,
    typeManager: TypeManager
): Unit {
    if (parent.GetGenericsCount() != child.GetGenericsCount()) {
        diag.Diagnose(
            child.begin,
            child.end,
            DiagKind.sema_generic_member_type_argument_different,
            args: [DiagArgument(child.identifier.Val())]
        )
        return
    }
    let childGeneric = child.GetGeneric()
    let typeMapping = typeManager.GenerateGenericMappingFromGeneric(parent, child)
    if (let None <- childGeneric) {
        return
    }
    CJC_ASSERT(parentBounds.size == childBounds.size)
    let childGenericNode = childGeneric.getOrThrow()
    for (i in 0..parentBounds.size) {
        let childUppers = childBounds[i].Clone()
        let anyTy = typeManager.GetAnyTy()
        var childUpperIdx: Int64 = 0
        while (childUpperIdx < childUppers.values.size) {
            if (refEq(childUppers.values[childUpperIdx], anyTy)) {
                childUppers.values.remove(at: childUpperIdx)
            } else {
                childUpperIdx++
            }
        }
        if (childUppers.IsEmpty()) {
            continue
        }
        let parentUppers = parentBounds[i]
        let instUppers = TySet()
        for (it in parentUppers.values) {
            let instUpper = typeManager.GetInstantiatedTy(it, typeMapping)
            var foundInstUpper = false
            for (existingInstUpper in instUppers.values) {
                if (refEq(existingInstUpper, instUpper)) {
                    foundInstUpper = true
                    break
                }
            }
            if (!foundInstUpper) {
                instUppers.values.add(instUpper)
            }
        }
        var childLooser = true
        for (upper in childUppers.values) {
            var foundSubtype = false
            for (it in instUppers.values) {
                if (typeManager.IsSubtype(it, upper)) {
                    foundSubtype = true
                    break
                }
            }
            childLooser = foundSubtype
            if (!childLooser) {
                break
            }
        }
        for (upper in instUppers.values) {
            if (!childLooser) {
                break
            }
            var hasChildSubtype = false
            for (it in childUppers.values) {
                if (!typeManager.IsTyEqual(it, upper) && typeManager.IsSubtype(it, upper)) {
                    hasChildSubtype = true
                    break
                }
            }
            childLooser = !hasChildSubtype
        }
        if (!childLooser) {
            let parentConstraints = if (instUppers.IsEmpty()) {
                "empty"
            } else {
                "'" + Ty.GetTypesToStableStr(instUppers.values, "', '") + "'"
            }
            let diagNode = GetConstraintNodeByIndex(i, childGenericNode)
            let range = MakeRange(diagNode.begin, diagNode.end)
            let builder = diag.DiagnoseRefactor(DiagKindRefactor.sema_generic_constraint_not_looser, range)
            builder.AddNote("parent constraint is " + parentConstraints)
        }
    }
}
