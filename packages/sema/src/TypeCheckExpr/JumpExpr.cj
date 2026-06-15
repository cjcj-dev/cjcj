package cangjie_compiler::sema.TypeCheckExpr

import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

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

public func ChkLoopControlExpr(je: JumpExpr): Bool {
    let ty = SynLoopControlExpr(je)
    return !ty.HasInvalidTy()
}
