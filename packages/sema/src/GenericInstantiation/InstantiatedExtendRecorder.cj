package cangjie_compiler::sema.GenericInstantiation

import cangjie_compiler::ast.*
import cangjie_compiler::sema.*
import cangjie_compiler::utils.InternalError

public class InstantiatedExtendRecorder {
    private var typeManager: TypeManager
    private var promotion: Promotion

    public init(typeManager: TypeManager) {
        this.typeManager = typeManager
        promotion = Promotion(typeManager)
    }

    public func Record(node: Node): Unit {
        if (let Some(pkg) <- (node as Package)) {
            for (file in pkg.files) {
                Record(file)
            }
            for (decl in pkg.srcImportedNonGenericDecls) {
                Record(decl)
            }
            return
        }
        let walker = Walker(node, visitPre: { current: Node =>
            RecordUsedExtendDecl(current)
        })
        let _ = walker.Walk()
    }

    private func RecordUsedExtendDecl(node: Node): VisitAction {
        if (let Some(expr) <- (node as Expr)) {
            if (let Some(desugarExpr) <- expr.desugarExpr) {
                Record(desugarExpr)
                return VisitAction.SKIP_CHILDREN
            }
        }
        if (let Some(memberAccess) <- (node as MemberAccess)) {
            RecordExtendForMemberAccess(memberAccess)
        }
        return VisitAction.WALK_CHILDREN
    }

    private func RecordExtendForMemberAccess(memberAccess: MemberAccess): Unit {
        let target = if (let Some(value) <- memberAccess.GetTarget()) {
            value
        } else {
            return
        }
        let baseExpr = if (let Some(value) <- memberAccess.baseExpr) {
            value
        } else {
            return
        }
        let baseTy = if (let Some(value) <- baseExpr.GetTy()) {
            value
        } else {
            return
        }
        if (!Ty.IsTyCorrect(baseTy) || baseTy.HasGeneric()) {
            return
        }
        let outerDecl = if (let Some(value) <- target.outerDecl) {
            value
        } else {
            return
        }
        if (outerDecl.astKind == ASTKind.EXTEND_DECL) {
            let promoteRes = promotion.Promote(baseTy, outerDecl.GetTy().getOrThrow())
            if (promoteRes.IsEmpty()) {
                InternalError("generic instantiation failed")
                return
            }
            typeManager.RecordUsedGenericExtend(promoteRes.values[0], extendDecl: (outerDecl as ExtendDecl))
        }
    }
}
