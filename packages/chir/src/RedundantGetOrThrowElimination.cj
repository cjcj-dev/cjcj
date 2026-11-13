package cjcj::chir

import cjcj::utils.CJC_ASSERT
import cjcj::utils.CJC_NULLPTR_CHECK
import std.collection.*

// Upstream CHIR/Optimization/RedundantGetOrThrowElimination.cpp (cangjie_compiler !2344): a getOrThrow on a
// value already unwrapped on every path reuses the earlier result, for both Apply and TryApply, and the
// redundant call is removed after the whole function has been visited.
public class RedundantGetOrThrowElimination {
    private let builder: Option<CHIRBuilder>

    public init() {
        builder = None
    }

    public init(builder: CHIRBuilder) {
        this.builder = Some(builder)
    }

    public func RunOnPackage(pkg: Package, isDebug!: Bool = false, threadNum!: Int64 = 1): Int64 {
        var changed: Int64 = 0
        let redundantCalls = ArrayList<Expression>()
        if (threadNum <= 1 || isDebug) {
            for (fn in pkg.GetGlobalFuncsWithBody()) {
                redundantCalls.add(all: CollectOnFunc(fn, isDebug: isDebug))
            }
        } else {
            // Result replacement stays on the function's own call results; call removal touches the shared
            // callee user list, so it is replayed serially below.
            for (calls in RunFunctionLocalPass<ArrayList<Expression>>(pkg.GetGlobalFuncsWithBody(), threadNum,
                { fn => CollectOnFunc(fn) }, passName: "redundant-get-or-throw")) {
                redundantCalls.add(all: calls)
            }
        }
        for (call in redundantCalls) {
            if (RemoveRedundantCall(call)) {
                changed++
            }
        }
        return changed
    }

    public func RunOnFunc(fn: Function, isDebug!: Bool = false): Int64 {
        var changed: Int64 = 0
        for (call in CollectOnFunc(fn, isDebug: isDebug)) {
            if (RemoveRedundantCall(call)) {
                changed++
            }
        }
        return changed
    }

    private func CollectOnFunc(fn: Function, isDebug!: Bool = false): ArrayList<Expression> {
        let analysis = GetOrThrowResultAnalysis(fn, isDebug: isDebug)
        let resultOpt = Engine<GetOrThrowResultDomain>(fn, analysis).IterateToFixpoint()
        CJC_NULLPTR_CHECK(resultOpt)
        let result = resultOpt.getOrThrow()
        let body = fn.GetBody().getOrThrow()
        let redundantCalls = ArrayList<Expression>()
        let replaceResult = { state: GetOrThrowResultDomain, expr: Expression =>
            if (IsGetOrThrowFunction(expr)) {
                CJC_ASSERT(expr.GetNumOfOperands() > 1)
                if (let Some(previous) <- state.CheckGetOrThrowResult(expr.GetOperand(1))) {
                    if (!refEq(previous, expr)) {
                        expr.GetResult().getOrThrow().ReplaceWith(previous.GetResult().getOrThrow(), body)
                        redundantCalls.add(expr)
                        if (isDebug) {
                            println("[RGetOtThrowE] replaced redundant getOrThrow result")
                        }
                    }
                }
            }
        }
        result.VisitWith(
            { state: GetOrThrowResultDomain, expr: Expression, _: Int64 => replaceResult(state, expr) },
            { _: GetOrThrowResultDomain, _: Expression, _: Int64 => () },
            { state: GetOrThrowResultDomain, expr: Expression, _: Option<Block> => replaceResult(state, expr) }
        )
        return redundantCalls
    }

    // Keeps the analysed CFG intact until every expression was visited; a TryApply leaves a GoTo to its
    // success block so the error edge disappears together with the call.
    private func RemoveRedundantCall(call: Expression): Bool {
        if (let Some(tryApply) <- (call as TryApply)) {
            let chirBuilder = match (builder) {
                case Some(b) => b
                // Without a builder the TryApply stays; its result already points at the earlier unwrap.
                case None => return false
            }
            let parent = tryApply.GetParentBlock().getOrThrow()
            let success = tryApply.GetSuccessBlock()
            tryApply.RemoveSelfFromBlock()
            parent.AppendExpression(chirBuilder.CreateGoTo(success, parent))
            return true
        }
        call.RemoveSelfFromBlock()
        return true
    }
}
