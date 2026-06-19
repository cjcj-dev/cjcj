package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*

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

public func SameTy(lhs: Ty, rhs: Ty): Bool {
    if (lhs.kind != rhs.kind) {
        if (lhs.IsAny() && rhs.IsAny()) {
            return true
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

public func CopyTypeArgs(tys: ArrayList<Ty>): Array<Ty> {
    let out = ArrayList<Ty>()
    for (ty in tys) {
        out.add(ty)
    }
    return out.toArray()
}

public func IsPrimitiveNumericWidening(leaf: Ty, root: Ty): Bool {
    if (!leaf.IsPrimitive() || !root.IsPrimitive()) {
        return false
    }
    if (leaf.kind == root.kind) {
        return true
    }
    if (leaf.kind == TypeKind.TYPE_NOTHING) {
        return true
    }
    if (leaf.kind == TypeKind.TYPE_IDEAL_INT && (root.IsInteger() || root.IsFloating())) {
        return true
    }
    if (leaf.kind == TypeKind.TYPE_IDEAL_FLOAT && root.IsFloating()) {
        return true
    }
    if (leaf.IsSignedInteger() && root.IsSignedInteger()) {
        return TypeKindIndex(leaf.kind) <= TypeKindIndex(root.kind)
    }
    if (leaf.IsUnsignedInteger() && root.IsUnsignedInteger()) {
        return TypeKindIndex(leaf.kind) <= TypeKindIndex(root.kind)
    }
    if (leaf.IsInteger() && root.IsFloating()) {
        return true
    }
    return false
}

public func DeclIdentity(decl: Decl): String {
    if (decl.TestAttr(Attribute.IMPORTED)) {
        if (!decl.rawMangleName.isEmpty()) {
            return "${ASTKindName(decl.astKind)}:${decl.fullPackageName}:${decl.rawMangleName}"
        }
        if (!decl.mangledName.isEmpty()) {
            return "${ASTKindName(decl.astKind)}:${decl.fullPackageName}:${decl.mangledName}"
        }
    }
    return "${ASTKindName(decl.astKind)}:${decl.fullPackageName}:${decl.identifier.Val()}:${decl.begin.ToString()}"
}
