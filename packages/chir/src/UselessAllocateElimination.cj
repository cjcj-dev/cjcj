package cangjie_compiler::chir

import cangjie_compiler::utils.StaticCast

public class UselessAllocateElimination {
    public init() {}

    public static func RunOnPackage(pkg: Package, isDebug!: Bool = false): Unit {
        for (fn in pkg.GetGlobalFuncsWithBody()) {
            RunOnFunc(fn, isDebug)
        }
    }

    private static func RunOnFunc(fn: Function, isDebug: Bool): Unit {
        let body = fn.GetBody().getOrThrow()
        for (block in body.GetBlocks()) {
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
