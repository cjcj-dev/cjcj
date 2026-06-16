package cangjie_compiler::codegen

import cangjie_compiler::chir.BinaryExpression
import cangjie_compiler::chir.Constant
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.Function
import cangjie_compiler::chir.UnaryExpression

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
