package cangjie_compiler::chir

import std.collection.*

public class ClosureConversion {
    private let convertedLambdaExpressions: ArrayList<Lambda> = ArrayList<Lambda>()
    private let capturedValues: ArrayList<Value> = ArrayList<Value>()

    public init() {}

    public func RunOnPackage(pkg: Package): Unit {
        for (fn in pkg.GetGlobalFunctions(includePureAbstract: true)) {
            RunOnFunction(fn)
        }
    }

    public func GetConvertedLambdaExpressions(): ArrayList<Lambda> {
        let out = ArrayList<Lambda>()
        for (lambdaExpr in convertedLambdaExpressions) {
            out.add(lambdaExpr)
        }
        return out
    }

    public func GetCapturedValues(): ArrayList<Value> {
        return CopyValueList(capturedValues)
    }

    private func RunOnFunction(fn: Function): Unit {
        if (fn.IsLambda() && fn.GetNumOfParams() == 0) {
            fn.EnableAttr(Attribute.THIN)
        }
        if (let Some(body) <- fn.GetBody()) {
            RunOnBlockGroup(body)
        }
    }

    private func RunOnBlockGroup(body: BlockGroup): Unit {
        for (block in body.GetBlocksRef()) {
            for (expr in block.GetExpressionsRef()) {
                if (let Some(lambdaExpr) <- (expr as Lambda)) {
                    ConvertLambdaExpression(lambdaExpr)
                    if (let Some(lambdaBody) <- lambdaExpr.GetBody()) {
                        RunOnBlockGroup(lambdaBody)
                    }
                } else {
                    for (group in expr.GetBlockGroups()) {
                        RunOnBlockGroup(group)
                    }
                }
            }
        }
    }

    private func ConvertLambdaExpression(lambdaExpr: Lambda): Unit {
        if (!ContainsLambda(convertedLambdaExpressions, lambdaExpr)) {
            convertedLambdaExpressions.add(lambdaExpr)
        }
        let operands = lambdaExpr.GetOperands()
        if (operands.isEmpty()) {
            lambdaExpr.EnableAttr(Attribute.THIN)
            return
        }
        lambdaExpr.EnableAttr(Attribute.BOXED)
        for (operand in operands) {
            if (!ContainsValue(capturedValues, operand)) {
                capturedValues.add(operand)
            }
            if (operand.TestAttr(Attribute.MUT)) {
                operand.EnableAttr(Attribute.BOXED)
            }
        }
    }
}

private func ContainsLambda(values: ArrayList<Lambda>, lambdaExpr: Lambda): Bool {
    for (value in values) {
        if (value.nodeId == lambdaExpr.nodeId) {
            return true
        }
    }
    return false
}
