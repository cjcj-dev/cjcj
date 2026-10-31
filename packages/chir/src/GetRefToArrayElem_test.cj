package cjcj::chir

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class GetRefToArrayElemSnapshotTest {
    @TestCase
    public func FieldReadStaysBeforeInterveningCall(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let elementTy = context.GetTupleTy(ArrayList<Type>([context.GetInt64Ty(), context.GetInt64Ty()]))
        let arrayTy = context.GetRefTy(context.GetRawArrayTy(elementTy))
        let fn = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>(), context.GetInt64Ty()), "snapshot")
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let block = builder.CreateBlock(body)
        body.SetEntryBlock(block)
        let array = builder.CreateParameter(arrayTy, DebugLocation(), fn)
        let index = builder.CreateConstant(context.GetInt64Ty(), IntLiteral(0), block)
        let get = builder.CreateIntrinsic(elementTy, IntrisicCallContext(kind: IntrinsicKind.ARRAY_GET_UNCHECKED,
            args: ArrayList<Value>([array, index.GetResult().getOrThrow()])), block)
        let callee = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>([arrayTy]), context.GetUnitTy()), "overwrite")
        let call = builder.CreateApply(context.GetUnitTy(), callee, FuncCallContext(args: ArrayList<Value>([array])), block)
        let field = builder.CreateField(context.GetInt64Ty(), get.GetResult().getOrThrow(), ArrayList<UInt64>([0u64]), block)
        let exit = builder.CreateExit(Some<Value>(field.GetResult().getOrThrow()), block)
        block.AppendExpressions(ArrayList<Expression>([index, get, call, field, exit]))
        @Expect(GetRefToArrayElem.RunOnFunc(fn, builder), 1)
        let result = exit.GetOperand(0).AsLocalVar().getOrThrow().GetExpr().getOrThrow()
        @Expect(result.GetExprKind(), ExprKind.LOAD)
        var loadIndex: Int64 = -1
        var callIndex: Int64 = -1
        let exprs = block.GetExpressions()
        for (i in 0..exprs.size) {
            if (exprs[i].nodeId == result.nodeId) { loadIndex = i }
            if (exprs[i].nodeId == call.nodeId) { callIndex = i }
        }
        @Expect(loadIndex >= 0 && loadIndex < callIndex, true)
        @Expect(get.GetParentBlock().isNone(), true)
    }
    @TestCase
    public func ParallelPackageKeepsBothSnapshotsBeforeWrites(): Unit {
        let ctx = CHIRContext()
        let b = CHIRBuilder(ctx)
        let pkg = b.CreatePackage("parallel_snapshot")
        let tupleTy = ctx.GetTupleTy(ArrayList<Type>([ctx.GetInt64Ty()]))
        let arrayTy = ctx.GetRefTy(ctx.GetRawArrayTy(tupleTy))
        let overwrite = b.CreateFunction(ctx.GetFuncTy(ArrayList<Type>([arrayTy]), ctx.GetUnitTy()), "overwrite")
        let snapshots = ArrayList<(Intrinsic, Exit, Apply)>()
        for (i in 0..2) {
            let fn = b.CreateFunction(ctx.GetFuncTy(ArrayList<Type>([arrayTy]), ctx.GetInt64Ty()), "snapshot${i}")
            let body = b.CreateBlockGroup(fn)
            fn.InitBody(body)
            let block = b.CreateBlock(body)
            body.SetEntryBlock(block)
            let array = b.CreateParameter(arrayTy, DebugLocation(), fn)
            let index = b.CreateConstant(ctx.GetInt64Ty(), IntLiteral(0), block)
            let get = b.CreateIntrinsic(tupleTy, IntrisicCallContext(kind: IntrinsicKind.ARRAY_GET_UNCHECKED,
                args: ArrayList<Value>([array, index.GetResult().getOrThrow()])), block)
            let call = b.CreateApply(ctx.GetUnitTy(), overwrite, FuncCallContext(args: ArrayList<Value>([array])), block)
            let field = b.CreateField(ctx.GetInt64Ty(), get.GetResult().getOrThrow(), ArrayList<UInt64>([0u64]), block)
            let exit = b.CreateExit(Some<Value>(field.GetResult().getOrThrow()), block)
            block.AppendExpressions(ArrayList<Expression>([index, get, call, field, exit]))
            snapshots.add((get, exit, call))
        }
        @Expect(GetRefToArrayElem.RunOnPackage(pkg, b, threadNum: 2), 2)
        for ((get, exit, call) in snapshots) {
            let load = exit.GetOperand(0).AsLocalVar().getOrThrow().GetExpr().getOrThrow()
            @Expect(load.GetExprKind(), ExprKind.LOAD)
            var loadIndex: Int64 = -1
            var callIndex: Int64 = -1
            let expressions = call.GetParentBlock().getOrThrow().GetExpressions()
            for (i in 0..expressions.size) {
                if (expressions[i].nodeId == load.nodeId) { loadIndex = i }
                if (expressions[i].nodeId == call.nodeId) { callIndex = i }
            }
            @Expect(loadIndex >= 0 && loadIndex < callIndex, true)
            @Expect(get.GetParentBlock().isNone(), true)
        }
        @Expect(GetRefToArrayElem.RunOnPackage(pkg, b, threadNum: 2), 0)
    }

}
