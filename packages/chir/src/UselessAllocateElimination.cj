package cangjie_compiler::chir

public class UselessAllocateElimination {
    public init() {}

    public static func RunOnPackage(pkg: Package, isDebug!: Bool = false): Int64 {
        var changed: Int64 = 0
        for (fn in pkg.GetGlobalFuncsWithBody()) {
            changed += UselessAllocateElimination().RunOnFunction(fn, isDebug: isDebug)
        }
        return changed
    }

    public func RunOnFunction(fn: Function, isDebug!: Bool = false): Int64 {
        if (let Some(body) <- fn.GetBody()) {
            return RunOnBody(body, fn, isDebug)
        }
        return 0
    }

    private func RunOnBody(body: BlockGroup, fn: Function, isDebug: Bool): Int64 {
        var changed: Int64 = 0
        for (block in body.GetBlocksRef()) {
            let exprs = block.GetExpressions()
            for (expr in exprs) {
                if (expr.GetExprKind() == ExprKind.ALLOCATE && TryRemoveAllocate(expr, fn, isDebug)) {
                    changed++
                }
            }
        }
        return changed
    }

    private func TryRemoveAllocate(expr: Expression, fn: Function, isDebug: Bool): Bool {
        if (AllocatedClassHasFinalizer(expr)) {
            return false
        }
        if (let Some(result) <- expr.GetResult()) {
            if (IsFunctionReturnValue(result, fn)) {
                return false
            }
            let users = result.GetUsers()
            for (user in users) {
                if (!IsOnlyWriteOrDebugUser(user, result)) {
                    return false
                }
            }
            expr.RemoveSelfFromBlock()
            for (user in users) {
                user.RemoveSelfFromBlock()
            }
            if (isDebug && expr.GetDebugLocation().IsValid()) {
                println("[UselessAllocateElimination] removed Allocate " + expr.GetDebugLocation().ToString() + ".")
            }
            return true
        }
        return false
    }

    private func AllocatedClassHasFinalizer(expr: Expression): Bool {
        if (let Some(result) <- expr.GetResult()) {
            if (let Some(resultTy) <- result.GetType()) {
                return ClassTypeHasFinalizer(StripAllocatedRef(resultTy))
            }
        }
        return false
    }

    private func StripAllocatedRef(ty: Type): Type {
        if (let Some(refTy) <- (ty as RefType)) {
            return refTy.GetBaseType()
        }
        return ty
    }

    private func ClassTypeHasFinalizer(ty: Type): Bool {
        if (let Some(classTy) <- (ty as ClassType)) {
            if (let Some(classDef) <- (classTy.GetCustomTypeDef() as ClassDef)) {
                for (method in classDef.GetMethods()) {
                    if (method.IsFinalizer()) {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func IsFunctionReturnValue(value: LocalVar, fn: Function): Bool {
        if (let Some(retValue) <- fn.GetReturnValue()) {
            return retValue.nodeId == value.nodeId
        }
        return false
    }

    private func IsOnlyWriteOrDebugUser(user: Expression, allocated: LocalVar): Bool {
        let kind = user.GetExprKind()
        if (kind == ExprKind.DEBUGEXPR) {
            return true
        }
        if (kind == ExprKind.STORE && user.GetNumOfOperands() >= 2) {
            return user.GetOperand(1).nodeId == allocated.nodeId
        }
        if (kind == ExprKind.STORE_ELEMENT_REF && user.GetNumOfOperands() >= 2) {
            return user.GetOperand(1).nodeId == allocated.nodeId
        }
        return false
    }
}
