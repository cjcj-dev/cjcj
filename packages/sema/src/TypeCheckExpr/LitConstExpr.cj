package cangjie_compiler::sema.TypeCheckExpr

import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

private func InvalidLitConstExpr(lce: LitConstExpr): Ty {
    let invalidTy = TypeManager.GetInvalidTy()
    lce.SetTy(invalidTy)
    return invalidTy
}

private func GetInnerNumericType(boxTy: Ty, basicTy: Ty): Ty {
    if (boxTy.IsCoreOptionType() && boxTy.typeArgs.size == 1) {
        return GetInnerNumericType(boxTy.typeArgs[0], basicTy)
    }
    if (boxTy.HasInvalidTy()) {
        return if (boxTy.IsNumeric()) { boxTy } else { basicTy }
    }
    return if (boxTy.IsNumeric()) { boxTy } else { basicTy }
}

private func IsSameOrBoxable(typeManager: TypeManager, literalTy: Ty, target: Ty): Bool {
    if (SameTy(literalTy, target) || typeManager.IsLitBoxableType(literalTy, target)) {
        return true
    }
    if (target.IsCoreOptionType() && target.typeArgs.size == 1) {
        return IsSameOrBoxable(typeManager, literalTy, target.typeArgs[0])
    }
    return false
}

private func IsIntegerLiteralBoxable(typeManager: TypeManager, suffixKind: TypeKind, basicTy: Ty, target: Ty): Bool {
    if (target.IsCoreOptionType() && target.typeArgs.size == 1) {
        return IsIntegerLiteralBoxable(typeManager, suffixKind, basicTy, target.typeArgs[0])
    }
    if (target.IsIntegerSubType()) {
        return suffixKind == target.kind || suffixKind == TypeKind.TYPE_IDEAL_INT
    }
    return typeManager.IsLitBoxableType(basicTy, target)
}

private func IsFloatLiteralBoxable(typeManager: TypeManager, suffixKind: TypeKind, basicTy: Ty, target: Ty): Bool {
    if (target.IsCoreOptionType() && target.typeArgs.size == 1) {
        return IsFloatLiteralBoxable(typeManager, suffixKind, basicTy, target.typeArgs[0])
    }
    if (target.IsFloatingSubType()) {
        if (suffixKind == target.kind || suffixKind == TypeKind.TYPE_IDEAL_FLOAT) {
            return true
        }
    }
    return typeManager.IsLitBoxableType(basicTy, target)
}

private func DefaultIntegerKind(suffixKind: TypeKind): TypeKind {
    return if (suffixKind == TypeKind.TYPE_IDEAL_INT) { TypeKind.TYPE_INT64 } else { suffixKind }
}

private func DefaultFloatKind(suffixKind: TypeKind): TypeKind {
    return if (suffixKind == TypeKind.TYPE_IDEAL_FLOAT) { TypeKind.TYPE_FLOAT64 } else { suffixKind }
}

public func ChkLitConstExprOfTypeBool(typeManager: TypeManager, target: Ty, lce: LitConstExpr): Bool {
    let boolTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
    if (target.IsBooleanSubType()) {
        lce.SetTy(target)
        return true
    }
    if (IsSameOrBoxable(typeManager, boolTy, target) || target.IsAny() || target.IsCType()) {
        lce.SetTy(boolTy)
        return true
    }
    lce.SetTy(TypeManager.GetNonNullTy(lce.GetTy() ?? TypeManager.GetInvalidTy()))
    return false
}

public func ChkLitConstExprOfTypeUnit(typeManager: TypeManager, target: Ty, lce: LitConstExpr): Bool {
    let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
    if (target.IsAny() || target.IsUnit() || target.IsCType() || IsSameOrBoxable(typeManager, unitTy, target)) {
        lce.SetTy(unitTy)
        return true
    }
    let _ = InvalidLitConstExpr(lce)
    return false
}

public func ChkLitConstExprOfTypeInteger(typeManager: TypeManager, target: Ty, lce: LitConstExpr): Bool {
    let suffixKind = lce.GetNumLitTypeKind()
    if (suffixKind == TypeKind.TYPE_INVALID) {
        let _ = InvalidLitConstExpr(lce)
        return false
    }
    let defaultKind = DefaultIntegerKind(suffixKind)
    let basicTy = TypeManager.GetPrimitiveTy(defaultKind)
    if (target.IsIntegerSubType()) {
        if (suffixKind == target.kind || suffixKind == TypeKind.TYPE_IDEAL_INT) {
            lce.SetTy(target)
            return true
        }
        let _ = InvalidLitConstExpr(lce)
        return false
    }
    if (IsIntegerLiteralBoxable(typeManager, suffixKind, basicTy, target)) {
        lce.SetTy(GetInnerNumericType(target, basicTy))
        return true
    }
    if (target.IsAny() || target.IsCType()) {
        lce.SetTy(GetInnerNumericType(target, basicTy))
        return true
    }
    if (!target.IsInvalid()) {
        let _ = InvalidLitConstExpr(lce)
        return false
    }
    lce.SetTy(TypeManager.GetNonNullTy(lce.GetTy() ?? TypeManager.GetInvalidTy()))
    return false
}

