package cjcj::sema.TypeCheckExpr

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.MakeRange as BasicMakeRange
import cjcj::sema.*

private func invalidTupleLit(tl: TupleLit): Ty {
    let invalidTy = TypeManager.GetInvalidTy()
    tl.SetTy(invalidTy)
    return invalidTy
}

private func unboxOptionType(ty: Ty): Ty {
    var currentTy = ty
    while (!currentTy.HasInvalidTy() && currentTy.IsCoreOptionType()) {
        if (currentTy.typeArgs.size != 1) {
            return TypeManager.GetInvalidTy()
        }
        currentTy = currentTy.typeArgs[0]
    }
    return currentTy
}

private func replaceIdealChildTy(typeManager: TypeManager, expr: Expr): Option<Ty> {
    if (let Some(exprTy) <- expr.GetTy()) {
        if (exprTy.HasInvalidTy()) {
            return None
        }
        if (exprTy.IsIdeal()) {
            let concreteTy = typeManager.ReplaceIdealTy(exprTy)
            expr.SetTy(concreteTy)
            return concreteTy
        }
        return exprTy
    }
    return None
}

private func diagMismatchedTypesWithFoundTy(
    diag: Option<BasicDiagnosticEngine>,
    node: Node,
    expected: String,
    found: String
): Unit {
    if (!node.ShouldDiagnose(allowCompilerAdd: true)) {
        return
    }
    if (let Some(diagValue) <- diag) {
        let builder = DiagnoseRefactor(diagValue,
            BasicDiagKindRefactor.sema_mismatched_types,
            node)
        builder.AddMainHintArguments([expected, found])
        builder.Emit()
    }
}

private func diagMismatchedTypes(
    diag: Option<BasicDiagnosticEngine>,
    node: Node,
    target: Ty
): Unit {
    if (!Ty.IsTyCorrect(node.GetTy()) || !Ty.IsTyCorrect(target)) {
        return
    }
    diagMismatchedTypesWithFoundTy(diag, node, target.String(), (node.GetTy() ?? TypeManager.GetInvalidTy()).String())
}

public func SynTupleLit(typeManager: TypeManager, tl: TupleLit): Ty {
    let elementTys = ArrayList<Ty>()
    for (child in tl.children) {
        if (let Some(elementTy) <- replaceIdealChildTy(typeManager, child)) {
            elementTys.add(elementTy)
        } else {
            return invalidTupleLit(tl)
        }
    }
    let tupleTy = typeManager.GetTupleTy(elementTys.toArray())
    tl.SetTy(tupleTy)
    return tupleTy
}

public func ChkTupleLit(typeManager: TypeManager, target: Ty, tl: TupleLit, synthesizer: (TupleLit) -> Ty,
    check!: Option<(Ty, Expr) -> Bool> = None, diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (target.IsAny()) {
        tl.SetTy(synthesizer(tl))
        let _ = ReplaceIdealTy(typeManager, tl, diag: diag)
        return Ty.IsTyCorrect(tl.GetTy())
    }

    let targetTy = unboxOptionType(target)
    if (targetTy.HasInvalidTy() || !targetTy.IsTuple()) {
        diagMismatchedTypesWithFoundTy(diag, tl, targetTy.String(), "Tuple")
        tl.SetTy(TypeManager.GetNonNullTy(tl.GetTy() ?? TypeManager.GetInvalidTy()))
        return false
    }
    if (let Some(targetTuple) <- (targetTy as TupleTy)) {
        if (targetTuple.typeArgs.size != tl.children.size) {
            let _ = SynTupleLit(typeManager, tl)
            diagMismatchedTypes(diag, tl, targetTy)
            return false
        }
        for (idx in 0..targetTuple.typeArgs.size) {
            let child = tl.children[idx]
            if (let Some(checkFunc) <- check) {
                if (!checkFunc(targetTuple.typeArgs[idx], child)) {
                    diagMismatchedTypes(diag, child, targetTuple.typeArgs[idx])
                    let _ = SynTupleLit(typeManager, tl)
                    return false
                }
                continue
            }
            if (let Some(childTy) <- replaceIdealChildTy(typeManager, child)) {
                if (childTy.HasInvalidTy() ||
                    typeManager.CheckTypeCompatibility(targetTuple.typeArgs[idx], childTy) ==
                    TypeCompatibility.INCOMPATIBLE) {
                    let _ = SynTupleLit(typeManager, tl)
                    return false
                }
            } else {
                let _ = invalidTupleLit(tl)
                return false
            }
        }
        tl.SetTy(targetTy)
        return true
    }
    let _ = invalidTupleLit(tl)
    return false
}

extend TypeChecker {
}
