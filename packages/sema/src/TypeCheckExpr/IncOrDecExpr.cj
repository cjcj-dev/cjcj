package cangjie_compiler::sema.TypeCheckExpr

import cangjie_compiler::ast.*
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::sema.*

public func SynIncOrDecExpr(ide: IncOrDecExpr, leftSynthesizer: (Expr) -> Ty,
    desugarSynthesizer: (Expr) -> Ty, diag!: Option<BasicDiagnosticEngine> = None): Ty {
    if (let None <- ide.desugarExpr) {
        return TypeManager.GetInvalidTy()
    }
    let desugar = ide.desugarExpr.getOrThrow()
    let assignExpr = (desugar as AssignExpr).getOrThrow()
    let leftValue = assignExpr.leftValue.getOrThrow()
    let leftTy = leftSynthesizer(leftValue)
    if (!Ty.IsTyCorrect(leftTy)) {
        ide.SetTy(TypeManager.GetInvalidTy())
    } else if (!leftTy.IsInteger()) {
        if (let Some(diagValue) <- diag) {
            DiagMismatchedTypesWithFoundTy(diagValue, leftValue, "integer type", leftTy.String(),
                note: "the base of increment or decrement expressions should be of integer type")
        }
        ide.SetTy(TypeManager.GetInvalidTy())
    } else {
        if (leftValue.astKind == ASTKind.SUBSCRIPT_EXPR && (let Some(_) <- leftValue.desugarExpr)) {
            RecoverToSubscriptExpr((leftValue as SubscriptExpr).getOrThrow())
        }
        ide.SetTy(desugarSynthesizer(desugar))
    }
    return ide.GetTy() ?? TypeManager.GetInvalidTy()
}

public func ChkIncOrDecExpr(typeManager: TypeManager, target: Ty, ide: IncOrDecExpr,
    leftSynthesizer: (Expr) -> Ty, desugarSynthesizer: (Expr) -> Ty,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    let actualTy = SynIncOrDecExpr(ide, leftSynthesizer, desugarSynthesizer, diag: diag)
    if (!Ty.IsTyCorrect(actualTy)) {
        return false
    }
    if (typeManager.IsSubtype(actualTy, target)) {
        return true
    }
    if (let Some(diagValue) <- diag) {
        DiagMismatchedTypesWithFoundTy(diagValue, ide, target, actualTy,
            note: "the type of an assignment expression is always 'Unit'")
    }
    ide.SetTy(TypeManager.GetInvalidTy())
    return false
}
