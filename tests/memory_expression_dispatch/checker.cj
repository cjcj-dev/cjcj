package memory_dispatch_checker

import std.collection.*
import cjcj::chir.*
import cjcj::option.GlobalOptions

// Construct IR through the product builder; check it through CheckPackage.
main(args: Array<String>): Int64 {
    let mode = args[0]
    let context = CHIRContext()
    let builder = CHIRBuilder(context)
    let pkg = builder.CreatePackage("memory_dispatch_checker")
    let fnTy = context.GetFuncTy(ArrayList<Type>(), context.GetNothingType())
    let caller = builder.CreateFunction(fnTy, "caller", packageName: pkg.GetName())
    let body = builder.CreateBlockGroup(caller)
    caller.InitBody(body)
    let block = builder.CreateBlock(body)
    body.SetEntryBlock(block)
    let intTy = context.GetInt64Ty()
    let refTy = context.GetRefTy(intTy)
    if (mode == "allocate" || mode == "allocate-good" || mode == "load-good") {
        let alloc = builder.CreateAllocate(if (mode == "allocate") { intTy } else { refTy }, intTy, block)
        block.AppendExpression(alloc)
        if (mode == "load-good") {
            block.AppendExpression(builder.CreateLoad(intTy, alloc.GetResult().getOrThrow(), block))
        }
    } else if (mode != "control") {
        let expr: Expression = match (mode) {
            case "load" => builder.CreateLoad(intTy, caller, block)
            case "store" => builder.CreateStore(caller, caller, block)
            case "get-ref" => builder.CreateGetElementRef(refTy, caller, ArrayList<UInt64>([0]), block)
            case "get-name" => builder.CreateGetElementByName(intTy, caller, ArrayList<String>(["field"]), block)
            case "store-ref" => builder.CreateStoreElementRef(caller, caller, ArrayList<UInt64>([0]), block)
            case "store-name" => builder.CreateStoreElementByName(caller, caller, ArrayList<String>(["field"]), block)
            case _ => builder.CreateLoad(intTy, caller, block)
        }
        if (mode == "load" || mode == "store" || mode == "get-ref" || mode == "store-ref") {
            expr.EraseOperands()
        }
        block.AppendExpression(expr)
    }
    block.AppendExpression(builder.CreateExit(None, block))
    let observed = CHIRChecker(pkg, GlobalOptions(), builder).CheckPackage(
        ArrayList<CHIRCheckerRule>([CHIRCheckerRule.CHECK_FUNC_BODY]))
    let expected = mode == "control" || mode == "allocate-good" || mode == "load-good"
    println("TARGET mode=${mode} observed=${observed} expected=${expected}")
    return if (observed == expected) { 0 } else { 1 }
}
