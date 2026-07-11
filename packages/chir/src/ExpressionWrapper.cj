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
        return expr.GetOperands()
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
            return dispatch.GetVirtualMethodOffset().getOrThrow()
        }
        return exprE.getOrThrow().GetVirtualMethodOffset().getOrThrow()
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
    private let expr: Option<UnaryExpression>
    private let exprE: Option<IntOpWithException>

    public init(expression: Expression) {
        super(expression)
        if (expression.GetExprMajorKind() == ExprMajorKind.UNARY_EXPR) {
            expr = (expression as UnaryExpression).getOrThrow()
            exprE = None
        } else {
            expr = None
            exprE = (expression as IntOpWithException).getOrThrow()
        }
    }

    public init(expression: UnaryExpression) {
        super(expression)
        expr = expression
        exprE = None
    }

    public init(expression: IntOpWithException) {
        super(expression)
        expr = None
        exprE = expression
    }

    public func GetOpKind(): ExprKind {
        if (let Some(unary) <- expr) {
            return unary.GetExprKind()
        }
        return exprE.getOrThrow().GetOpKind()
    }

    public func GetExprKindName(): String {
        if (let Some(unary) <- expr) {
            return unary.GetExprKindName()
        }
        return exprE.getOrThrow().GetOpKindName()
    }

    public func GetOperand(): Value {
        if (let Some(unary) <- expr) {
            return unary.GetOperand(0)
        }
        return exprE.getOrThrow().GetLHSOperand()
    }

    public func GetOverflowStrategy(): OverflowStrategy {
        if (let Some(unary) <- expr) {
            return unary.GetOverflowStrategy()
        }
        return exprE.getOrThrow().GetOverflowStrategy()
    }
}

public class BinaryExprBase <: ExpressionBase {
    private let expr: Option<BinaryExpression>
    private let exprE: Option<IntOpWithException>

    public init(expression: Expression) {
        super(expression)
        if (expression.GetExprMajorKind() == ExprMajorKind.BINARY_EXPR) {
            expr = (expression as BinaryExpression).getOrThrow()
            exprE = None
        } else {
            expr = None
            exprE = (expression as IntOpWithException).getOrThrow()
        }
    }

    public init(expression: BinaryExpression) {
        super(expression)
        expr = expression
        exprE = None
    }

    public init(expression: IntOpWithException) {
        super(expression)
        expr = None
        exprE = expression
    }

    public func GetOpKind(): ExprKind {
        if (let Some(binary) <- expr) {
            return binary.GetExprKind()
        }
        return exprE.getOrThrow().GetOpKind()
    }

    public func GetExprKindName(): String {
        if (let Some(binary) <- expr) {
            return binary.GetExprKindName()
        }
        return exprE.getOrThrow().GetOpKindName()
    }

    public func GetLHSOperand(): Value {
        if (let Some(binary) <- expr) {
            return binary.GetOperand(0)
        }
        return exprE.getOrThrow().GetLHSOperand()
    }

    public func GetRHSOperand(): Value {
        if (let Some(binary) <- expr) {
            return binary.GetOperand(1)
        }
        return exprE.getOrThrow().GetRHSOperand().getOrThrow()
    }

    public func GetOverflowStrategy(): OverflowStrategy {
        if (let Some(binary) <- expr) {
            return binary.GetOverflowStrategy()
        }
        return exprE.getOrThrow().GetOverflowStrategy()
    }
}

public class SpawnBase <: ExpressionBase {
    private let expr: Option<Spawn>
    private let exprE: Option<SpawnWithException>

    public init(expression: Expression) {
        super(expression)
        if (expression.GetExprKind() == ExprKind.SPAWN) {
            expr = (expression as Spawn).getOrThrow()
            exprE = None
        } else {
            expr = None
            exprE = (expression as SpawnWithException).getOrThrow()
        }
    }

    public init(expression: Spawn) {
        super(expression)
        expr = expression
        exprE = None
    }

    public init(expression: SpawnWithException) {
        super(expression)
        expr = None
        exprE = expression
    }

    public func GetObject(): Value {
        if (let Some(spawnExpr) <- expr) {
            return spawnExpr.GetOperands()[0]
        }
        return exprE.getOrThrow().GetOperands()[0]
    }

    public func IsExecuteClosure(): Bool {
        if (let Some(spawnExpr) <- expr) {
            return spawnExpr.IsExecuteClosure()
        }
        return exprE.getOrThrow().IsExecuteClosure()
    }
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

public class AllocateBase <: ExpressionBase {
    private let expr: Option<Allocate>
    private let exprE: Option<AllocateWithException>

    public init(expression: Expression) {
        super(expression)
        if (expression.GetExprKind() == ExprKind.ALLOCATE) {
            expr = (expression as Allocate).getOrThrow()
            exprE = None
        } else {
            expr = None
            exprE = (expression as AllocateWithException).getOrThrow()
        }
    }

    public init(expression: Allocate) {
        super(expression)
        expr = expression
        exprE = None
    }

    public init(expression: AllocateWithException) {
        super(expression)
        expr = None
        exprE = expression
    }

    public func GetType(): Type {
        if (let Some(allocate) <- expr) {
            return allocate.GetType()
        }
        return exprE.getOrThrow().GetType()
    }
}

public class RawArrayAllocateBase <: ExpressionBase {
    private let expr: Option<RawArrayAllocate>
    private let exprE: Option<RawArrayAllocateWithException>

    public init(expression: Expression) {
        super(expression)
        if (expression.GetExprKind() == ExprKind.RAW_ARRAY_ALLOCATE) {
            expr = (expression as RawArrayAllocate).getOrThrow()
            exprE = None
        } else {
            expr = None
            exprE = (expression as RawArrayAllocateWithException).getOrThrow()
        }
    }

    public init(expression: RawArrayAllocate) {
        super(expression)
        expr = expression
        exprE = None
    }

    public init(expression: RawArrayAllocateWithException) {
        super(expression)
        expr = None
        exprE = expression
    }

    public func GetElementType(): Type {
        if (let Some(allocate) <- expr) {
            return allocate.GetElementType()
        }
        return exprE.getOrThrow().GetElementType()
    }

    public func GetSize(): Value {
        if (let Some(allocate) <- expr) {
            return allocate.GetSize()
        }
        return exprE.getOrThrow().GetSize()
    }
}
