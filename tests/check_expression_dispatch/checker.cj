package expression_dispatch_checker

import std.collection.*
import cjcj::chir.*
import cjcj::option.GlobalOptions

// Malformed IR is intentional: observe the real release CheckPackage result.
main(args: Array<String>): Int64 {
    let mode = args[0]
    let context = CHIRContext()
    let builder = CHIRBuilder(context)
    let pkg = builder.CreatePackage("expression_dispatch_checker")
    let fnTy = context.GetFuncTy(ArrayList<Type>(), context.GetNothingType())
    let caller = builder.CreateFunction(fnTy, "caller", packageName: pkg.GetName())
    let body = builder.CreateBlockGroup(caller)
    caller.InitBody(body)
    let block = builder.CreateBlock(body)
    body.SetEntryBlock(block)
    if (mode == "unary" || mode == "binary" || mode == "memory") {
        let kind = if (mode == "unary") { ExprKind.NEG }
            else if (mode == "binary") { ExprKind.ADD } else { ExprKind.LOAD }
        let expr: Expression = if (mode == "unary") {
            builder.CreateUnaryExpression(kind, context.GetInt64Ty(), caller, block)
        } else if (mode == "binary") {
            builder.CreateBinaryExpression(kind, context.GetInt64Ty(), caller, caller, block)
        } else {
            builder.CreateExpression(kind, Some(context.GetInt64Ty()), ArrayList<Value>(), block)
        }
        expr.EraseOperands()
        expr.GetResult().getOrThrow().SetIdentifier("%route")
        block.AppendExpression(expr)
    }
    if (mode == "lambda" || mode == "lambda-good") {
        let expr = builder.CreateLambda(fnTy, fnTy, block, isLocalFunc: true,
            identifier: if (mode == "lambda") { "" } else { "inner" }, srcCodeIdentifier: "inner")
        expr.GetResult().getOrThrow().SetIdentifier("%lambda")
        let innerBody = builder.CreateBlockGroup(caller)
        expr.InitBody(innerBody)
        let innerBlock = builder.CreateBlock(innerBody)
        innerBody.SetEntryBlock(innerBlock)
        innerBlock.AppendExpression(builder.CreateExit(None, innerBlock))
        block.AppendExpression(expr)
    }
    block.AppendExpression(builder.CreateExit(if (mode == "exit") { Some(caller) } else { None }, block))
    let observed = CHIRChecker(pkg, GlobalOptions(), builder).CheckPackage(
        ArrayList<CHIRCheckerRule>([CHIRCheckerRule.CHECK_FUNC_BODY]))
    let expected = mode == "control" || mode == "lambda-good"
    println("TARGET mode=${mode} observed=${observed} expected=${expected}")
    return if (observed == expected) { 0 } else { 1 }
}
