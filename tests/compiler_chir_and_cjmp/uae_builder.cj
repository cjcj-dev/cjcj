package uae_builder

import std.collection.*
import cjcj::chir.*
import cjcj::option.GlobalOptions

// Construct the exact only-written TryAllocate shape that a source constructor
// cannot express: the allocation result has one Store user and no TryApply user.
main(): Int64 {
    let context = CHIRContext()
    let builder = CHIRBuilder(context)
    let pkg = builder.CreatePackage("uae_builder")
    let fnTy = context.GetFuncTy(ArrayList<Type>(), context.GetUnitTy())
    let fn = builder.CreateFunction(fnTy, "onlyWritten", packageName: pkg.GetName())
    let body = builder.CreateBlockGroup(fn)
    fn.InitBody(body)
    let block = builder.CreateBlock(body)
    body.SetEntryBlock(block)
    let success = builder.CreateBlock(body)
    let failure = builder.CreateBlock(body)
    success.AppendExpression(builder.CreateExit(None, success))
    failure.AppendExpression(builder.CreateExit(None, failure))
    let term = builder.CreateTryAllocate(context.GetInt64Ty(), context.GetInt64Ty(), success, failure, block)
    block.AppendExpression(term)
    let value = builder.CreateConstant(context.GetInt64Ty(), IntLiteral(42), success).GetResult().getOrThrow()
    value.GetExpr().getOrThrow().MoveBefore(success.GetExpressions()[0])
    let store = builder.CreateStore(value, term.GetResult().getOrThrow(), success)
    store.MoveBefore(success.GetExpressions()[0])
    UselessAllocateElimination.RunOnPackage(pkg, builder: Some(builder))
    let removed = block.GetExpressions().size == 1 && block.GetExpressions()[0].GetExprKind() == ExprKind.GOTO
    println("UAE_ONLY_WRITTEN_REMOVED=${removed}")
    return if (removed) { 0 } else { 1 }
}
