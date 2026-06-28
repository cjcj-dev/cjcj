package cangjie_compiler::chir

import cangjie_compiler::utils.{CJC_ASSERT, DynamicCast, StaticCast}

public class OptFuncRetType {
    private let chirPackage: Package
    private let builder: CHIRBuilder

    public init(chirPackage: Package, builder: CHIRBuilder) {
        this.chirPackage = chirPackage
        this.builder = builder
    }

    public func Unit2Void(): Unit {
        for (fn in chirPackage.GetGlobalFunctions()) {
            if (!ReturnTypeShouldBeVoid(fn)) {
                continue
            }
            CJC_ASSERT(fn.GetReturnType().getOrThrow().IsUnit())
            var oldRet: Option<LocalVar> = None
            if (fn.IsFuncWithBody()) {
                oldRet = fn.GetReturnValue()
                CJC_ASSERT(oldRet.isSome())
            }
            fn.ReplaceReturnValue(None, builder)
            if (let Some(retValue) <- oldRet) {
                RemoveOldRetValue(retValue)
            }
            for (user in fn.GetUsers()) {
                if (let Some(apply) <- DynamicCast<Apply>(user)) {
                    CJC_ASSERT(apply.GetCallee().nodeId == fn.nodeId)
                    let funcCallContext = FuncCallContext(args: apply.GetArgs(),
                        instTypeArgs: apply.GetInstantiatedTypeArgs(), thisType: apply.GetThisType())
                    let newApply = builder.CreateApply(fn.GetReturnType().getOrThrow(), apply.GetCallee(),
                        funcCallContext, apply.GetParentBlock().getOrThrow())
                    newApply.SetDebugLocation(apply.GetDebugLocation())
                    if (apply.IsSuperCall()) {
                        newApply.SetSuperCall()
                    }
                    apply.ReplaceWith(newApply)
                } else {
                    let awe = StaticCast<ApplyWithException>(user)
                    CJC_ASSERT(awe.GetCallee().nodeId == fn.nodeId)
                    let funcCallContext = FuncCallContext(args: awe.GetArgs(),
                        instTypeArgs: awe.GetInstantiatedTypeArgs(), thisType: awe.GetThisType())
                    let newApply = builder.CreateApplyWithException(fn.GetReturnType().getOrThrow(), awe.GetCallee(),
                        funcCallContext, awe.GetSuccessBlock(), awe.GetErrorBlock(), awe.GetParentBlock().getOrThrow())
                    newApply.SetDebugLocation(awe.GetDebugLocation())
                    awe.ReplaceWith(newApply)
                }
            }
        }
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
        let store = StaticCast<Store>(user)
        if (let Some(unitVal) <- DynamicCast<LocalVar>(store.GetValue())) {
            let unitExpr = unitVal.GetExpr().getOrThrow()
            if (unitExpr.IsConstant()) {
                unitExpr.RemoveSelfFromBlock()
            }
        }
        store.RemoveSelfFromBlock()
    }
    oldRet.GetExpr().getOrThrow().RemoveSelfFromBlock()
}
