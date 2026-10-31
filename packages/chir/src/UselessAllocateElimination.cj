package cjcj::chir

import cjcj::utils.StaticCast

public class UselessAllocateElimination {
    public init() {}

    public static func RunOnPackage(pkg: Package, isDebug!: Bool = false, threadNum!: Int64 = 1): Unit {
        if (threadNum <= 1 || isDebug) {
            for (fn in pkg.GetGlobalFuncsWithBody()) { RunOnFunc(fn, isDebug) }
            return
        }
        // No builder or cross-function analysis: each task removes only its own unused allocation
        // and stores. Shared global operands only lose users under Value's existing lock.
        let _ = RunFunctionLocalPass<Unit>(pkg.GetGlobalFuncsWithBody(), threadNum,
            { fn => RunOnFunc(fn, false) })
    }

    private static func RunOnFunc(fn: Function, isDebug: Bool): Unit {
        for (block in fn.GetBody().getOrThrow().GetBlocks()) {
            let exprs = block.GetExpressions()
            for (expr in exprs) {
                if (expr.GetExprKind() != ExprKind.ALLOCATE) {
                    continue
                }
                let allocate = StaticCast<Allocate>(expr)
                let allocatedTy = allocate.GetType()
                if (allocatedTy.IsClass() &&
                    StaticCast<ClassType>(allocatedTy).GetClassDef().GetFinalizer().isSome()) {
                    continue
                }
                let result = allocate.GetResult().getOrThrow()
                if (let Some(retValue) <- fn.GetReturnValue()) {
                    if (refEq(retValue, result)) {
                        continue
                    }
                }
                let users = result.GetUsers()
                var onlyBeenWritten = true
                for (user in users) {
                    if (user.GetExprKind() == ExprKind.STORE &&
                        StaticCast<Store>(user).GetLocation().nodeId == result.nodeId) {
                        continue
                    }
                    if (user.GetExprKind() == ExprKind.STORE_ELEMENT_REF &&
                        StaticCast<StoreElementRef>(user).GetLocation().nodeId == result.nodeId) {
                        continue
                    }
                    if (user.GetExprKind() == ExprKind.DEBUGEXPR) {
                        continue
                    }
                    onlyBeenWritten = false
                    break
                }
                if (onlyBeenWritten) {
                    allocate.RemoveSelfFromBlock()
                    for (user in users) {
                        user.RemoveSelfFromBlock()
                    }
                    if (isDebug && !allocate.GetDebugLocation().GetBeginPos().IsZero()) {
                        println("[UselessAllocateElimination] Allocate" +
                            ToPosInfo(allocate.GetDebugLocation()) + " and its users have been deleted")
                    }
                }
            }
        }
    }
}
