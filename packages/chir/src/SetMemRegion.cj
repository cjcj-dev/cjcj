package cjcj::chir

import std.collection.*

private func CaptureBody(value: Value): BlockGroup {
    if (let Some(p) <- value.AsParameter()) {
        if (let Some(fn) <- p.GetOwnerFunc()) { return fn.GetBody().getOrThrow() }
        return p.GetOwnerLambda().getOrThrow().GetBody().getOrThrow()
    }
    let defining = value.AsLocalVar().getOrThrow().GetExpr().getOrThrow()
    return defining.GetParentBlockGroup().getOrThrow().GetFuncOrLambdaBody().getOrThrow()
}

private func SignatureNeedsRegion(params: ArrayList<Parameter>, ret: Option<Type>): Bool {
    if ((let Some(ty) <- ret) && ty.StripAllRefs().IsLocalRegion()) { return true }
    for (param in params) {
        let ty = param.GetType().getOrThrow().StripAllRefs()
        if (ty.IsMustLocalRegion() || (ty.IsMaybeLocalRegion() && param.paramDftValFunc.isSome())) { return true }
    }
    return false
}

private func CallNeedsRegion(expr: Expression): Bool {
    if ((let Some(result) <- expr.GetResultType()) && result.StripAllRefs().IsLocalRegion()) { return true }
    let callee = expr.GetOperand(0)
    if (let Some(fn) <- callee.AsFunction()) {
        if ((expr is Apply || expr is TryApply) && fn.IsConstructor() && fn.GetParentCustomTypeDef().isSome() &&
            fn.GetParam(0).GetType().getOrThrow().StripAllRefs().IsLocalRegion()) { return true }
        let decl = fn.GetGenericDecl() ?? fn
        return SignatureNeedsRegion(decl.GetParams(), decl.GetReturnType())
    }
    if ((let Some(local) <- callee.AsLocalVar()) && (let Some(def) <- local.GetExpr()) &&
        (let Some(lambda) <- (def as Lambda))) {
        let decl = lambda.GetGenericDecl() ?? lambda
        return SignatureNeedsRegion(decl.GetParams(), decl.GetReturnType())
    }
    return false
}

private func AllReturnsInExclave(result: LocalVar): Bool {
    if (!result.IsRetValue()) { return false }
    for (user in result.GetUsers()) {
        let store = (user as Store) ?? continue
        if (!refEq(store.GetLocation(), result) || store.GetValue().GetType().getOrThrow().IsNothing()) { continue }
        var bg = user.GetParentBlockGroup().getOrThrow()
        while (true) {
            let owner = bg.GetOwnerExpression() ?? return false
            if (owner is Exclave) { break }
            bg = owner.GetParentBlockGroup().getOrThrow()
        }
    }
    return true
}

// Select owners before closure conversion erases lexical capture boundaries.
public class SetMemRegion {
    private let builder: CHIRBuilder
    public init(builder: CHIRBuilder) { this.builder = builder }

    public func RunOnPackage(pkg: Package): Unit {
        for (fn in pkg.GetGlobalFuncsWithBody()) {
            let body = fn.GetBody().getOrThrow()
            if (fn.GetWrappedRawMethod().isNone()) {
                let owners = HashMap<Int64, BlockGroup>()
                Visitor.Visit(body, { expr: Expression =>
                    if (expr is Exclave) { return VisitResult.SKIP }
                    let enclosing = expr.GetParentBlockGroup().getOrThrow().GetFuncOrLambdaBody().getOrThrow()
                    var needed = false
                    if (expr is FuncCall || expr is FuncCallWithException) {
                        needed = CallNeedsRegion(expr)
                    } else if (let Some(lambda) <- (expr as Lambda)) {
                        for (capture in lambda.GetCapturedVariables()) {
                            if (!capture.GetType().getOrThrow().StripAllRefs().IsLocalRegion()) { continue }
                            let outer = CaptureBody(capture)
                            var bg = lambda.GetBody().getOrThrow()
                            while (!refEq(bg, outer)) {
                                owners[bg.nodeId] = bg
                                bg = bg.GetOwnerExpression().getOrThrow().GetParentBlockGroup().getOrThrow()
                                    .GetFuncOrLambdaBody().getOrThrow()
                            }
                            owners[outer.nodeId] = outer
                        }
                        needed = lambda.GetFuncType().getOrThrow().IsLocalRegion()
                    } else if (expr is RawArrayAllocateBase || expr is Box) {
                        // This frontend can lower constructors directly to allocation/box instructions.
                        // There is no Apply left to establish the caller's region in that case.
                        needed = expr.GetResultType().getOrThrow().StripAllRefs().IsLocalRegion()
                    } else if (expr is Allocate || expr is TryAllocate || expr is Tuple) {
                        let result = expr.GetResult().getOrThrow()
                        let ty = result.GetType().getOrThrow().StripAllRefs()
                        if (ty.IsLocalRegion() && (let Some(e) <- (ty as EnumType))) {
                            needed = !e.GetEnumDef().IsAllCtorsTrivial() && !AllReturnsInExclave(result)
                        }
                    } else if (expr is Constant) {
                        needed = expr.GetResultType().getOrThrow().StripAllRefs().IsMustLocalRegion()
                    }
                    if (needed) { owners[enclosing.nodeId] = enclosing }
                    return VisitResult.CONTINUE
                })
                for ((_, owner) in owners) {
                    if (!refEq(owner, body) || !fn.TestAttr(Attribute.EXCLAVE)) { SetRegion(owner) }
                }
            }
            Visitor.Visit(body, { _: Expression => VisitResult.CONTINUE }, { expr: Expression =>
                if (let Some(exclave) <- (expr as Exclave)) {
                    let group = exclave.GetBody()
                    let entry = group.GetEntryBlock().getOrThrow()
                    let outer = expr.GetParentBlockGroup().getOrThrow()
                    for (block in group.GetBlocks()) { block.MoveTo(outer) }
                    expr.ReplaceWith(builder.CreateGoTo(entry, expr.GetParentBlock().getOrThrow()))
                }
                return VisitResult.CONTINUE
            })
            fn.DisableAttr(Attribute.EXCLAVE)
        }
    }

    private func SetRegion(owner: BlockGroup): Unit {
        let entry = owner.GetEntryBlock().getOrThrow()
        entry.InsertExprIntoHead(builder.CreateRegionBoundary(ExprKind.START_REGION, entry))
        Visitor.Visit(owner, { expr: Expression =>
            if (expr is Lambda) { return VisitResult.SKIP }
            if (expr is Exit || expr is Exclave) {
                builder.CreateRegionBoundary(ExprKind.END_REGION, expr.GetParentBlock().getOrThrow()).MoveBefore(expr)
                if (expr is Exclave) { return VisitResult.SKIP }
            }
            return VisitResult.CONTINUE
        })
    }
}
