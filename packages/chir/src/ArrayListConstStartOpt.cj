package cjcj::chir

import cjcj::option.GlobalOptions

// C++: CHIR/Optimization/ArrayListConstStartOpt.cpp:14-17.
private let ARRAY_FUNC_INLINE_WHITE_LIST: Array<FuncInfo> = [
    FuncInfo("getUnchecked", "Array", [NOT_CARE], ANY_TYPE, "std.core"),
    FuncInfo("setUnchecked", "Array", [NOT_CARE], ANY_TYPE, "std.core")
]

// C++: CHIR/Optimization/ArrayListConstStartOpt.cpp:19-22.
private let ARRAYLIST_FUNC_LIST: Array<FuncInfo> = [
    FuncInfo("[]", "ArrayList", [NOT_CARE], ANY_TYPE, "std.collection"),
    FuncInfo("==", "ArrayList", [NOT_CARE], ANY_TYPE, "std.collection")
]

// C++: CHIR/Optimization/ArrayListConstStartOpt.cpp:24-26.
private let ARRAYLIST_ITERATOR_FUNC_LIST: Array<FuncInfo> = [
    FuncInfo("next", "ArrayListIterator", [NOT_CARE], ANY_TYPE, "std.collection")
]

// C++: CHIR/Optimization/ArrayListConstStartOpt.cpp:29-37.
private func InWhiteList(`func`: Function, whiteList: Array<FuncInfo>): Bool {
    for (element in whiteList) {
        if (IsExpectedFunction(`func`, element)) {
            return true
        }
    }
    return false
}

// C++: CHIR/Optimization/ArrayListConstStartOpt.h:20-54;
//      CHIR/Optimization/ArrayListConstStartOpt.cpp:40-201.
public class ArrayListConstStartOpt {
    private let builder: CHIRBuilder
    private let optPassName: String = "ArrayListConstStartOpt Inline"
    private let opts: GlobalOptions
    private let pass: FunctionInline
    private let effectMap: OptEffectCHIRMap = OptEffectCHIRMap()

    public init(builder: CHIRBuilder, opts: GlobalOptions, pass: FunctionInline) {
        this.builder = builder
        this.opts = opts
        this.pass = pass
    }

    // C++: CHIR/Optimization/ArrayListConstStartOpt.cpp:40-43.
    public func GetEffectMap(): OptEffectCHIRMap {
        return effectMap
    }

    // C++: CHIR/Optimization/ArrayListConstStartOpt.cpp:45-52.
    private func CheckNeedRewrite(apply: Apply): Bool {
        if (!apply.GetCallee().IsFuncWithBody()) {
            return false
        }
        let callee = apply.GetCallee().AsFunction().getOrThrow()
        return InWhiteList(callee, ARRAY_FUNC_INLINE_WHITE_LIST)
    }

    // C++: CHIR/Optimization/ArrayListConstStartOpt.cpp:54-140.
    private func IsStartAddIndexExpression(field: Field, isIteratorFunc: Bool): Bool {
        let resultTy = field.GetResult().getOrThrow().GetType().getOrThrow().GetTypeKind()
        if (resultTy != TypeKind.TYPE_INT64) {
            return false
        }

        if (field.GetPath()[0] != 1u64) {
            return false
        }

        var expr = field.GetBase().AsLocalVar().getOrThrow().GetExpr().getOrThrow()
        if (expr.GetExprKind() != ExprKind.LOAD) {
            return false
        }

        expr = expr.GetOperand(0).AsLocalVar().getOrThrow().GetExpr().getOrThrow()
        if (expr.GetExprKind() != ExprKind.GET_ELEMENT_REF) {
            return false
        }
        var getElementRef = (expr as GetElementRef).getOrThrow()
        if (getElementRef.GetPath()[0] != 0u64) {
            return false
        }

        var location = getElementRef.GetLocation()
        if (!isIteratorFunc && location.IsParameter()) {
            let param = location.AsParameter().getOrThrow()
            let topLevelFunc = field.GetTopLevelFunc().getOrThrow()
            if (param == topLevelFunc.GetParam(0) || param == topLevelFunc.GetParam(1)) {
                return true
            }
        }

        if (isIteratorFunc) {
            expr = location.AsLocalVar().getOrThrow().GetExpr().getOrThrow()
            if (expr.GetExprKind() != ExprKind.LOAD) {
                return false
            }
            expr = expr.GetOperand(0).AsLocalVar().getOrThrow().GetExpr().getOrThrow()
            if (expr.GetExprKind() != ExprKind.GET_ELEMENT_REF) {
                return false
            }
            getElementRef = (expr as GetElementRef).getOrThrow()
            if (getElementRef.GetPath()[0] != 1u64) {
                return false
            }

            location = getElementRef.GetLocation()
            if (!location.IsParameter()) {
                return false
            }
            let param = location.AsParameter().getOrThrow()
            let topLevelFunc = field.GetTopLevelFunc().getOrThrow()
            return param == topLevelFunc.GetParam(0) || param == topLevelFunc.GetParam(1)
        }
        return false
    }

    // C++: CHIR/Optimization/ArrayListConstStartOpt.cpp:142-159.
    private func RewriteStartWithConstZero(oldExpr: Expression): Unit {
        let oldExprResult = oldExpr.GetResult().getOrThrow()
        let oldExprParent = oldExpr.GetParentBlock().getOrThrow()
        let literalValueZero = builder.CreateLiteralValue(IntLiteral(0u64), builder.context.GetInt64Ty())
        let newExpr = builder.CreateConstant(
            oldExprResult.GetType().getOrThrow(), literalValueZero, oldExprParent)
        newExpr.SetDebugLocation(oldExpr.GetDebugLocation())

        oldExpr.ReplaceWith(newExpr)
        oldExprResult.ReplaceWith(newExpr.GetResult().getOrThrow(), newExpr.GetParentBlockGroup())

        if (opts.chirDebugOptimizer) {
            println("[ArrayListConstStartOpt] The " + oldExpr.GetExprKindName() +
                ToPosInfo(oldExpr.GetDebugLocation()) + " has been rewrited to a constant")
        }
    }

    // C++: CHIR/Optimization/ArrayListConstStartOpt.cpp:161-201.
    public func RunOnPackage(`package`: Package): Unit {
        for (`func` in `package`.GetGlobalFuncsWithBody()) {
            let isArrayListIteratorFunc = InWhiteList(`func`, ARRAYLIST_ITERATOR_FUNC_LIST)
            if (!isArrayListIteratorFunc && !InWhiteList(`func`, ARRAYLIST_FUNC_LIST)) {
                continue
            }

            let preVisit: VisitExprActionFunc = { expr =>
                if (expr.GetExprKind() != ExprKind.APPLY) {
                    return VisitResult.CONTINUE
                }

                let apply = (expr as Apply).getOrThrow()
                if (CheckNeedRewrite(apply)) {
                    pass.DoFunctionInline(apply, optPassName)
                    MergeEffectMap(pass.GetEffectMap(), effectMap)
                }

                return VisitResult.CONTINUE
            }
            Visitor.Visit(`func`, preVisit)

            let removeStartVisit: VisitExprActionFunc = { expr =>
                if (expr.GetExprKind() != ExprKind.FIELD) {
                    return VisitResult.CONTINUE
                }

                let field = (expr as Field).getOrThrow()
                if (IsStartAddIndexExpression(field, isArrayListIteratorFunc)) {
                    RewriteStartWithConstZero(expr)
                }

                return VisitResult.CONTINUE
            }
            Visitor.Visit(`func`, removeStartVisit)
        }
    }
}
