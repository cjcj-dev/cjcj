package other_expression_dispatch_checker

import std.collection.*
import cjcj::chir.*
import cjcj::option.GlobalOptions

// Inputs only: all validation comes from the linked release CHIR archive.
main(args: Array<String>): Int64 {
    let mode = args[0]
    let context = CHIRContext()
    let builder = CHIRBuilder(context)
    let pkg = builder.CreatePackage("other_expression_dispatch_checker")
    let ty = context.GetInt64Ty()
    let fnTy = context.GetFuncTy(ArrayList<Type>(), context.GetNothingType())
    let caller = builder.CreateFunction(fnTy, "caller", packageName: pkg.GetName())
    let body = builder.CreateBlockGroup(caller)
    caller.InitBody(body)
    let block = builder.CreateBlock(body)
    body.SetEntryBlock(block)
    let expr: Expression = match (mode) {
        case "constant" => builder.CreateConstant(ty, IntLiteral(1i64), block)
        case "debug" => builder.CreateDebug(ty, caller, "source", block)
        case "tuple" => builder.CreateTuple(ty, ArrayList<Value>(), block)
        case "field" => builder.CreateField(ty, caller, ArrayList<UInt64>(), block)
        case "field-by-name" => builder.CreateFieldByName(ty, caller, ArrayList<String>(["member"]), block)
        case "apply" => builder.CreateApply(ty, caller, FuncCallContext(), block)
        case "invoke" => builder.CreateInvoke(ty, InvokeCallContext(caller, caller, FuncCallContext()), block)
        case "invoke-static" => builder.CreateInvokeStatic(ty, InvokeCallContext(caller, caller, FuncCallContext()), block)
        case "instanceof" => builder.CreateInstanceOf(ty, caller, ty, block)
        case "class-cast" => builder.CreateClassStaticCast(ty, caller, block)
        case "numeric-cast" => builder.CreateNumericCast(ty, caller, block, overflowStrategy: OverflowStrategy.NA)
        case "exception" => builder.CreateGetException(ty, block)
        case "spawn" => builder.CreateSpawn(ty, caller, block)
        case "raw-allocate" => builder.CreateRawArrayAllocate(ty, ty, caller, block)
        case "raw-literal" => builder.CreateRawArrayLiteralInit(ty, caller, ArrayList<Value>(), block)
        case "raw-value" => builder.CreateRawArrayInitByValue(ty, caller, caller, caller, block)
        case "varray" => builder.CreateVArray(ty, ArrayList<Value>(), block)
        case "varray-builder" => builder.CreateVArrayBuilder(ty, caller, caller, caller, block)
        case "intrinsic" => builder.CreateIntrinsic(ty, IntrisicCallContext(), block)
        case "box" => builder.CreateBox(ty, caller, block)
        case "unbox" => builder.CreateUnBoxToValue(ty, caller, block)
        case "generic" => builder.CreateCastToGeneric(ty, caller, block)
        case "concrete" => builder.CreateCastToConcrete(ty, caller, block)
        case "instantiate" => builder.CreateGetInstantiateValue(ty, caller, ArrayList<Type>(), block)
        case "unbox-ref" => builder.CreateUnBoxToRef(ty, caller, block)
        case "rtti" => builder.CreateGetRTTI(ty, caller, block)
        case "rtti-static" => builder.CreateGetRTTIStatic(ty, ty, block)
        case "unknown" => builder.CreateExpression(ExprKind.INVALID, Some(ty), ArrayList<Value>(), block)
        case "constant-good" => builder.CreateConstant(ty, IntLiteral(1i64), block)
        case _ => throw Exception("unknown test mode")
    }
    // Remove operands only where the target checker owns an operand-count check.
    if (mode != "field-by-name" && mode != "exception" && mode != "varray" &&
        mode != "intrinsic" && mode != "rtti-static" && mode != "constant-good") {
        expr.EraseOperands()
    }
    expr.GetResult().getOrThrow().SetIdentifier("%route")
    block.AppendExpression(expr)
    block.AppendExpression(builder.CreateExit(None, block))
    let observed = CHIRChecker(pkg, GlobalOptions(), builder).CheckPackage(
        ArrayList<CHIRCheckerRule>([CHIRCheckerRule.CHECK_FUNC_BODY]))
    let expected = mode == "class-cast" || mode == "numeric-cast" ||
        mode == "unknown" || mode == "constant-good"
    println("TARGET mode=${mode} observed=${observed} expected=${expected}")
    return if (observed == expected) { 0 } else { 1 }
}
