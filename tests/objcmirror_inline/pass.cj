package objcmirror_inline

import std.collection.*
import cjcj::chir.*
import cjcj::option.OptimizationLevel

// Link this fixture against the release CHIR archive; it contains no pass copy.
func observe(name: String, mirror: Bool, noInline: Bool, size: Int64, expected: Int64): Int64 {
    let context = CHIRContext()
    let builder = CHIRBuilder(context)
    let _ = builder.CreatePackage("objcmirror_inline")
    let ty = context.GetFuncTy(ArrayList<Type>(), context.GetUnitTy())
    let callee = builder.CreateFunction(ty, name, srcCodeIdentifier: name)
    if (mirror) { callee.EnableAttr(Attribute.OBJ_C_MIRROR) }
    if (noInline) { callee.EnableAttr(Attribute.NO_INLINE) }
    let body = builder.CreateBlockGroup(callee)
    callee.InitBody(body)
    let block = builder.CreateBlock(body)
    body.SetEntryBlock(block)
    for (i in 0..size) {
        block.AppendExpression(builder.CreateConstant(context.GetInt64Ty(), IntLiteral(i), block))
    }
    block.AppendExpression(builder.CreateExit(None, block))
    let caller = builder.CreateFunction(ty, "caller_" + name)
    let callerBody = builder.CreateBlockGroup(caller)
    caller.InitBody(callerBody)
    let callerBlock = builder.CreateBlock(callerBody)
    callerBody.SetEntryBlock(callerBlock)
    callerBlock.AppendExpression(builder.CreateApply(context.GetUnitTy(), callee, FuncCallContext(), callerBlock))
    callerBlock.AppendExpression(builder.CreateExit(None, callerBlock))
    FunctionInline(builder, OptimizationLevel.O2, false).Run(caller)
    var calls: Int64 = 0
    for (b in callerBody.GetBlocks()) {
        for (e in b.GetExpressions()) {
            if (e.GetExprKind() == ExprKind.APPLY) { calls++ }
        }
    }
    println("ASSERT " + name + " remaining_calls=" + calls.toString() + " expected=" + expected.toString())
    return if (calls == expected) { 0 } else { 1 }
}

main(): Int64 {
    var failures: Int64 = 0
    failures += observe("mirror_over_threshold", true, false, 80, 0)
    failures += observe("ordinary_over_threshold", false, false, 80, 1)
    failures += observe("mirror_no_inline", true, true, 80, 1)
    failures += observe("ordinary_small", false, false, 1, 0)
    println("RESULT failures=" + failures.toString() + " total=4")
    return failures
}
