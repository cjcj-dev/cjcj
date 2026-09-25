package cjcj::chir

import std.collection.*
import cjcj::utils.OverflowStrategy

public open class ExpressionBase {
    private let expr: Expression

    protected init(expr: Expression) {
        this.expr = expr
    }

    public func GetRawExpr(): Expression {
        return expr
    }

    public func GetResult(): Option<LocalVar> {
        return expr.GetResult()
    }

    public func GetOperands(): ArrayList<Value> {
        return expr.GetNonSuccessorOperands()
    }
}

public open class FuncCallBase <: ExpressionBase {
    private let expr: Option<FuncCall>
    private let exprE: Option<FuncCallWithException>

    public init(expression: Expression) {
        super(expression)
        if (let Some(funcCall) <- (expression as FuncCall)) {
            expr = funcCall
            exprE = None
        } else {
            expr = None
            exprE = (expression as FuncCallWithException).getOrThrow()
        }
    }

    public init(expression: FuncCall) {
        super(expression)
        expr = expression
        exprE = None
    }

    public init(expression: FuncCallWithException) {
        super(expression)
        expr = None
        exprE = expression
    }

    public func GetArgs(): ArrayList<Value> {
        if (let Some(call) <- expr) {
            return call.GetArgs()
        }
        return exprE.getOrThrow().GetArgs()
    }

    public func GetThisType(): Option<Type> {
        if (let Some(call) <- expr) {
            return call.GetThisType()
        }
        return exprE.getOrThrow().GetThisType()
    }

    public func GetInstantiatedTypeArgs(): ArrayList<Type> {
        if (let Some(call) <- expr) {
            return call.GetInstantiatedTypeArgs()
        }
        return exprE.getOrThrow().GetInstantiatedTypeArgs()
    }

    public func GetInstantiatedTypeArgsRef(): ArrayList<Type> {
        if (let Some(call) <- expr) {
            return call.GetInstantiatedTypeArgs()
        }
        return exprE.getOrThrow().GetInstantiatedTypeArgs()
    }
}

public class ApplyBase <: FuncCallBase {
    private let expr: Option<Apply>
    private let exprE: Option<ApplyWithException>

    public init(expression: Expression) {
        super(expression)
        if (expression.GetExprKind() == ExprKind.APPLY) {
            expr = (expression as Apply).getOrThrow()
            exprE = None
        } else {
            expr = None
            exprE = (expression as ApplyWithException).getOrThrow()
        }
    }

    public init(expression: Apply) {
        super(expression)
        expr = expression
        exprE = None
    }

    public init(expression: ApplyWithException) {
        super(expression)
        expr = None
        exprE = expression
    }

    public func GetCallee(): Value {
        if (let Some(apply) <- expr) {
            return apply.GetCallee()
        }
        return exprE.getOrThrow().GetCallee()
    }

    public func GetInstParentCustomTyOfCallee(builder: CHIRBuilder): Option<Type> {
        if (let Some(apply) <- expr) {
            return apply.GetInstParentCustomTyOfCallee(builder)
        }
        return exprE.getOrThrow().GetInstParentCustomTyOfCallee(builder)
    }
}

public open class DynamicDispatchBase <: FuncCallBase {
    private let expr: Option<DynamicDispatch>
    private let exprE: Option<DynamicDispatchWithException>

    public init(expression: Expression) {
        super(expression)
        if (let Some(dispatch) <- (expression as DynamicDispatch)) {
            expr = dispatch
            exprE = None
        } else {
            expr = None
            exprE = (expression as DynamicDispatchWithException).getOrThrow()
        }
    }

    public init(expression: DynamicDispatch) {
        super(expression)
        expr = expression
        exprE = None
    }

    public init(expression: DynamicDispatchWithException) {
        super(expression)
        expr = None
        exprE = expression
    }

    public func GetGenericTypeParams(): ArrayList<GenericType> {
        if (let Some(dispatch) <- expr) {
            return dispatch.GetGenericTypeParams()
        }
        return exprE.getOrThrow().GetGenericTypeParams()
    }

    public func GetGenericTypeParamsRef(): ArrayList<GenericType> {
        if (let Some(dispatch) <- expr) {
            return dispatch.GetGenericTypeParams()
        }
        return exprE.getOrThrow().GetGenericTypeParams()
    }

    public func GetMethodName(): String {
        if (let Some(dispatch) <- expr) {
            return dispatch.GetMethodName()
        }
        return exprE.getOrThrow().GetMethodName()
    }

    public func GetMethodType(): FuncType {
        if (let Some(dispatch) <- expr) {
            return dispatch.GetMethodType()
        }
        return exprE.getOrThrow().GetMethodType()
    }

    public func GetVirtualMethodOffset(): UInt64 {
        if (let Some(dispatch) <- expr) {
            return dispatch.GetVirtualMethodOffset()
        }
        return exprE.getOrThrow().GetVirtualMethodOffset()
    }

