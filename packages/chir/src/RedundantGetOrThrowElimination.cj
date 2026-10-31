package cjcj::chir

import cjcj::utils.CJC_NULLPTR_CHECK
import std.collection.*
import std.core.Box as CoreBox

public class RedundantGetOrThrowElimination {
    public init() {}

    public func RunOnPackage(pkg: Package, isDebug!: Bool = false, threadNum!: Int64 = 1): Int64 {
        var changed: Int64 = 0
        if (threadNum <= 1 || isDebug) {
            for (fn in pkg.GetGlobalFuncsWithBody()) {
                changed += RunOnFunc(fn, isDebug: isDebug)
            }
            return changed
        }
        // Replacements stay on this function's own Apply results, so no global-user order needs replaying.
        for (count in RunFunctionLocalPass<Int64>(pkg.GetGlobalFuncsWithBody(), threadNum, { fn => RunOnFunc(fn) })) {
            changed += count
        }
        return changed
    }

    public func RunOnFunc(fn: Function, isDebug!: Bool = false): Int64 {
        let analysis = GetOrThrowResultAnalysis(fn, isDebug: isDebug)
        let resultOpt = Engine<GetOrThrowResultDomain>(fn, analysis).IterateToFixpoint()
        CJC_NULLPTR_CHECK(resultOpt)
        let result = resultOpt.getOrThrow()
        let changed = CoreBox<Int64>(0)
        result.VisitWith(
            { state: GetOrThrowResultDomain, expr: Expression, _: Int64 =>
                if (IsGetOrThrowFunction(expr)) {
                    let apply = (expr as Apply).getOrThrow()
                    let args = apply.GetArgs()
                    if (let Some(previous) <- state.CheckGetOrThrowResult(args[0])) {
                        let previousResult = previous.GetResult().getOrThrow()
                        let applyResult = apply.GetResult().getOrThrow()
                        applyResult.ReplaceWith(previousResult, fn.GetBody().getOrThrow())
                        changed.value++
                        if (isDebug) {
                            println("[RGetOtThrowE] replaced redundant getOrThrow result")
                        }
                    }
                }
            },
            { _: GetOrThrowResultDomain, _: Expression, _: Int64 => () },
            { _: GetOrThrowResultDomain, _: Expression, _: Option<Block> => () }
        )
        return changed.value
    }
}
