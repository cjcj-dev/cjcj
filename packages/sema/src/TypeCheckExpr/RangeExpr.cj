package cjcj::sema.TypeCheckExpr

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::sema.*

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

private func BindRangeDecl(re: RangeExpr, rangeDecl: Option<StructDecl>): Bool {
    if (let Some(decl) <- rangeDecl) {
        re.decl = Some(decl)
    }
    return re.decl.isSome()
}

private func CheckRangeGenericInstantiation(typeManager: TypeManager, re: RangeExpr, elemTy: Ty,
    checkGenericDeclInstantiation!: Option<(Option<Decl>, ArrayList<Ty>, Node) -> Bool> = None): Bool {
    if (let Some(rangeDecl) <- re.decl) {
        let typeArgs = ArrayList<Ty>()
        typeArgs.add(elemTy)
        if (let Some(checker) <- checkGenericDeclInstantiation) {
            let declOpt: Option<Decl> = rangeDecl
            return checker(declOpt, typeArgs, re)
        }
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

public func CheckRangeElements(typeManager: TypeManager, elemTy: Ty, re: RangeExpr,
    ctx!: Option<ASTContext> = None, checker!: Option<(Ty, Expr) -> Bool> = None,
    checkGenericDeclInstantiation!: Option<(Option<Decl>, ArrayList<Ty>, Node) -> Bool> = None,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    var isWellTyped = true
    if (let Some(start) <- re.startExpr) {
        isWellTyped = if (let Some(check) <- checker) { check(elemTy, start) } else {
            ChkExprShallow(typeManager, elemTy, start, ctx: ctx, diag: diag)
        }
    }
    if (let Some(stop) <- re.stopExpr) {
        let stopWellTyped = if (let Some(check) <- checker) { check(elemTy, stop) } else {
            ChkExprShallow(typeManager, elemTy, stop, ctx: ctx, diag: diag)
        }
        isWellTyped = stopWellTyped && isWellTyped
    }
    if (let Some(realCtx) <- ctx) {
        let inconsistent = !realCtx.HasTargetTy(re) && re.startExpr.isSome() && re.stopExpr.isSome() && !isWellTyped
        if (inconsistent) {
            if (!CanSkipDiag(re.startExpr.getOrThrow()) && !CanSkipDiag(re.stopExpr.getOrThrow())) {
                if (let Some(diagValue) <- diag) {
                    let builder = diagValue.Diagnose(re.begin, re.end, BasicDiagKind.sema_inconsistency_range_elemType)
                    builder.Emit()
                }
            }
        }
    }
    if (isWellTyped && !CheckRangeGenericInstantiation(typeManager, re, elemTy,
        checkGenericDeclInstantiation: checkGenericDeclInstantiation)) {
        isWellTyped = false
    }
    if (let Some(stepExpr) <- re.stepExpr) {
        let int64Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
        let stepWellTyped = if (let Some(check) <- checker) { check(int64Ty, stepExpr) } else {
            ChkExprShallow(typeManager, int64Ty, stepExpr, ctx: ctx, diag: diag)
        }
        if (!stepWellTyped) {
            if (!CanSkipDiag(stepExpr)) {
                if (let Some(diagValue2) <- diag) {
                    let builder2 = diagValue2.Diagnose(re.begin, re.end, BasicDiagKind.sema_range_step_not_int64)
                    builder2.Emit()
                }
            }
            isWellTyped = false
        } else if (stepExpr.isConst) {
            if (stepExpr.constNumValue.asInt.Uint64() == 0u64) {
                if (let Some(diagValue3) <- diag) {
                    let builder3 = diagValue3.Diagnose(stepExpr.begin, stepExpr.end,
                        BasicDiagKind.sema_step_non_zero_range)
                    builder3.Emit()
                }
            }
        }
    }
    return isWellTyped
}

public func SynRangeExpr(typeManager: TypeManager, re: RangeExpr, rangeDecl!: Option<StructDecl> = None,
    ctx!: Option<ASTContext> = None, checker!: Option<(Ty, Expr) -> Bool> = None,
    checkGenericDeclInstantiation!: Option<(Option<Decl>, ArrayList<Ty>, Node) -> Bool> = None,
    diag!: Option<BasicDiagnosticEngine> = None): Ty {
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
    if (!CheckRangeElements(typeManager, elemTy, re, ctx: ctx, checker: checker,
        checkGenericDeclInstantiation: checkGenericDeclInstantiation, diag: diag)) {
        return invalidTy
    }
    let rangeTy = typeManager.GetStructTy(resolvedRangeDecl, [elemTy])
    re.SetTy(rangeTy)
    return rangeTy
}

public func ChkRangeExpr(typeManager: TypeManager, target: Ty, re: RangeExpr,
    rangeDecl!: Option<StructDecl> = None, ctx!: Option<ASTContext> = None,
    checker!: Option<(Ty, Expr) -> Bool> = None,
    checkGenericDeclInstantiation!: Option<(Option<Decl>, ArrayList<Ty>, Node) -> Bool> = None,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    re.SetTy(TypeManager.GetInvalidTy())
    if (!BindRangeDecl(re, rangeDecl)) {
        if (let Some(diagValue) <- diag) {
            let builder = diagValue.Diagnose(re.begin, re.end, BasicDiagKind.sema_no_core_object)
            builder.Emit()
        }
        return false
    }
    if (!Ty.IsTyCorrect(target)) {
        return false
    }
    let synAndCheckRangeTy = { =>
        re.SetTy(SynRangeExpr(typeManager, re, ctx: ctx, checker: checker,
            checkGenericDeclInstantiation: checkGenericDeclInstantiation, diag: diag))
        let synTy = re.GetTy() ?? TypeManager.GetInvalidTy()
        let synWellTyped = typeManager.IsSubtype(synTy, target)
        if (!synWellTyped && Ty.IsTyCorrect(synTy)) {
            if (let Some(diagValue2) <- diag) {
                DiagMismatchedTypes(diagValue2, re, target)
            }
        }
        synWellTyped
    }
    let targetTy = UnboxOptionType(target)
    if (!Ty.IsTyCorrect(targetTy) || (!targetTy.IsStruct() && !targetTy.IsInterface())) {
        let _ = synAndCheckRangeTy()
        re.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    var rangeTy = targetTy
    if (targetTy.IsInterface()) {
        let rangeDeclTy = re.decl.getOrThrow().GetTy() ?? TypeManager.GetInvalidTy()
        let candiTys = Promotion(typeManager).Downgrade(rangeDeclTy, target)
        if (candiTys.IsEmpty()) {
            if (synAndCheckRangeTy()) {
                return true
            }
            if (let Some(diagValue3) <- diag) {
                DiagUnableToInferExpr(diagValue3, re)
            }
            return false
        }
        rangeTy = candiTys.values[0]
    } else if (!targetTy.IsRange() || rangeTy.typeArgs.size != 1) {
        return synAndCheckRangeTy()
    }
    if (!CheckRangeElements(typeManager, rangeTy.typeArgs[0], re, ctx: ctx, checker: checker,
        checkGenericDeclInstantiation: checkGenericDeclInstantiation, diag: diag)) {
        return false
    }
    re.SetTy(rangeTy)
    let isWellTyped = typeManager.IsSubtype(re.GetTy() ?? TypeManager.GetInvalidTy(), target)
    if (!isWellTyped) {
        if (let Some(diagValue4) <- diag) {
            DiagMismatchedTypes(diagValue4, re, target)
        }
    }
    return isWellTyped
}

extend TypeChecker {
}