    public func GetInstSrcParentCustomTypeOfMethod(builder: CHIRBuilder): ClassType {
        if (let Some(dispatch) <- expr) {
            return dispatch.GetInstSrcParentCustomTypeOfMethod(builder)
        }
        return exprE.getOrThrow().GetInstSrcParentCustomTypeOfMethod(builder)
    }
}

public class InvokeBase <: DynamicDispatchBase {
    private let expr: Option<Invoke>
    private let exprE: Option<InvokeWithException>

    public init(expression: Expression) {
        super(expression)
        if (expression.GetExprKind() == ExprKind.INVOKE) {
            expr = (expression as Invoke).getOrThrow()
            exprE = None
        } else {
            expr = None
            exprE = (expression as InvokeWithException).getOrThrow()
        }
    }

    public init(expression: Invoke) {
        super(expression)
        expr = expression
        exprE = None
    }

    public init(expression: InvokeWithException) {
        super(expression)
        expr = None
        exprE = expression
    }

    public func GetObject(): Value {
        if (let Some(invoke) <- expr) {
            return invoke.GetObject()
        }
        return exprE.getOrThrow().GetObject()
    }
}

public class InvokeStaticBase <: DynamicDispatchBase {
    private let expr: Option<InvokeStatic>
    private let exprE: Option<InvokeStaticWithException>

    public init(expression: Expression) {
        super(expression)
        if (expression.GetExprKind() == ExprKind.INVOKESTATIC) {
            expr = (expression as InvokeStatic).getOrThrow()
            exprE = None
        } else {
            expr = None
            exprE = (expression as InvokeStaticWithException).getOrThrow()
        }
    }

    public init(expression: InvokeStatic) {
        super(expression)
        expr = expression
        exprE = None
    }

    public init(expression: InvokeStaticWithException) {
        super(expression)
        expr = None
        exprE = expression
    }

    public func GetRTTIValue(): Value {
        if (let Some(invoke) <- expr) {
            return invoke.GetRTTIValue()
        }
        return exprE.getOrThrow().GetRTTIValue()
    }
}

public class UnaryExprBase <: ExpressionBase {
    private let expr: UnaryExpressionBase

    public init(expression: Expression) {
        super(expression)
        expr = (expression as UnaryExpressionBase).getOrThrow()
    }

    public init(expression: UnaryExpressionBase) {
        super(expression)
        expr = expression
    }

    public func GetOpKind(): ExprKind { return expr.GetOpKind() }

    public func GetExprKindName(): String { return expr.GetExprKindName() }

    public func GetOperand(): Value { return expr.GetOperand(0) }

    public func GetOverflowStrategy(): OverflowStrategy { return expr.GetOverflowStrategy() }
}

public class BinaryExprBase <: ExpressionBase {
    private let expr: BinaryExpressionBase

    public init(expression: Expression) {
        super(expression)
        expr = (expression as BinaryExpressionBase).getOrThrow()
    }

    public init(expression: BinaryExpressionBase) {
        super(expression)
        expr = expression
    }

    public func GetOpKind(): ExprKind { return expr.GetOpKind() }

    public func GetExprKindName(): String { return expr.GetExprKindName() }

    public func GetLHSOperand(): Value { return expr.GetLHSOperand() }

    public func GetRHSOperand(): Value { return expr.GetRHSOperand() }

    public func GetOverflowStrategy(): OverflowStrategy { return expr.GetOverflowStrategy() }
}


public class IntrinsicBase <: ExpressionBase {
    private let expr: Option<Intrinsic>
    private let exprE: Option<IntrinsicWithException>

    public init(expression: Expression) {
        super(expression)
        if (expression.GetExprKind() == ExprKind.INTRINSIC) {
            expr = (expression as Intrinsic).getOrThrow()
            exprE = None
        } else {
            expr = None
            exprE = (expression as IntrinsicWithException).getOrThrow()
        }
    }

    public init(expression: Intrinsic) {
        super(expression)
        expr = expression
        exprE = None
    }

    public init(expression: IntrinsicWithException) {
        super(expression)
        expr = None
        exprE = expression
    }

    public func GetIntrinsicKind(): IntrinsicKind {
        if (let Some(intrinsic) <- expr) {
            return intrinsic.GetIntrinsicKind()
        }
        return exprE.getOrThrow().GetIntrinsicKind()
    }

    public func GetInstantiatedTypeArgs(): ArrayList<Type> {
        if (let Some(intrinsic) <- expr) {
            return intrinsic.GetInstantiatedTypeArgs()
        }
        return exprE.getOrThrow().GetInstantiatedTypeArgs()
    }

    public func GetInstantiatedTypeArgsRef(): ArrayList<Type> {
        if (let Some(intrinsic) <- expr) {
            return intrinsic.GetInstantiatedTypeArgs()
        }
        return exprE.getOrThrow().GetInstantiatedTypeArgs()
    }
}
