package cjcj::chir

import std.collection.ArrayList

// Upstream DevirtualizeTrivialStatics.h:26-31 (ae3b4d8a).
private class TrivialStaticRewriteInfo {
    let invokeStatic: InvokeStatic
    let realCallee: Function
    let thisType: Type
    var newApply: Option<Apply> = None

    init(invokeStatic: InvokeStatic, realCallee: Function, thisType: Type) {
        this.invokeStatic = invokeStatic
        this.realCallee = realCallee
        this.thisType = thisType
    }
}

// Upstream DevirtualizeTrivialStatics.cpp:31-77 (d1f7107d).
private func ResolveStaticCallee(invoke: InvokeStatic, clazz: ClassType,
    builder: CHIRBuilder): Option<Function> {
    // Actual argument types distinguish multiple instantiations of the same method.
    let instParamTypes = ArrayList<Type>()
    for (arg in invoke.GetArgs()) {
        instParamTypes.add(arg.GetType().getOrThrow())
    }
    let instFuncType = builder.context.GetFuncTy(instParamTypes, builder.context.GetUnitTy())
    let funcCallType = FuncCallType(instFuncType, funcName: invoke.GetMethodName())
    let candidates = GetFuncIndexInVTable(clazz, funcCallType, builder)
    for (cand in candidates) {
        if (cand.instance.isNone()) {
            continue
        }
        var expectedFunc = cand.instance.getOrThrow()
        if (expectedFunc.IsPureAbstract()) {
            continue
        }
        // Rewriting reuses args without casts: unwrap only on exact parameter types.
        if (let Some(rawFunc) <- expectedFunc.GetWrappedRawMethod()) {
            let rawParams = rawFunc.GetFuncType().getOrThrow().GetParamTypes()
            let args = invoke.GetArgs()
            if (rawParams.size != args.size) {
                return None
            }
            for (i in 0..args.size) {
                if (args[i].GetType().getOrThrow() != rawParams[i]) {
                    return None
                }
            }
            expectedFunc = rawFunc
        }
        return Some(expectedFunc)
    }
    return None
}

// Upstream DevirtualizeTrivialStatics.cpp:79-112 (d1f7107d).
private func RewriteInvokeStatic(expr: Expression, builder: CHIRBuilder,
    rewriteInfos: ArrayList<TrivialStaticRewriteInfo>): Unit {
    let invoke = (expr as InvokeStatic) ?? return ()
    if (!invoke.GetInstantiatedTypeArgs().isEmpty()) { return }
    let rttiLocalVar = (invoke.GetRTTIValue() as LocalVar) ?? return ()
    let value = rttiLocalVar.GetExpr() ?? return ()
    let rttiStatic = (value as GetRTTIStatic) ?? return ()
    let thisType = invoke.GetThisType().getOrThrow().StripAllRefs()
    if (!thisType.IsClass() || thisType.IsGenericRelated()) { return }
    let clazz = (thisType as ClassType).getOrThrow()
    if (rttiStatic.GetRTTIType().StripAllRefs() != clazz) { return }
    let expectedFunc = ResolveStaticCallee(invoke, clazz, builder) ?? return ()
    rewriteInfos.add(TrivialStaticRewriteInfo(invoke, expectedFunc, invoke.GetThisType().getOrThrow()))
}

public class DevirtualizeTrivialStatics {
    private let rewriteInfos = ArrayList<TrivialStaticRewriteInfo>()

    // Upstream DevirtualizeTrivialStatics.cpp:22-29 (d1f7107d).
    public func RunOnPackage(pkg: Package, builder: CHIRBuilder, isDebug: Bool): Unit {
        rewriteInfos.clear()
        for (fn in pkg.GetGlobalFuncsWithBody()) {
            RunOnFunc(fn, builder)
        }
        RewriteToApply(builder, rewriteInfos, isDebug)
    }

    private func RunOnFunc(fn: Function, builder: CHIRBuilder): Unit {
        let actionBeforeVisitExpr: VisitExprActionFunc = { expr =>
            if (expr.GetExprKind() == ExprKind.INVOKESTATIC) {
                RewriteInvokeStatic(expr, builder, rewriteInfos)
                return VisitResult.CONTINUE
            }
            return VisitResult.CONTINUE
        }
        Visitor.Visit(fn, actionBeforeVisitExpr)
    }

    private static func RewriteToApply(builder: CHIRBuilder,
        rewriteInfos: ArrayList<TrivialStaticRewriteInfo>, isDebug: Bool): Unit {
        var index = rewriteInfos.size - 1
        while (index >= 0) {
            let rewriteInfo = rewriteInfos[index]
            let invoke = rewriteInfo.invokeStatic
            let parent = invoke.GetParentBlock().getOrThrow()
            let thisType = rewriteInfo.thisType
            let realFunc = rewriteInfo.realCallee
            let args = invoke.GetArgs()
            let instRetTy = invoke.GetResultType().getOrThrow()
            let loc = invoke.GetDebugLocation()
            let apply = builder.CreateApply(instRetTy, realFunc,
                FuncCallContext(args: args, thisType: Some(thisType)), parent)
            apply.SetDebugLocation(loc)
            rewriteInfo.newApply = Some(apply)
            invoke.ReplaceWith(apply)
            invoke.GetResult().getOrThrow().ReplaceWith(apply.GetResult().getOrThrow(),
                parent.GetParentBlockGroup())
            if (isDebug) {
                println("[DevirtualizeTrivialStatics] The function call to " + invoke.GetMethodName() +
                    ToPosInfo(invoke.GetDebugLocation()) + " was optimized.")
            }
            index--
        }
    }
}
