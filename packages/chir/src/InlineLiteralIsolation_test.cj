package cjcj::chir

import cjcj::option.OptimizationLevel
import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

// Real inline and MergeBlocks worker entries must keep cloned literal users local.
// The old-sharing witness remains frozen at 833d9750. This regression checks
// isolation, not a dynamic overlap or reproduction of the production SIGSEGV.
@Test
class InlineLiteralIsolationTest {
    private func MakeCallee(builder: CHIRBuilder, global: GlobalVar): (Function, Constant) {
        let context = builder.context
        let ty = context.GetInt64Ty()
        let fn = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>([context.GetBoolTy()]), ty), "callee")
        let condition = builder.CreateParameter(context.GetBoolTy(), DebugLocation(), fn)
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let entry = builder.CreateBlock(body)
        body.SetEntryBlock(entry)
        let slot = builder.CreateAllocate(context.GetRefTy(ty), ty, entry)
        fn.SetReturnValue(slot.GetResult().getOrThrow())
        entry.AppendExpression(slot)
        let left = builder.CreateBlock(body)
        let right = builder.CreateBlock(body)
        let join = builder.CreateBlock(body)
        entry.AppendExpression(builder.CreateBranch(condition, left, right, entry))
        for (pred in [left, right]) {
            // Keep each predecessor from being treated as a goto-only block.
            pred.AppendExpression(builder.CreateConstant(ty, IntLiteral(1i64), pred))
            pred.AppendExpression(builder.CreateGoTo(join, pred))
        }
        let constant = builder.CreateConstant(ty, IntLiteral(7i64), join)
        join.AppendExpression(constant)
        join.AppendExpression(builder.CreateLoad(ty, global, join))
        join.AppendExpression(builder.CreateStore(constant.GetResult().getOrThrow(),
            fn.GetReturnValue().getOrThrow(), join))
        join.AppendExpression(builder.CreateExit(None, join))
        join.SetGeneratedFromForIn(true)
        return (fn, constant)
    }

    private func InlineCaller(builder: CHIRBuilder, callee: Function, name: String): Function {
        let context = builder.context
        let ty = context.GetInt64Ty()
        let fn = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>([context.GetBoolTy()]), ty), name)
        let condition = builder.CreateParameter(context.GetBoolTy(), DebugLocation(), fn)
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let block = builder.CreateBlock(body)
        body.SetEntryBlock(block)
        let slot = builder.CreateAllocate(context.GetRefTy(ty), ty, block)
        fn.SetReturnValue(slot.GetResult().getOrThrow())
        block.AppendExpression(slot)
        let call = builder.CreateApply(ty, callee, FuncCallContext(args: ArrayList<Value>([condition])), block)
        block.AppendExpression(call)
        block.AppendExpression(builder.CreateStore(call.GetResult().getOrThrow(),
            fn.GetReturnValue().getOrThrow(), block))
        block.AppendExpression(builder.CreateExit(None, block))
        FunctionInline(builder, OptimizationLevel.O2, false).DoFunctionInline(call, "literal-sharing-diagnostic")
        return fn
    }

    private func CheckLiteralUsers(source: Function, first: Function, second: Function,
        firstCount: Int64, secondCount: Int64): Unit {
        let seen = HashSet<Int64>()
        for ((fn, expected) in [(source, 1i64), (first, firstCount), (second, secondCount)]) {
            var count: Int64 = 0
            for (block in fn.GetBody().getOrThrow().GetBlocks()) {
                for (expr in block.GetExpressions()) {
                    if (let Some(constant) <- (expr as Constant)) {
                        if (!constant.IsIntLit() || constant.GetSignedIntLitVal() != 7i64) { continue }
                        let literal = constant.GetValue()
                        @Expect(literal.IsGlobal(), false)
                        @Expect(seen.contains(literal.nodeId), false)
                        seen.add(literal.nodeId)
                        @Expect(literal.GetUsers().size, 1)
                        for (user in literal.GetUsers()) {
                            @Expect(refEq(user, constant), true)
                            @Expect(refEq(user.GetTopLevelFunc().getOrThrow(), fn), true)
                        }
                        count++
                    }
                }
            }
            @Expect(count, expected)
        }
    }

    @TestCase
    func twoInlineCallersAndBlockCopiesOwnTheirLiterals(): Unit {
        let builder = CHIRBuilder(CHIRContext())
        let _ = builder.CreatePackage("inline_literal_sharing_diagnostic")
        let global = builder.CreateGlobalVar(builder.context.GetRefTy(builder.context.GetInt64Ty()), "global_control")
        let (callee, constant) = MakeCallee(builder, global)
        let first = InlineCaller(builder, callee, "first")
        let second = InlineCaller(builder, callee, "second")
        let literal = constant.GetValue()
        @Expect(literal.IsGlobal(), false)
        @Expect(global.IsGlobal(), true)
        CheckLiteralUsers(callee, first, second, 1, 1)
        @Expect(global.GetUsers().size, 3)

        // RunOnPackage dispatches this same worker body once per function. Keep
        // this regression serial: distinct identity is the invariant needed by
        // the parallel dispatcher, independent of a particular interleaving.
        let firstBuilder = CHIRBuilder(builder.context)
        let secondBuilder = CHIRBuilder(builder.context)
        @Expect(MergeBlocks().RunOnFunction(first, firstBuilder) > 0, true)
        CheckLiteralUsers(callee, first, second, 2, 1)
        @Expect(global.GetUsers().size, 4)
        @Expect(MergeBlocks().RunOnFunction(second, secondBuilder) > 0, true)
        CheckLiteralUsers(callee, first, second, 2, 2)
        @Expect(global.GetUsers().size, 5)
    }
}
