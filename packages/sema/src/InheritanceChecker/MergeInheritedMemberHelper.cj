package cangjie_compiler::sema.InheritanceChecker

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

func UpdateUpperBoundsSetForInheritance(
    typeManager: TypeManager,
    upperBounds: ArrayList<TySet>,
    typeMapping: TypeSubst
): Unit {
    if (typeMapping.IsEmpty()) {
        return
    }
    for (bounds in upperBounds) {
        let replacement = TySet()
        for (upper in bounds.values) {
            replacement.Add(typeManager.GetInstantiatedTy(upper, typeMapping))
        }
        bounds.Clear()
        bounds.AddAll(replacement)
    }
}

func MergeUpperBoundsForInheritance(
    typeManager: TypeManager,
    src: MemberSignature,
    other: MemberSignature,
    shouldMerge: Bool
): Unit {
    if (!shouldMerge || src.upperBounds.isEmpty() || src.upperBounds.size != other.upperBounds.size) {
        return
    }
    if (let Some(srcDecl) <- src.decl) {
        if (let Some(otherDecl) <- other.decl) {
            if (SameDecl(srcDecl, otherDecl)) {
                return
            }
            let typeMapping = typeManager.GenerateGenericMappingFromGeneric(otherDecl, srcDecl)
            for (idx in 0..other.upperBounds.size) {
                for (upper in other.upperBounds[idx].values) {
                    src.upperBounds[idx].Add(typeManager.GetInstantiatedTy(upper, typeMapping))
                }
            }
        }
    }
}

func AddPossibleInconsistentTypes(target: MemberSignature, src: MemberSignature, inconsistentTypes: TySet): Unit {
    if (let Some(targetTy) <- GetMemberComparableTy(target)) {
        inconsistentTypes.Add(targetTy)
    }
    if (let Some(srcTy) <- GetMemberComparableTy(src)) {
        inconsistentTypes.Add(srcTy)
    }
}

private func GetMemberComparableTy(member: MemberSignature): Option<Ty> {
    if (let Some(ty) <- member.ty) {
        if (let Some(funcTy) <- (ty as FuncTy)) {
            return funcTy.retTy
        }
        return ty
    }
    return None
}

func UpdateInconsistentTypesForInheritance(
    member: MemberSignature,
    parent: MemberSignature,
    inconsistentTypes: TySet
): Unit {
    member.inconsistentTypes.AddAll(parent.inconsistentTypes)
    member.inconsistentTypes.AddAll(inconsistentTypes)
}

func TyOptionsDiffer(left: Option<Ty>, right: Option<Ty>): Bool {
    return !SameTy(left, right)
}

func FuncTyFromOption(ty: Option<Ty>): Option<FuncTy> {
    if (let Some(value) <- ty) {
        return value as FuncTy
    }
    return None
}

public func SelfhostPortStatus_InheritanceChecker_MergeInheritedMemberHelper(): Bool {
    return true
}
