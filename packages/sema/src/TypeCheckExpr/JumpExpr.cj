package cangjie_compiler::sema.TypeCheckExpr

import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

public func SynLoopControlExpr(ctx: ASTContext, je: JumpExpr): Ty {
    if (let Some(symbol) <- GetRefLoopSymbol(ctx, je)) {
        if (let Some(loopExpr) <- (symbol.node.getOrThrow() as Expr)) {
            je.refLoop = Some(loopExpr)
        }
    }
    return SynLoopControlExpr(je)
}

public func SynLoopControlExpr(je: JumpExpr): Ty {
    if (let Some(_) <- je.refLoop) {
        let nothingTy = TypeManager.GetNothingTy()
        je.SetTy(nothingTy)
        return nothingTy
    }
    let invalidTy = TypeManager.GetInvalidTy()
    je.SetTy(invalidTy)
    return invalidTy
}

public func ChkLoopControlExpr(ctx: ASTContext, je: JumpExpr): Bool {
    let ty = SynLoopControlExpr(ctx, je)
    return !ty.HasInvalidTy()
}

public func ChkLoopControlExpr(je: JumpExpr): Bool {
    let ty = SynLoopControlExpr(je)
    return !ty.HasInvalidTy()
}
