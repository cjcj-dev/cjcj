package cangjie_compiler::ast

public class IfAvailableExpr <: Expr {
    private var arg: Option<FuncArg> = None
    private var lambda1: Option<LambdaExpr> = None
    private var lambda2: Option<LambdaExpr> = None

    public init() {
        super(ASTKind.IF_AVAILABLE_EXPR)
    }

    public init(namedArg: FuncArg, lambdaArg1: LambdaExpr, lambdaArg2: LambdaExpr) {
        super(ASTKind.IF_AVAILABLE_EXPR)
        arg = namedArg
        lambda1 = lambdaArg1
        lambda2 = lambdaArg2
    }

    public func GetArg(): Option<FuncArg> {
        return arg
    }

    public func SetArg(namedArg: FuncArg): Unit {
        arg = namedArg
    }

    public func GetLambda1(): Option<LambdaExpr> {
        return lambda1
    }

    public func SetLambda1(lambdaArg: LambdaExpr): Unit {
        lambda1 = lambdaArg
    }

    public func GetLambda2(): Option<LambdaExpr> {
        return lambda2
    }

    public func SetLambda2(lambdaArg: LambdaExpr): Unit {
        lambda2 = lambdaArg
    }

    public override func ToString(): String {
        let first = if (let Some(value) <- arg) { value.ToString() } else { "" }
        let second = if (let Some(value) <- lambda1) { value.ToString() } else { "" }
        let third = if (let Some(value) <- lambda2) { value.ToString() } else { "" }
        return "@IfAvailable(" + first + ", " + second + ", " + third + ")"
    }
}
