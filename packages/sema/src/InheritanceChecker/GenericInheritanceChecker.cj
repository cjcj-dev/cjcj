package cangjie_compiler::sema.InheritanceChecker

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::basic.{DiagnosticEngine, DiagArgument, DiagKind, DiagKindRefactor, MakeRange}
import cangjie_compiler::sema.*

private func ContainsGenericTy(values: ArrayList<GenericsTy>, ty: GenericsTy): Bool {
    for (value in values) {
        if (SameTy(value, ty)) {
            return true
        }
    }
    return false
}

private func AddTyUnique(values: ArrayList<Ty>, ty: Ty): Unit {
    for (value in values) {
        if (SameTy(value, ty)) {
            return
        }
    }
    values.add(ty)
}

private func CollectGenericUpperBounds(genericTy: GenericsTy, out: ArrayList<Ty>): Unit {
    let queue = ArrayList<GenericsTy>()
    let visited = ArrayList<GenericsTy>()
    queue.add(genericTy)
    var idx: Int64 = 0
    while (idx < queue.size) {
        let current = queue[idx]
        idx++
        if (ContainsGenericTy(visited, current)) {
            continue
        }
        visited.add(current)
        for (upper in current.upperBounds) {
            AddTyUnique(out, upper)
            if (let Some(upperGeneric) <- (upper as GenericsTy)) {
                queue.add(upperGeneric)
            }
        }
    }
}

public func GetAllGenericUpperBounds(typeManager: TypeManager, decl: Decl): ArrayList<TySet> {
    let allUpperBounds = ArrayList<TySet>()
    if (let Some(generic) <- decl.GetGeneric()) {
        for (typeParam in generic.typeParameters) {
            if (let Some(paramTy) <- typeParam.GetTy()) {
                if (let Some(genericTy) <- (paramTy as GenericsTy)) {
                    let bounds = TySet()
                    let collected = ArrayList<Ty>()
                    CollectGenericUpperBounds(genericTy, collected)
                    if (collected.size > 1) {
                        bounds.Add(typeManager.GetIntersectionTy(collected.toArray()))
                    } else if (collected.size == 1) {
                        bounds.Add(collected[0])
                    }
                    allUpperBounds.add(bounds)
                }
            }
        }
    }
    return allUpperBounds
}

private func RemoveAnyTy(typeManager: TypeManager, tys: TySet): Unit {
    let anyTy = typeManager.GetAnyTy()
    var idx: Int64 = 0
    while (idx < tys.values.size) {
        if (SameTy(tys.values[idx], anyTy)) {
            tys.values.remove(at: idx)
        } else {
            idx++
        }
    }
}

private func IsChildConstraintLooser(
    typeManager: TypeManager,
    instUppers: TySet,
    childUppers: TySet,
): Bool {
    for (childUpper in childUppers.values) {
        var matched = false
        for (parentUpper in instUppers.values) {
            if (typeManager.IsSubtype(parentUpper, childUpper)) {
                matched = true
                break
            }
        }
        if (!matched) {
            return false
        }
    }
    for (parentUpper in instUppers.values) {
        for (childUpper in childUppers.values) {
            if (!typeManager.IsTyEqual(childUpper, parentUpper) && typeManager.IsSubtype(childUpper, parentUpper)) {
                return false
            }
        }
    }
    return true
}

private func InstantiateUpperBounds(typeManager: TypeManager, parentUppers: TySet, typeMapping: TypeSubst): TySet {
    let instUppers = TySet()
    for (upper in parentUppers.values) {
        instUppers.Add(typeManager.GetInstantiatedTy(upper, typeMapping))
    }
    return instUppers
}

private func ParentConstraintText(uppers: TySet): String {
    if (uppers.IsEmpty()) {
        return "empty"
    }
    return "'" + Ty.GetTypesToStableStr(uppers.values, "', '") + "'"
}

private func GetConstraintNodeByIndex(index: Int64, generic: Generic): Node {
    if (index >= generic.typeParameters.size) {
        return generic
    }
    let paramDecl = generic.typeParameters[index]
    let paramTy = paramDecl.GetTy()
    for (constraint in generic.genericConstraints) {
        if (let Some(refType) <- constraint.refType) {
            if (SameTy(refType.GetTy(), paramTy)) {
                return constraint
            }
        }
    }
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
    if (parentBounds.size != childBounds.size) {
        return
    }
    if (let None <- child.GetGeneric()) {
        return
    }
    let childGeneric = child.GetGeneric().getOrThrow()
    let typeMapping = typeManager.GenerateGenericMappingFromGeneric(parent, child)
    for (idx in 0..parentBounds.size) {
        let childUppers = childBounds[idx].Clone()
        RemoveAnyTy(typeManager, childUppers)
        if (childUppers.IsEmpty()) {
            continue
        }
        let instUppers = InstantiateUpperBounds(typeManager, parentBounds[idx], typeMapping)
        if (!IsChildConstraintLooser(typeManager, instUppers, childUppers)) {
            let diagNode = GetConstraintNodeByIndex(idx, childGeneric)
            let range = MakeRange(diagNode.begin, diagNode.end)
            let builder = diag.DiagnoseRefactor(DiagKindRefactor.sema_generic_constraint_not_looser, range)
            builder.AddNote("parent constraint is " + ParentConstraintText(instUppers))
        }
    }
}

public func SelfhostPortStatus_InheritanceChecker_GenericInheritanceChecker(): Bool {
    return true
}
