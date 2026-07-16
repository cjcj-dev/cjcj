package cjcj::chir

import std.collection.HashSet
import cjcj::utils.{CJC_ASSERT, CORE_PACKAGE_NAME, StaticCast}

private let ARRAY_INIT_FUNC_INFO =
    FuncInfo("arrayInitByFunction", "", [NOT_CARE], NOT_CARE, CORE_PACKAGE_NAME)

public class ArrayLambdaOpt {
    private let builder: CHIRBuilder

    public init(builder: CHIRBuilder) {
        this.builder = builder
    }

    public func RunOnPackage(pkg: Package, isDebug: Bool): Unit {
        for (`func` in pkg.GetGlobalFuncsWithBody()) {
            RunOnFunc(`func`, isDebug)
        }
    }

    private func RunOnFunc(`func`: Function, isDebug: Bool): Unit {
        let preAcation: VisitExprActionFunc = { expr =>
            if (let Some(constVal) <- CheckCanRewriteLambda(expr)) {
                RewriteArrayInitFunc(StaticCast<Apply>(expr), constVal)
                if (isDebug) {
                    println("[ArrayLambda] The call to arrayInitByFunction" +
                        ToPosInfo(expr.GetDebugLocation()) +
                        " has been optimised to a call to arrayInitByValue.")
                }
            } else if (let Some(zeroValue) <- CheckCanRewriteZeroValue(expr)) {
                RewriteZeroValue(StaticCast<RawArrayInitByValue>(expr), zeroValue)
                if (isDebug) {
                    println("[ArrayLambda] The call to arrayInitByValue" +
                        ToPosInfo(expr.GetDebugLocation()) +
                        " has been optimised due to the item is ZeroValue.")
                }
            }
            return VisitResult.CONTINUE
        }
        Visitor.Visit(`func`, preAcation)
    }

    private func CheckCanRewriteLambda(expr: Expression): Option<Constant> {
        if (expr.GetExprKind() != ExprKind.APPLY) {
            return None
        }
        let apply = StaticCast<Apply>(expr)
        let callee = apply.GetCallee()
        if (!callee.IsFuncWithBody()) {
            return None
        }
        if (!IsExpectedFunction(callee.AsFunction().getOrThrow(), ARRAY_INIT_FUNC_INFO)) {
            return None
        }

        let INIT_LAMBDA_INDEX: Int64 = 1
        CJC_ASSERT(apply.GetArgs().size == INIT_LAMBDA_INDEX + 1)
        let closureVar = apply.GetArgs()[INIT_LAMBDA_INDEX]
        if (!closureVar.IsLocalVar()) {
            return None
        }
        let closure = StaticCast<LocalVar>(closureVar).GetExpr().getOrThrow()
        if (closure.GetExprKind() != ExprKind.LAMBDA) {
            return None
        }
        return CheckIfLambdaReturnConst(StaticCast<Lambda>(closure))
    }

    private func CheckIfLambdaReturnConst(lambda: Lambda): Option<Constant> {
        let ret = lambda.GetReturnValue()
        if (ret.isNone()) {
            return None
        }
        let retValue = ret.getOrThrow()
        CJC_ASSERT(retValue.GetExpr().getOrThrow().GetExprKind() == ExprKind.ALLOCATE)
        let users = retValue.GetUsers()
        if (users.size == 1) {
            let store = users[0]
            if (store.GetExprKind() == ExprKind.STORE) {
                let storedValue = StaticCast<Store>(store).GetValue()
                if (!storedValue.IsLocalVar()) {
                    return None
                }
                let constant = StaticCast<LocalVar>(storedValue).GetExpr().getOrThrow()
                if (constant.GetExprKind() != ExprKind.CONSTANT) {
                    return None
                }

                let validExprs = HashSet<Expression>(
                    [retValue.GetExpr().getOrThrow(), store, constant])
                let blocksInLambda = lambda.GetBody().getOrThrow().GetBlocks()
                if (blocksInLambda.size > 1) {
                    return None
                }
                for (lambdaExpr in blocksInLambda[0].GetExpressions()) {
                    if (lambdaExpr.IsDebug() || lambdaExpr.IsTerminator()) {
                        continue
                    }
                    if (!validExprs.contains(lambdaExpr)) {
                        return None
                    }
                }
                return Some(StaticCast<Constant>(constant))
            }
        }
        return None
    }

    private func RewriteArrayInitFunc(apply: Apply, constant: Constant): Unit {
        let loc = apply.GetDebugLocation()
        let rawArray = apply.GetArgs()[0]
        let size = StaticCast<LocalVar>(rawArray).GetExpr().getOrThrow().GetOperand(0)
        let parent = apply.GetParentBlock().getOrThrow()
        let initVal = builder.CreateConstant(
            constant.GetResult().getOrThrow().GetType().getOrThrow(), constant.GetValue(), parent)
        initVal.SetDebugLocation(constant.GetDebugLocation())
        let newExpr = builder.CreateRawArrayInitByValue(
            builder.context.GetUnitTy(), rawArray, size, initVal.GetResult().getOrThrow(), parent)
        newExpr.SetDebugLocation(loc)

        initVal.MoveBefore(apply)
        apply.ReplaceWith(newExpr)
        newExpr.GetResult().getOrThrow().ReplaceWith(rawArray, parent.GetParentBlockGroup())
    }

    private func CheckCanRewriteZeroValue(expr: Expression): Option<Intrinsic> {
        if (expr.GetExprKind() != ExprKind.RAW_ARRAY_INIT_BY_VALUE) {
            return None
        }
        let `init` = StaticCast<RawArrayInitByValue>(expr)
        if (!`init`.GetInitValue().IsLocalVar()) {
            return None
        }
        let initVal = StaticCast<LocalVar>(`init`.GetInitValue())
        let initExpr = initVal.GetExpr().getOrThrow()
        if (initExpr.GetExprKind() != ExprKind.INTRINSIC) {
            return None
        }
        let intrinsic = StaticCast<Intrinsic>(initExpr)
        if (intrinsic.GetIntrinsicKind() != IntrinsicKind.OBJECT_ZERO_VALUE) {
            return None
        }
        return Some(intrinsic)
    }

    private func RewriteZeroValue(`init`: RawArrayInitByValue, zeroVal: Intrinsic): Unit {
        CJC_ASSERT(`init`.GetResult().getOrThrow().GetUsers().isEmpty())
        `init`.RemoveSelfFromBlock()

        let users = zeroVal.GetResult().getOrThrow().GetUsers()
        if (users.isEmpty()) {
            zeroVal.RemoveSelfFromBlock()
        } else if (users.size == 1 && users[0].GetExprKind() == ExprKind.DEBUGEXPR) {
            users[0].RemoveSelfFromBlock()
            zeroVal.RemoveSelfFromBlock()
        }
    }
}