public func ChkLitConstExprOfTypeFloat(typeManager: TypeManager, target: Ty, lce: LitConstExpr): Bool {
    let suffixKind = lce.GetNumLitTypeKind()
    if (suffixKind == TypeKind.TYPE_INVALID) {
        let _ = InvalidLitConstExpr(lce)
        return false
    }
    let defaultKind = DefaultFloatKind(suffixKind)
    let basicTy = TypeManager.GetPrimitiveTy(defaultKind)
    if (target.IsFloatingSubType()) {
        if (suffixKind == target.kind || suffixKind == TypeKind.TYPE_IDEAL_FLOAT) {
            lce.SetTy(target)
            return true
        }
        let _ = InvalidLitConstExpr(lce)
        return false
    }
    if (IsFloatLiteralBoxable(typeManager, suffixKind, basicTy, target)) {
        lce.SetTy(GetInnerNumericType(target, basicTy))
        return true
    }
    if (target.IsAny() || target.IsCType()) {
        lce.SetTy(GetInnerNumericType(target, basicTy))
        return true
    }
    lce.SetTy(TypeManager.GetNonNullTy(lce.GetTy() ?? TypeManager.GetInvalidTy()))
    return false
}

public func ChkLitConstExprOfTypeChar(typeManager: TypeManager, target: Ty, lce: LitConstExpr): Bool {
    let runeTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_RUNE)
    if (target.IsRune()) {
        lce.SetTy(target)
        return true
    }
    if (IsSameOrBoxable(typeManager, runeTy, target) || target.IsAny()) {
        lce.SetTy(runeTy)
        return true
    }
    lce.SetTy(TypeManager.GetNonNullTy(lce.GetTy() ?? TypeManager.GetInvalidTy()))
    return false
}

private func TyFromRef(ref: Option<RefType>): Option<Ty> {
    if (let Some(refType) <- ref) {
        if (let Some(refTy) <- refType.GetTy()) {
            if (Ty.IsTyCorrect(refTy)) {
                return refTy
            }
        }
    }
    return None
}

public func SynLitConstStringExpr(lce: LitConstExpr, stringTy!: Option<Ty> = None): Ty {
    if (let Some(ty) <- stringTy) {
        if (Ty.IsTyCorrect(ty)) {
            lce.SetTy(ty)
            if (let Some(siExpr) <- lce.siExpr) {
                siExpr.SetTy(ty)
            }
            return ty
        }
    }
    if (let Some(refTy) <- TyFromRef(lce.ref)) {
        lce.SetTy(refTy)
        if (let Some(siExpr) <- lce.siExpr) {
            siExpr.SetTy(refTy)
        }
        return refTy
    }
    if (let Some(currentTy) <- lce.GetTy()) {
        if (Ty.IsTyCorrect(currentTy) && currentTy.IsString()) {
            if (let Some(siExpr) <- lce.siExpr) {
                siExpr.SetTy(currentTy)
            }
            return currentTy
        }
    }
    return InvalidLitConstExpr(lce)
}

private func InterpolationPartsAreWellTyped(typeManager: TypeManager, stringTy: Ty, lce: LitConstExpr): Bool {
    if (let Some(siExpr) <- lce.siExpr) {
        var isWellTyped = true
        for (partExpr in siExpr.strPartExprs) {
            if (let Some(interpolationExpr) <- (partExpr as InterpolationExpr)) {
                if (let Some(block) <- interpolationExpr.block) {
                    if (!Ty.IsTyCorrect(block.GetTy())) {
                        interpolationExpr.SetTy(TypeManager.GetInvalidTy())
                        isWellTyped = false
                    } else if (let Some(blockTy) <- block.GetTy()) {
                        interpolationExpr.SetTy(blockTy)
                    }
                } else {
                    interpolationExpr.SetTy(TypeManager.GetInvalidTy())
                    isWellTyped = false
                }
            } else if (let Some(partLit) <- (partExpr as LitConstExpr)) {
                if (partLit.kind == LitConstKind.STRING || partLit.kind == LitConstKind.JSTRING) {
                    partLit.SetTy(stringTy)
                } else if (!ChkLitConstExprOfTypeString(typeManager, stringTy, partLit, stringTy: Some(stringTy))) {
                    isWellTyped = false
                }
            } else if (let Some(partTy) <- partExpr.GetTy()) {
                if (typeManager.CheckTypeCompatibility(stringTy, partTy) == TypeCompatibility.INCOMPATIBLE) {
                    partExpr.SetTy(TypeManager.GetInvalidTy())
                    isWellTyped = false
                }
            } else {
                partExpr.SetTy(TypeManager.GetInvalidTy())
                isWellTyped = false
            }
        }
        if (isWellTyped) {
            siExpr.SetTy(stringTy)
        }
        return isWellTyped
    }
    return true
}

