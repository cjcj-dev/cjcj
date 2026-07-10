package cjcj::sema.TypeCheckExpr

import cjcj::ast.*
import cjcj::sema.*

private let COMMAND_TYPE_NAME: String = "Command"

private func invalidPerformExpr(pe: PerformExpr): Ty {
    let invalidTy = TypeManager.GetInvalidTy()
    pe.SetTy(invalidTy)
    return invalidTy
}

private func commandPayloadTy(ty: Ty): Option<Ty> {
    if (ty.name == COMMAND_TYPE_NAME && ty.typeArgs.size == 1) {
        return ty.typeArgs[0]
    }
    return None
}

private func promoteToCommandTy(typeManager: TypeManager, exprTy: Ty, commandTy: Option<Ty>): Option<Ty> {
    if (exprTy.HasInvalidTy()) {
        return None
    }
    if (let Some(_) <- commandPayloadTy(exprTy)) {
        return exprTy
    }
    if (let Some(coreCommandTy) <- commandTy) {
        if (typeManager.IsSubtype(exprTy, coreCommandTy) && coreCommandTy.typeArgs.size == 1) {
            return coreCommandTy
        }
    }
    return None
}

public func SynPerformExpr(typeManager: TypeManager, pe: PerformExpr, commandTy!: Option<Ty> = None): Ty {
    if (let Some(innerExpr) <- pe.expr) {
        if (let Some(exprTy) <- innerExpr.GetTy()) {
            if (let Some(commandExprTy) <- promoteToCommandTy(typeManager, exprTy, commandTy)) {
                if (let Some(payloadTy) <- commandPayloadTy(commandExprTy)) {
                    pe.SetTy(payloadTy)
                    return payloadTy
                }
            }
        }
    }
    return invalidPerformExpr(pe)
}
