package cjcj::sema.TypeCheckExpr

import std.collection.*
import cjcj::ast.*
import cjcj::sema.*
import cjcj::sema.Desugar.*

private func SubscriptInvalid(se: SubscriptExpr): Ty {
    return TcInvalid(se)
}

private func PropagateSubscriptDesugarTarget(se: SubscriptExpr, desugar: Expr): Unit {
    if (let Some(callExpr) <- (desugar as CallExpr)) {
        if (let Some(resolved) <- callExpr.resolvedFunction) {
            ReplaceTarget(se, Some(resolved))
        }
    }
}

private func CheckIndexAsInt64(typeManager: TypeManager, expr: Expr): Bool {
    let int64Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
    return ChkExprShallow(typeManager, int64Ty, expr)
}

private func TupleIndex(typeManager: TypeManager, expr: Expr): Option<Int64> {
    if (let Some(lit) <- (expr as LitConstExpr)) {
        if (!CheckIndexAsInt64(typeManager, expr)) {
            return None
        }
        InitializeLitConstValue(lit)
        if (lit.constNumValue.asInt.IsNegativeNum()) {
            return None
        }
        return Some(Int64(lit.constNumValue.asInt.Uint64()))
    }
    return None
}

private func ChkTupleAccess(typeManager: TypeManager, target: Option<Ty>, se: SubscriptExpr, tupleTy: TupleTy): Bool {
    if (se.indexExprs.size != 1) {
        let _ = SubscriptInvalid(se)
        return false
    }
    if (let Some(index) <- TupleIndex(typeManager, se.indexExprs[0])) {
        if (index < 0 || index >= tupleTy.typeArgs.size) {
            let _ = SubscriptInvalid(se)
            return false
        }
        let elementTy = tupleTy.typeArgs[index]
        if (let Some(targetTy) <- target) {
            if (let Some(baseTupleLit) <- (se.baseExpr.getOrThrow() as TupleLit)) {
                if (index < baseTupleLit.children.size) {
                    if (!ChkExprShallow(typeManager, targetTy, baseTupleLit.children[index])) {
                        baseTupleLit.SetTy(TypeManager.GetInvalidTy())
                        let _ = SubscriptInvalid(se)
                        return false
                    }
                    let elemTys = ArrayList<Ty>()
                    for (child in baseTupleLit.children) {
                        elemTys.add(TcReplaceIdeal(typeManager, child))
                    }
                    baseTupleLit.SetTy(typeManager.GetTupleTy(elemTys.toArray()))
                    let updatedTy = elemTys[index]
                    se.isTupleAccess = true
                    se.SetTy(updatedTy)
                    return true
                }
            } else if (typeManager.CheckTypeCompatibility(targetTy, elementTy) == TypeCompatibility.INCOMPATIBLE) {
                let _ = SubscriptInvalid(se)
                return false
            }
        }
        se.isTupleAccess = true
        se.SetTy(elementTy)
        return true
    }
    let _ = SubscriptInvalid(se)
    return false
}

private func ChkVArrayAccess(typeManager: TypeManager, target: Option<Ty>, se: SubscriptExpr, varrayTy: VArrayTy): Bool {
    if (se.indexExprs.size != 1) {
        let _ = SubscriptInvalid(se)
        return false
    }
    if (!CheckIndexAsInt64(typeManager, se.indexExprs[0])) {
        let _ = SubscriptInvalid(se)
        return false
    }
    if (varrayTy.typeArgs.size != 1) {
        let _ = SubscriptInvalid(se)
        return false
    }
    let elementTy = varrayTy.typeArgs[0]
    if (let Some(targetTy) <- target) {
        if (typeManager.CheckTypeCompatibility(targetTy, elementTy) == TypeCompatibility.INCOMPATIBLE) {
            let _ = SubscriptInvalid(se)
            return false
        }
    }
    se.SetTy(elementTy)
    return true
}

