package cjcj::chir

import cjcj::utils.{CJC_NULLPTR_CHECK, TaskQueue, TaskResult}
import std.collection.*

// Runs a function-local pass over funcs. A task may only write the body it was given and global-user
// lists (AddUserOnly/RemoveUserOnly lock those); all results are drained before the first failure is rethrown.
func RunFunctionLocalPass<T>(funcs: Collection<Function>, threadNum: Int64, pass: (Function) -> T): ArrayList<T> {
    let taskQueue = TaskQueue(threadNum)
    let results = ArrayList<TaskResult<T>>()
    for (fn in funcs) {
        results.add(taskQueue.AddTask<T>({ => pass(fn) },
            priority: UInt64(fn.GetBody().getOrThrow().GetBlocks().size)))
    }
    taskQueue.RunAndWaitForAllTasksCompleted()
    let completed = ArrayList<T>()
    var firstFailure: Option<Exception> = None
    for (result in results) {
        try {
            completed.add(result.get())
        } catch (e: Exception) {
            if (firstFailure.isNone()) { firstFailure = Some(e) }
        }
    }
    if (let Some(e) <- firstFailure) { throw e }
    return completed
}

private func ModifyApplyCalleeInfo(loadResult: LocalVar, storeValue: Value): Unit {
    if (!storeValue.IsFunc()) {
        return
    }
    let funcBase = storeValue.AsFunction().getOrThrow()
    if (!funcBase.IsMemberFunc() || !funcBase.TestAttr(Attribute.STATIC)) {
        return
    }
    let thisType = funcBase.GetParentCustomTypeOrExtendedType().getOrThrow()
    let oldUsers = loadResult.GetUsers()
    for (user in oldUsers) {
        if (user.GetExprKind() == ExprKind.APPLY) {
            let apply = (user as Apply).getOrThrow()
            apply.SetThisType(thisType)
        }
        if (user.GetExprKind() == ExprKind.TRY_APPLY) {
            let apply = (user as TryApply).getOrThrow()
            apply.SetThisType(thisType)
        }
    }
}

public class RedundantLoadElimination {
    public init() {}

    public func RunOnPackage(pkg: Package, isDebug!: Bool = false, threadNum!: Int64 = 1): Int64 {
        var changed: Int64 = 0
        if (threadNum <= 1 || isDebug) {
            for (fn in pkg.GetGlobalFuncsWithBody()) {
                changed += RunOnFunction(fn, isDebug: isDebug)
            }
            return changed
        }
        let runs = RunFunctionLocalPass<(Int64, ArrayList<(Value, Expression)>)>(pkg.GetGlobalFuncsWithBody(), threadNum,
            { fn =>
                let globalUsers = ArrayList<(Value, Expression)>()
                (RunOnFunction(fn, false, globalUsers), globalUsers)
            })
        // Global users were appended in scheduling order; replay them in function order, as the serial loop does.
        for ((count, globalUsers) in runs) {
            changed += count
            for ((value, user) in globalUsers) {
                value.MoveUserToTail(user)
            }
        }
        return changed
    }

    public func RunOnFunction(fn: Function, isDebug!: Bool = false): Int64 {
        return RunOnFunction(fn, isDebug, ArrayList<(Value, Expression)>())
    }

    private func RunOnFunction(fn: Function, isDebug: Bool, globalUsers: ArrayList<(Value, Expression)>): Int64 {
        if (fn.TestAttr(Attribute.SKIP_ANALYSIS)) {
            return 0
        }
        if (let Some(body) <- fn.GetBody()) {
            let analysis = ReachingDefinitionAnalysis(fn)
            let resultOpt = Engine<ReachingDefinitionDomain>(fn, analysis).IterateToFixpoint()
            CJC_NULLPTR_CHECK(resultOpt)
            let result = resultOpt.getOrThrow()
            let toBeRemoved = ArrayList<Expression>()
            result.VisitWith(
                { _: ReachingDefinitionDomain, _: Expression, _: Int64 => () },
                { state: ReachingDefinitionDomain, expr: Expression, _: Int64 =>
                    if (expr.GetParentBlock().isSome() && expr.GetExprKind() == ExprKind.LOAD &&
                        expr.GetNumOfOperands() == 1) {
                        if (TryReplaceLoad(expr, state, body, isDebug, globalUsers)) {
                            toBeRemoved.add(expr)
                        }
                    }
                },
                { _: ReachingDefinitionDomain, _: Expression, _: Option<Block> => () }
            )
            for (expr in toBeRemoved) {
                if (expr.GetParentBlock().isSome()) {
                    expr.RemoveSelfFromBlock()
                }
            }
            return toBeRemoved.size
        }
        return 0
    }

    private func TryReplaceLoad(loadExpr: Expression, state: ReachingDefinitionDomain, scope: BlockGroup,
        isDebug: Bool, globalUsers: ArrayList<(Value, Expression)>): Bool {
        let location = loadExpr.GetOperand(0)
        if (let Some(storeExpr) <- state.CheckReachingDef(location)) {
            if (storeExpr.GetNumOfOperands() >= 1) {
                let storedValue = storeExpr.GetOperand(0)
                ModifyApplyCalleeInfo(loadExpr.GetResult().getOrThrow(), storedValue)
                if (ReplaceLoad(loadExpr, storedValue, scope, isDebug, globalUsers)) {
                    return true
                }
            }
        }
        if (let Some(validLoad) <- state.CheckReachingLoadDef(location)) {
            if (validLoad.nodeId == loadExpr.nodeId) {
                return false
            }
            if (let Some(validResult) <- validLoad.GetResult()) {
                if (ReplaceLoad(loadExpr, validResult, scope, isDebug, globalUsers)) {
                    return true
                }
            }
        }
        return false
    }

    private func ReplaceLoad(loadExpr: Expression, value: Value, scope: BlockGroup, isDebug: Bool,
        globalUsers: ArrayList<(Value, Expression)>): Bool {
        if (let Some(result) <- loadExpr.GetResult()) {
            if (value.IsGlobal()) {
                for (user in result.GetUsers()) {
                    globalUsers.add((value, user))
                }
            }
            result.ReplaceWith(value, scope)
            if (isDebug) {
                println("[RLE] replaced Load " + loadExpr.GetDebugLocation().ToString() +
                    " with " + value.GetIdentifier() + ".")
            }
            return true
        }
        return false
    }
}
