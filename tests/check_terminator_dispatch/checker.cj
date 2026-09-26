package terminator_dispatch_checker

import std.collection.*
import cjcj::chir.*
import cjcj::option.GlobalOptions

// Construct IR with the real builder, then observe the public product checker.
main(args: Array<String>): Int64 {
    let mode = args[0]
    let context = CHIRContext()
    let builder = CHIRBuilder(context)
    let pkg = builder.CreatePackage("terminator_dispatch_checker")
    let fnTy = context.GetFuncTy(ArrayList<Type>(), context.GetNothingType())
    let caller = builder.CreateFunction(fnTy, "caller", packageName: pkg.GetName())
    let body = builder.CreateBlockGroup(caller)
    caller.InitBody(body)
    let block = builder.CreateBlock(body)
    body.SetEntryBlock(block)
    let success = builder.CreateBlock(body)
    let failure = builder.CreateBlock(body)
    success.AppendExpression(builder.CreateExit(None, success))
    failure.AppendExpression(builder.CreateExit(None, failure))
    let ty = context.GetInt64Ty()
    let call = FuncCallContext()
    let invoke = InvokeCallContext(caller, caller, call)
    let binaryKinds = HashMap<String, ExprKind>([
        ("add", ExprKind.ADD), ("sub", ExprKind.SUB), ("mul", ExprKind.MUL),
        ("div", ExprKind.DIV), ("mod", ExprKind.MOD), ("exp", ExprKind.EXP),
        ("lshift", ExprKind.LSHIFT), ("rshift", ExprKind.RSHIFT)
    ])
    let expr: Expression = if (let Some(kind) <- binaryKinds.get(mode)) {
        builder.CreateTryBinaryExpression(ty, kind, caller, caller, success, failure, block)
    } else {
        match (mode) {
            case "goto" => builder.CreateGoTo(success, block)
            case "exit" => builder.CreateExit(Some(caller), block)
            case "raise" => builder.CreateRaiseException(caller, block)
            case "branch" => builder.CreateBranch(caller, success, failure, block)
            case "multibranch" => builder.CreateMultiBranch(caller, success,
                ArrayList<UInt64>([0]), ArrayList<Block>([failure]), block)
            case "apply" => builder.CreateTryApply(ty, caller, call, success, failure, block)
            case "invoke" => builder.CreateTryInvoke(ty, invoke, success, failure, block)
            case "invokestatic" => builder.CreateTryInvokeStatic(ty, invoke, success, failure, block)
            case "neg" => builder.CreateTryUnaryExpression(ty, ExprKind.NEG, caller, success, failure, block)
            case "spawn" => builder.CreateTrySpawn(ty, caller, success, failure, block)
            case "numeric" => builder.CreateTryNumericCast(ty, caller, success, failure, block)
            case "intrinsic" => builder.CreateTryIntrinsic(ty, IntrisicCallContext(), success, failure, block)
            case "allocate" => builder.CreateTryAllocate(ty, ty, success, failure, block)
            case "rawarray" => builder.CreateTryRawArrayAllocate(ty, ty, caller, success, failure, block)
            case "control" => builder.CreateExit(None, block)
            case _ => throw IllegalArgumentException("unknown case ${mode}")
        }
    }
    // Keep result metadata. Erase operands and successor links together so earlier
    // block/predecessor checks cannot mask the selected callback's diagnostic.
    if (mode != "exit" && mode != "numeric" && mode != "control") {
        expr.EraseOperands()
    }
    block.AppendExpression(expr)
    let observed = CHIRChecker(pkg, GlobalOptions(), builder).CheckPackage(
        ArrayList<CHIRCheckerRule>([CHIRCheckerRule.CHECK_FUNC_BODY]))
    let expected = mode == "numeric" || mode == "control"
    println("TARGET mode=${mode} observed=${observed} expected=${expected}")
    return if (observed == expected) { 0 } else { 1 }
}
