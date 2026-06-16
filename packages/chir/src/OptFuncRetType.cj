package cangjie_compiler::chir

import std.collection.*

public class OptFuncRetType {
    private let chirPackage: Package
    private let builder: CHIRBuilder

    public init(chirPackage: Package, builder: CHIRBuilder) {
        this.chirPackage = chirPackage
        this.builder = builder
    }

    public func Unit2Void(): Int64 {
        var changed: Int64 = 0
        for (fn in chirPackage.GetGlobalFunctions(includePureAbstract: true)) {
            if (!ReturnTypeShouldBeVoid(fn)) {
                continue
            }
            if (let Some(returnTy) <- fn.GetReturnType()) {
                if (!returnTy.IsUnit()) {
                    continue
                }
            } else {
                continue
            }
            let oldRet: Option<LocalVar> = if (fn.IsFuncWithBody()) { fn.GetReturnValue() } else { None }
            fn.ReplaceReturnValue(None, builder)
            changed++
            if (let Some(retValue) <- oldRet) {
                RemoveOldRetValue(retValue)
            }
            changed += UpdateCallSites(fn)
        }
        return changed
    }

    private func UpdateCallSites(fn: Function): Int64 {
        var changed: Int64 = 0
        let users = fn.GetUsers()
        for (user in users) {
            let kind = user.GetExprKind()
            if ((kind == ExprKind.APPLY || kind == ExprKind.APPLY_WITH_EXCEPTION) &&
                user.GetNumOfOperands() > 0 && user.GetOperand(0).nodeId == fn.nodeId) {
                if (RewriteCallSite(user)) {
                    changed++
                }
            }
        }
        return changed
    }

    private func RewriteCallSite(callExpr: Expression): Bool {
        if (let Some(result) <- callExpr.GetResult()) {
            if (!result.GetUsersRef().isEmpty()) {
                result.SetType(builder.context.GetVoidTy())
                return true
            }
        }
        if (let Some(parentBlock) <- callExpr.GetParentBlock()) {
            let operands = callExpr.GetOperands()
            let newExpr = builder.CreateExpression(callExpr.GetExprKind(), None, operands, parentBlock)
            newExpr.SetDebugLocation(callExpr.GetDebugLocation())
            callExpr.ReplaceWith(newExpr)
            return true
        }
        return false
    }
}

private func RemoveOldRetValue(oldRet: LocalVar): Unit {
    let users = oldRet.GetUsers()
    for (user in users) {
        if (user.GetExprKind() != ExprKind.STORE) {
            return
        }
    }
    for (user in users) {
        if (user.GetNumOfOperands() >= 1) {
            let storedValue = user.GetOperand(0)
            if (let Some(unitLocal) <- storedValue.AsLocalVar()) {
                if (let Some(unitExpr) <- unitLocal.GetExpr()) {
                    if (unitExpr.IsConstant()) {
                        unitExpr.RemoveSelfFromBlock()
                    }
                }
            }
        }
        user.RemoveSelfFromBlock()
    }
    if (let Some(oldRetExpr) <- oldRet.GetExpr()) {
        oldRetExpr.RemoveSelfFromBlock()
    }
}