public func ChkLitConstExprOfTypeString(typeManager: TypeManager, target: Ty, lce: LitConstExpr,
    stringTy!: Option<Ty> = None): Bool {
    let actualTy = SynLitConstStringExpr(lce, stringTy: stringTy)
    if (!Ty.IsTyCorrect(actualTy)) {
        return false
    }
    if (!InterpolationPartsAreWellTyped(typeManager, actualTy, lce)) {
        let _ = InvalidLitConstExpr(lce)
        return false
    }
    let isWellTyped = IsSameOrBoxable(typeManager, actualTy, target) || target.IsAny()
    if (!isWellTyped) {
        lce.SetTy(TypeManager.GetInvalidTy())
    }
    return isWellTyped
}

public func ChkLitConstExpr(typeManager: TypeManager, target: Ty, lce: LitConstExpr,
    stringTy!: Option<Ty> = None): Bool {
    let isWellTyped = match (lce.kind) {
        case LitConstKind.BOOL => ChkLitConstExprOfTypeBool(typeManager, target, lce)
        case LitConstKind.UNIT => ChkLitConstExprOfTypeUnit(typeManager, target, lce)
        case LitConstKind.INTEGER => ChkLitConstExprOfTypeInteger(typeManager, target, lce)
        case LitConstKind.RUNE_BYTE => ChkLitConstExprOfTypeInteger(typeManager, target, lce)
        case LitConstKind.FLOAT => ChkLitConstExprOfTypeFloat(typeManager, target, lce)
        case LitConstKind.RUNE => ChkLitConstExprOfTypeChar(typeManager, target, lce)
        case LitConstKind.STRING => ChkLitConstExprOfTypeString(typeManager, target, lce, stringTy: stringTy)
        case LitConstKind.JSTRING => ChkLitConstExprOfTypeString(typeManager, target, lce, stringTy: stringTy)
        case LitConstKind.NONE => false
    }
    if (!isWellTyped) {
        return false
    }
    return match (lce.kind) {
        case LitConstKind.INTEGER => ChkLitConstExprRange(lce)
        case LitConstKind.RUNE_BYTE => ChkLitConstExprRange(lce)
        case LitConstKind.FLOAT => ChkLitConstExprRange(lce)
        case _ => true
    }
}

public func SynLitConstExpr(lce: LitConstExpr, stringTy!: Option<Ty> = None): Ty {
    let synTy = match (lce.kind) {
        case LitConstKind.BOOL => TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
        case LitConstKind.UNIT => TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        case LitConstKind.INTEGER => TypeManager.GetPrimitiveTy(lce.GetNumLitTypeKind())
        case LitConstKind.RUNE_BYTE => TypeManager.GetPrimitiveTy(lce.GetNumLitTypeKind())
        case LitConstKind.FLOAT => TypeManager.GetPrimitiveTy(lce.GetNumLitTypeKind())
        case LitConstKind.RUNE => TypeManager.GetPrimitiveTy(TypeKind.TYPE_RUNE)
        case LitConstKind.STRING => SynLitConstStringExpr(lce, stringTy: stringTy)
        case LitConstKind.JSTRING => SynLitConstStringExpr(lce, stringTy: stringTy)
        case LitConstKind.NONE => TypeManager.GetInvalidTy()
    }
    if (lce.kind != LitConstKind.STRING && lce.kind != LitConstKind.JSTRING) {
        lce.SetTy(synTy)
    }
    if (lce.kind == LitConstKind.INTEGER || lce.kind == LitConstKind.RUNE_BYTE || lce.kind == LitConstKind.FLOAT) {
        let _ = ChkLitConstExprRange(lce)
    }
    return lce.GetTy() ?? TypeManager.GetInvalidTy()
}
