package cangjie_compiler::sema.TypeCheckExpr

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.TypeCompatibility
import cangjie_compiler::sema.TypeManager

private func ValidExprTy(expr: Option<Expr>): Option<Ty> {
    if (let Some(realExpr) <- expr) {
        if (let Some(exprTy) <- realExpr.GetTy()) {
            if (Ty.IsTyCorrect(exprTy)) {
                return exprTy
            }
        }
    }
    return None
}

private func IsLitConstExpr(expr: Option<Expr>): Bool {
    if (let Some(realExpr) <- expr) {
        if (let Some(_) <- (realExpr as LitConstExpr)) {
            return true
        }
    }
    return false
}

private func CheckRangeBound(typeManager: TypeManager, elemTy: Ty, expr: Option<Expr>): Bool {
    if (let Some(realExpr) <- expr) {
        if (let Some(exprTy) <- realExpr.GetTy()) {
            if (!Ty.IsTyCorrect(exprTy)) {
                return false
            }
            var actualTy = exprTy
            if (actualTy.IsIdeal()) {
                actualTy = typeManager.ReplaceIdealTy(actualTy)
                realExpr.SetTy(actualTy)
            }
            return typeManager.CheckTypeCompatibility(elemTy, actualTy) != TypeCompatibility.INCOMPATIBLE
        }
        return false
    }
    return true
}

private func CheckRangeStep(typeManager: TypeManager, re: RangeExpr): Bool {
    if (let Some(stepExpr) <- re.stepExpr) {
        if (let Some(stepTy) <- stepExpr.GetTy()) {
            let int64Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
            if (typeManager.CheckTypeCompatibility(int64Ty, stepTy) == TypeCompatibility.INCOMPATIBLE) {
                return false
            }
            if (stepExpr.isConst && stepExpr.constNumValue.asInt.Uint64() == 0u64) {
                return false
            }
            return true
        }
        return false
    }
    return true
}

private func BindRangeDecl(re: RangeExpr, rangeDecl: Option<StructDecl>): Bool {
    if (let Some(decl) <- rangeDecl) {
        re.decl = Some(decl)
    }
    return re.decl.isSome()
}

private func CheckRangeGenericInstantiation(typeManager: TypeManager, re: RangeExpr, elemTy: Ty): Bool {
    if (let Some(rangeDecl) <- re.decl) {
        let typeArgs = ArrayList<Ty>()
        typeArgs.add(elemTy)
        return typeManager.CheckGenericDeclInstantiation(rangeDecl, typeArgs)
    }
    return false
}

public func SynRangeExprInferElemTy(re: RangeExpr): Ty {
    let startTy = ValidExprTy(re.startExpr)
    let useStartLit = !IsLitConstExpr(re.startExpr) || IsLitConstExpr(re.stopExpr)
    if (let Some(realStartTy) <- startTy) {
        if (!realStartTy.IsNothing() && useStartLit) {
            return realStartTy
        }
    }
    if (let Some(stopTy) <- ValidExprTy(re.stopExpr)) {
        if (!stopTy.IsNothing()) {
            return stopTy
        }
    } else if (let Some(realStartTy) <- startTy) {
        return realStartTy
    }
    return TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
}

public func CheckRangeElements(typeManager: TypeManager, elemTy: Ty, re: RangeExpr): Bool {
    var isWellTyped = CheckRangeBound(typeManager, elemTy, re.startExpr)
    isWellTyped = CheckRangeBound(typeManager, elemTy, re.stopExpr) && isWellTyped
    if (isWellTyped && !CheckRangeGenericInstantiation(typeManager, re, elemTy)) {
        isWellTyped = false
    }
    if (!CheckRangeStep(typeManager, re)) {
        isWellTyped = false
    }
    return isWellTyped
}

public func SynRangeExpr(typeManager: TypeManager, re: RangeExpr, rangeDecl!: Option<StructDecl> = None): Ty {
    let invalidTy = TypeManager.GetInvalidTy()
    re.SetTy(invalidTy)
    if (!BindRangeDecl(re, rangeDecl)) {
        return invalidTy
    }
    let resolvedRangeDecl = re.decl.getOrThrow()
    var elemTy = SynRangeExprInferElemTy(re)
    if (Ty.IsTyCorrect(elemTy) && elemTy.IsIdeal() && elemTy.IsInteger()) {
        elemTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
    }
    if (!CheckRangeElements(typeManager, elemTy, re)) {
        return invalidTy
    }
    let rangeTy = typeManager.GetStructTy(resolvedRangeDecl, [elemTy])
    re.SetTy(rangeTy)
    return rangeTy
}

public func ChkRangeExpr(typeManager: TypeManager, target: Ty, re: RangeExpr,
    rangeDecl!: Option<StructDecl> = None): Bool {
    re.SetTy(TypeManager.GetInvalidTy())
    if (!BindRangeDecl(re, rangeDecl)) {
        return false
    }
    if (!Ty.IsTyCorrect(target)) {
        return false
    }
    let targetTy = TypeManager.GetNonNullTy(target)
    if (targetTy.IsRange() && targetTy.typeArgs.size == 1) {
        if (!CheckRangeElements(typeManager, targetTy.typeArgs[0], re)) {
            return false
        }
        re.SetTy(targetTy)
        return typeManager.CheckTypeCompatibility(target, targetTy) != TypeCompatibility.INCOMPATIBLE
    }
    let synTy = SynRangeExpr(typeManager, re)
    return Ty.IsTyCorrect(synTy) &&
        typeManager.CheckTypeCompatibility(target, synTy) != TypeCompatibility.INCOMPATIBLE
}
