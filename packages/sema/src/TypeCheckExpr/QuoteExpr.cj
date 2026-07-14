package cjcj::sema.TypeCheckExpr

import cjcj::ast.*
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::modules.SemaImportManager
import cjcj::sema.*
import cjcj::utils.AST_PACKAGE_NAME

private func ChkIfImportLibAST(diag: BasicDiagnosticEngine, importManager: SemaImportManager, qe: QuoteExpr): Unit {
    if (qe.GetFullPackageName() == AST_PACKAGE_NAME) {
        return
    }
    for (importedPkg in importManager.GetAllImportedPackages(false)) {
        if (importedPkg.srcPackage.fullPackageName == AST_PACKAGE_NAME) {
            return
        }
    }
    DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_use_expr_without_import, qe,
        arguments: ["std.ast", "quote"]).Emit()
}

extend TypeChecker {
    func ChkQuoteExpr(ctx: ASTContext, target: Ty, qe: QuoteExpr): Bool {
        ChkIfImportLibAST(impl.diag.getOrThrow(), impl.importManager.getOrThrow(), qe)
        if (!Ty.IsTyCorrect(Synthesize(ctx, qe))) {
            return false
        }
        if (!impl.typeManager.IsSubtype(qe.GetTy().getOrThrow(), target)) {
            if (let Some(diag) <- impl.diag) {
                DiagMismatchedTypes(diag, qe, target)
            }
            qe.SetTy(TypeManager.GetInvalidTy())
            return false
        }
        if (let Some(desugar) <- qe.desugarExpr) {
            if (!Check(ctx, target, desugar)) {
                qe.SetTy(TypeManager.GetInvalidTy())
                return false
            }
        }
        return true
    }

    func SynQuoteExpr(ctx: ASTContext, qe: QuoteExpr): Ty {
        ChkIfImportLibAST(impl.diag.getOrThrow(), impl.importManager.getOrThrow(), qe)
        if (let Some(desugar) <- qe.desugarExpr) {
            qe.SetTy(Synthesize(ctx, SynPos.NONE, desugar))
        } else {
            qe.SetTy(TypeManager.GetInvalidTy())
        }
        return qe.GetTy().getOrThrow()
    }
}
