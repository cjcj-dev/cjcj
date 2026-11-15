package interop_generic_contract

import cjcj::chir.*
import std.collection.*

func require(ok: Bool, text: String): Unit {
    if (!ok) { throw Exception(text) }
}

main(): Int64 {
    let builder = CHIRBuilder(CHIRContext())
    let ctx = builder.context
    let pkg = builder.CreatePackage("intrinsic_lift")
    let old = ctx.GetGenericTy("outer_T", "T")
    let fn = builder.CreateFunction(ctx.GetFuncTy(ArrayList<Type>(), ctx.GetUnitTy()),
        "outer", packageName: "intrinsic_lift", genericTypeParams: ArrayList<GenericType>([old]))
    pkg.SetPackageInitFunc(fn)
    pkg.SetPackageLiteralInitFunc(fn)
    let body = builder.CreateBlockGroup(fn)
    fn.InitBody(body)
    let entry = builder.CreateBlock(body)
    body.SetEntryBlock(entry)
    let ret = builder.CreateAllocate(ctx.GetRefTy(ctx.GetUnitTy()), ctx.GetUnitTy(), entry)
    fn.SetReturnValue(ret.GetResult().getOrThrow())
    entry.AppendExpression(ret)
    let lambdaTy = ctx.GetFuncTy(ArrayList<Type>(), ctx.GetCStringTy())
    let lambda = builder.CreateLambda(lambdaTy, lambdaTy, entry,
        identifier: "_CN14intrinsic_lift5outerEL_E")
    let lambdaBody = builder.CreateBlockGroup(fn)
    lambda.InitBody(lambdaBody)
    let block = builder.CreateBlock(lambdaBody)
    lambdaBody.SetEntryBlock(block)
    let ok = builder.CreateBlock(lambdaBody)
    let fail = builder.CreateBlock(lambdaBody)
    let slot = builder.CreateAllocate(ctx.GetRefTy(ctx.GetCStringTy()), ctx.GetCStringTy(), block)
    lambda.SetReturnValue(slot.GetResult().getOrThrow())
    let generic = builder.CreateIntrinsic(ctx.GetCStringTy(),
        IntrisicCallContext(kind: IntrinsicKind.GET_TYPE_FOR_TYPE_PARAMETER,
            instTypeArgs: ArrayList<Type>([old])), block)
    let concrete = builder.CreateIntrinsic(ctx.GetCStringTy(),
        IntrisicCallContext(kind: IntrinsicKind.GET_TYPE_FOR_TYPE_PARAMETER,
            instTypeArgs: ArrayList<Type>([ctx.GetInt64Ty()])), block)
    let exceptional = builder.CreateTryIntrinsic(ctx.GetCStringTy(),
        IntrisicCallContext(kind: IntrinsicKind.GET_TYPE_FOR_TYPE_PARAMETER,
            instTypeArgs: ArrayList<Type>([old])), ok, fail, block)
    block.AppendExpressions(ArrayList<Expression>([slot, generic, concrete, exceptional]))
    for (next in [ok, fail]) {
        next.AppendExpressions(ArrayList<Expression>([
            builder.CreateStore(concrete.GetResult().getOrThrow(), slot.GetResult().getOrThrow(), next),
            builder.CreateExit(None, next)]))
    }
    let saved = builder.CreateGlobalVar(ctx.GetRefTy(lambdaTy), "saved")
    entry.AppendExpressions(ArrayList<Expression>([lambda,
        builder.CreateStore(lambda.GetResult().getOrThrow(), saved, entry), builder.CreateExit(None, entry)]))
    ClosureConversion(builder).RunOnPackage(pkg)
    let lifted = generic.GetTopLevelFunc().getOrThrow()
    require(lifted.IsLambda(), "lifted lambda was not reached")
    let newTy = generic.GetInstantiatedTypeArgs()[0]
    require(concrete.GetInstantiatedTypeArgs()[0] == ctx.GetInt64Ty(), "concrete type changed")
    println("CONCRETE_INTRINSIC_CONTROL_OK")
    require(newTy != old, "INTRINSIC_RETAINED_OUTER_GENERIC")
    require(lifted.GetGenericTypeParams().contains((newTy as GenericType).getOrThrow()),
        "intrinsic has no lifted TypeInfo parameter")
    require(exceptional.GetInstantiatedTypeArgs()[0] == newTy, "TRY_INTRINSIC_RETAINED_OUTER_GENERIC")
    println("LIFTED_INTRINSIC_AND_TRY_PROVIDER_OK concrete=Int64")
    return 0
}
