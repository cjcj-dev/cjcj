package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.BinaryExpression
import cangjie_compiler::chir.Constant
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.Apply
import cangjie_compiler::chir.ApplyWithException
import cangjie_compiler::chir.Attribute
import cangjie_compiler::chir.Function
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.UnaryExpression
import cangjie_compiler::chir.Value
import cangjie_compiler::utils.CJC_ASSERT_WITH_MSG

public open class CHIRExprWrapper {
    public let expr: Expression

    public init(expr: Expression) {
        this.expr = expr
    }

    public func GetTopLevelFunc(): Option<Function> {
        return expr.GetTopLevelFunc()
    }

    public func GetExpression(): Expression {
        return expr
    }
}

public class CHIRUnaryExprWrapper <: CHIRExprWrapper {
    public let unaryExpr: UnaryExpression
    public init(expr: UnaryExpression) {
        super(expr)
        unaryExpr = expr
    }
}

public class CHIRBinaryExprWrapper <: CHIRExprWrapper {
    public let binaryExpr: BinaryExpression
    public init(expr: BinaryExpression) {
        super(expr)
        binaryExpr = expr
    }
}

public class CHIRConstantExprWrapper <: CHIRExprWrapper {
    public let constant: Constant
    public init(expr: Constant) {
        super(expr)
        constant = expr
    }
}

public class CHIRApplyWrapper <: CHIRExprWrapper {
    public init(apply: Apply) {
        super(apply)
        CheckCalleeTypeArgsNum()
    }

    public init(applyWithException: ApplyWithException) {
        super(applyWithException)
        CheckCalleeTypeArgsNum()
    }

    public func GetCallee(): Value {
        if (let Some(apply) <- (expr as Apply)) {
            return apply.GetCallee()
        }
        return (expr as ApplyWithException).getOrThrow().GetCallee()
    }

    public func GetArgs(): ArrayList<Value> {
        if (let Some(apply) <- (expr as Apply)) {
            return apply.GetArgs()
        }
        return (expr as ApplyWithException).getOrThrow().GetArgs()
    }

    public func GetInstantiatedTypeArgs(): ArrayList<Type> {
        if (let Some(apply) <- (expr as Apply)) {
            return apply.GetInstantiatedTypeArgs()
        }
        return (expr as ApplyWithException).getOrThrow().GetInstantiatedTypeArgs()
    }

    public func GetThisType(): Option<Type> {
        if (let Some(apply) <- (expr as Apply)) {
            return apply.GetThisType()
        }
        return (expr as ApplyWithException).getOrThrow().GetThisType()
    }

    public func IsCalleeMethod(): Bool {
        if (let Some(calleeFunc) <- GetCallee().AsFunction()) {
            return calleeFunc.IsMemberFunc()
        }
        return false
    }

    public func IsCalleeStatic(): Bool {
        return GetCallee().TestAttr(Attribute.STATIC)
    }

    public func IsCalleeStructInstanceMethod(): Bool {
        if (!IsCalleeMethod() || IsCalleeStatic()) {
            return false
        }
        let calleeFunc = GetCallee().AsFunction().getOrThrow()
        let outer = calleeFunc.GetOuterDeclaredOrExtendedDef() ?? return false
        return outer.IsStruct()
    }

    public func IsCalleeStructMutOrCtorMethod(): Bool {
        let calleeFunc = GetCallee().AsFunction().getOrThrow()
        return IsCalleeStructInstanceMethod() &&
            (GetCallee().TestAttr(Attribute.MUT) || calleeFunc.IsConstructor())
    }

    public func GetThisParam(): Option<Value> {
        if (IsCalleeMethod() && !IsCalleeStatic()) {
            return GetArgs()[0]
        }
        return None
    }

    private func CheckCalleeTypeArgsNum(): Unit {
        CJC_ASSERT_WITH_MSG(GetInstantiatedTypeArgs().size == GetCalleeTypeArgsNum(),
            "Incorrect ApplyExpr from CHIR, type arguments are missing.")
    }

    private func GetCalleeTypeArgsNum(): Int64 {
        if (let Some(calleeFunc) <- GetCallee().AsFunction()) {
            return calleeFunc.GetGenericTypeParams().size
        }
        return 0
    }
}
