package cjcj::sema

import std.collection.*
import cjcj::ast.*

public func SameTypeArgs(lhs: ArrayList<Ty>, rhs: ArrayList<Ty>): Bool {
    if (lhs.size != rhs.size) {
        return false
    }
    for (idx in 0..lhs.size) {
        if (!SameTy(lhs[idx], rhs[idx])) {
            return false
        }
    }
    return true
}

private func SameClassDeclIdentity(lhs: Option<ClassDecl>, rhs: Option<ClassDecl>): Bool {
    if (let Some(left) <- lhs) {
        if (let Some(right) <- rhs) {
            return left == right
        }
        return false
    }
    if (let Some(_) <- rhs) {
        return false
    }
    return true
}

private func SameInterfaceDeclIdentity(lhs: Option<InterfaceDecl>, rhs: Option<InterfaceDecl>): Bool {
    if (let Some(left) <- lhs) {
        if (let Some(right) <- rhs) {
            return left == right
        }
        return false
    }
    if (let Some(_) <- rhs) {
        return false
    }
    return true
}

private func SameStructDeclIdentity(lhs: Option<StructDecl>, rhs: Option<StructDecl>): Bool {
    if (let Some(left) <- lhs) {
        if (let Some(right) <- rhs) {
            return left == right
        }
        return false
    }
    if (let Some(_) <- rhs) {
        return false
    }
    return true
}

private func SameEnumDeclIdentity(lhs: Option<EnumDecl>, rhs: Option<EnumDecl>): Bool {
    if (let Some(left) <- lhs) {
        if (let Some(right) <- rhs) {
            return left == right
        }
        return false
    }
    if (let Some(_) <- rhs) {
        return false
    }
    return true
}

private func SameTypeAliasDeclIdentity(lhs: Option<TypeAliasDecl>, rhs: Option<TypeAliasDecl>): Bool {
    if (let Some(left) <- lhs) {
        if (let Some(right) <- rhs) {
            return left == right
        }
        return false
    }
    if (let Some(_) <- rhs) {
        return false
    }
    return true
}

private func IsDeclIdentityTy(ty: Ty): Bool {
    return ty.IsNominal() || ty.kind == TypeKind.TYPE
}

private func SameNominalTy(lhs: Ty, rhs: Ty): Bool {
    if (lhs.name != rhs.name || !SameTypeArgs(lhs.typeArgs, rhs.typeArgs)) {
        return false
    }
    if (let Some(leftClass) <- (lhs as ClassTy)) {
        if (let Some(rightClass) <- (rhs as ClassTy)) {
            if ((leftClass as ClassThisTy).isSome() != (rightClass as ClassThisTy).isSome()) {
                return false
            }
            return SameClassDeclIdentity(leftClass.declPtr, rightClass.declPtr)
        }
        return false
    }
    if (let Some(leftInterface) <- (lhs as InterfaceTy)) {
        if (let Some(rightInterface) <- (rhs as InterfaceTy)) {
            return SameInterfaceDeclIdentity(leftInterface.declPtr, rightInterface.declPtr)
        }
        return false
    }
    if (let Some(leftStruct) <- (lhs as StructTy)) {
        if (let Some(rightStruct) <- (rhs as StructTy)) {
            return SameStructDeclIdentity(leftStruct.declPtr, rightStruct.declPtr)
        }
        return false
    }
    if (let Some(leftEnum) <- (lhs as EnumTy)) {
        if (let Some(rightEnum) <- (rhs as EnumTy)) {
            if ((leftEnum as RefEnumTy).isSome() != (rightEnum as RefEnumTy).isSome()) {
                return false
            }
            return SameEnumDeclIdentity(leftEnum.declPtr, rightEnum.declPtr)
        }
        return false
    }
    if (let Some(leftAlias) <- (lhs as TypeAliasTy)) {
        if (let Some(rightAlias) <- (rhs as TypeAliasTy)) {
            return SameTypeAliasDeclIdentity(leftAlias.declPtr, rightAlias.declPtr)
        }
        return false
    }
    return false
}

public func SameTy(lhs: Ty, rhs: Ty): Bool {
    if (lhs.kind != rhs.kind) {
        if (lhs.IsAny() && rhs.IsAny()) {
            return true
        }
        return false
    }
    if (IsDeclIdentityTy(lhs) || IsDeclIdentityTy(rhs)) {
        return SameNominalTy(lhs, rhs)
    }
    // A generic type variable is identified by its GenericParamDecl, not by its source name: two distinct decls can
    // both name their parameter `T` (e.g. ArrayList<T> and a local generic function) yet are different type variables.
    // C++ compares TyVars by pointer identity; mirror that by comparing the owning decls when both are known, so a
    // substitution keyed on one decl's `T` does not collide with another decl's `T`.
    if (let Some(leftGen) <- (lhs as GenericsTy)) {
        if (let Some(rightGen) <- (rhs as GenericsTy)) {
            if (let Some(ld) <- leftGen.decl) {
                if (let Some(rd) <- rightGen.decl) {
                    return ld == rd
                }
            }
        }
    }
    if (let Some(leftUnion) <- (lhs as UnionTy)) {
        if (let Some(rightUnion) <- (rhs as UnionTy)) {
            return leftUnion == rightUnion
        }
        return false
    }
    if (let Some(leftIntersection) <- (lhs as IntersectionTy)) {
        if (let Some(rightIntersection) <- (rhs as IntersectionTy)) {
            return leftIntersection == rightIntersection
        }
        return false
    }
    if (lhs.Hash() == rhs.Hash() && lhs.String() == rhs.String()) {
        return true
    }
    if (lhs.name != rhs.name) {
        return false
    }
    if (!SameTypeArgs(lhs.typeArgs, rhs.typeArgs)) {
        return false
    }
    if (let Some(leftFunc) <- (lhs as FuncTy)) {
        if (let Some(rightFunc) <- (rhs as FuncTy)) {
            return leftFunc.isC == rightFunc.isC &&
                leftFunc.isClosureTy == rightFunc.isClosureTy &&
                leftFunc.hasVariableLenArg == rightFunc.hasVariableLenArg &&
                leftFunc.noCast == rightFunc.noCast &&
                SameTypeArgs(leftFunc.paramTys, rightFunc.paramTys) &&
                SameTy(leftFunc.retTy, rightFunc.retTy)
        }
        return false
    }
    if (let Some(leftTuple) <- (lhs as TupleTy)) {
        if (let Some(rightTuple) <- (rhs as TupleTy)) {
            return leftTuple.isClosureTy == rightTuple.isClosureTy && SameTypeArgs(leftTuple.typeArgs, rightTuple.typeArgs)
        }
        return false
    }
    if (let Some(leftArray) <- (lhs as ArrayTy)) {
        if (let Some(rightArray) <- (rhs as ArrayTy)) {
            return leftArray.dims == rightArray.dims && SameTypeArgs(leftArray.typeArgs, rightArray.typeArgs)
        }
        return false
    }
    if (let Some(leftVArray) <- (lhs as VArrayTy)) {
        if (let Some(rightVArray) <- (rhs as VArrayTy)) {
            return leftVArray.size == rightVArray.size && SameTypeArgs(leftVArray.typeArgs, rightVArray.typeArgs)
        }
        return false
    }
    return true
}

public func SameTy(lhs: Option<Ty>, rhs: Option<Ty>): Bool {
    if (let Some(left) <- lhs) {
        if (let Some(right) <- rhs) {
            return SameTy(left, right)
        }
        return false
    }
    if (let Some(_) <- rhs) {
        return false
    }
    return true
}