private func SynIndexExprs(typeManager: TypeManager, se: SubscriptExpr): Bool {
    var ok = true
    for (indexExpr in se.indexExprs) {
        if (Ty.IsTyCorrect(indexExpr.GetTy())) {
            continue
        }
        ok = Ty.IsTyCorrect(SynExprShallow(typeManager, indexExpr)) && ok
    }
    return ok
}

private func ChkSubscriptOverload(typeManager: TypeManager, target: Option<Ty>, se: SubscriptExpr): Bool {
    DesugarOperatorOverloadExpr(se)
    if (let Some(desugar) <- se.desugarExpr) {
        let ok = if (let Some(targetTy) <- target) {
            ChkExprShallow(typeManager, targetTy, desugar)
        } else {
            Ty.IsTyCorrect(SynExprShallow(typeManager, desugar))
        }
        if (ok) {
            PropagateSubscriptDesugarTarget(se, desugar)
            se.SetTy(TcTyOrInvalid(desugar))
            return true
        }
        RecoverToSubscriptExpr(se)
    }
    let _ = SubscriptInvalid(se)
    return false
}

public func ChkSubscriptExpr(typeManager: TypeManager, target: Ty, se: SubscriptExpr,
    ctx!: Option<ASTContext> = None): Bool {
    if (let Some(desugar) <- se.desugarExpr) {
        if (ChkExprShallow(typeManager, target, desugar, ctx: ctx)) {
            PropagateSubscriptDesugarTarget(se, desugar)
            se.SetTy(TcTyOrInvalid(desugar))
            return true
        }
    }
    if (let None <- se.baseExpr) {
        let _ = SubscriptInvalid(se)
        return false
    }
    if (se.indexExprs.isEmpty()) {
        let _ = SubscriptInvalid(se)
        return false
    }
    let baseExpr = se.baseExpr.getOrThrow()
    SetIsNotAlone(baseExpr)
    let baseTy = SynExprShallow(typeManager, baseExpr, ctx: ctx)
    if (!Ty.IsTyCorrect(baseTy) || !SynIndexExprs(typeManager, se)) {
        let _ = SubscriptInvalid(se)
        return false
    }
    if (let Some(tupleTy) <- (baseTy as TupleTy)) {
        return ChkTupleAccess(typeManager, Some(target), se, tupleTy)
    }
    if (let Some(varrayTy) <- (baseTy as VArrayTy)) {
        return ChkVArrayAccess(typeManager, Some(target), se, varrayTy)
    }
    return ChkSubscriptOverload(typeManager, Some(target), se)
}

public func SynSubscriptExpr(typeManager: TypeManager, se: SubscriptExpr, ctx!: Option<ASTContext> = None): Ty {
    if (let Some(desugar) <- se.desugarExpr) {
        let desugarTy = SynExprShallow(typeManager, desugar, ctx: ctx)
        if (Ty.IsTyCorrect(desugarTy)) {
            PropagateSubscriptDesugarTarget(se, desugar)
            se.SetTy(desugarTy)
            return desugarTy
        }
    }
    if (let None <- se.baseExpr) {
        return SubscriptInvalid(se)
    }
    if (se.indexExprs.isEmpty()) {
        return SubscriptInvalid(se)
    }
    let baseExpr = se.baseExpr.getOrThrow()
    SetIsNotAlone(baseExpr)
    let baseTy = SynExprShallow(typeManager, baseExpr, ctx: ctx)
    if (!Ty.IsTyCorrect(baseTy) || !SynIndexExprs(typeManager, se)) {
        return SubscriptInvalid(se)
    }
    if (let Some(tupleTy) <- (baseTy as TupleTy)) {
        if (ChkTupleAccess(typeManager, None, se, tupleTy)) {
            return TcTyOrInvalid(se)
        }
        return SubscriptInvalid(se)
    }
    if (let Some(varrayTy) <- (baseTy as VArrayTy)) {
        if (ChkVArrayAccess(typeManager, None, se, varrayTy)) {
            return TcTyOrInvalid(se)
        }
        return SubscriptInvalid(se)
    }
    if (ChkSubscriptOverload(typeManager, None, se)) {
        return TcTyOrInvalid(se)
    }
    return SubscriptInvalid(se)
}
