package cjcj::chir

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class MergeBlocksParallelTest {
    @TestCase
    func clonedLoopBlocksKeepGlobalUsersInTheirOwnFunctions(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let pkg = builder.CreatePackage("parallel_merge_blocks")
        let ty = context.GetInt64Ty()
        let global = builder.CreateGlobalVar(context.GetRefTy(ty), "shared")
        let functions = ArrayList<Function>()
        for (index in 0..2) {
            let fn = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>([context.GetBoolTy()]), ty),
                "branch${index}")
            functions.add(fn)
            let body = builder.CreateBlockGroup(fn)
            fn.InitBody(body)
            let entry = builder.CreateBlock(body)
            body.SetEntryBlock(entry)
            let left = builder.CreateBlock(body)
            let right = builder.CreateBlock(body)
            let join = builder.CreateBlock(body)
            let condition = builder.CreateParameter(context.GetBoolTy(), DebugLocation(), fn)
            entry.AppendExpression(builder.CreateBranch(condition, left, right, entry))
            for (pred in [left, right]) {
                pred.AppendExpression(builder.CreateConstant(ty, IntLiteral(index), pred))
                pred.AppendExpression(builder.CreateGoTo(join, pred))
            }
            let load = builder.CreateLoad(ty, global, join)
            join.AppendExpression(load)
            join.AppendExpression(builder.CreateExit(Some<Value>(load.GetResult().getOrThrow()), join))
            join.SetGeneratedFromForIn(true)
        }
        @Expect(global.GetUsers().size, 2)
        @Expect(MergeBlocks().RunOnPackage(pkg, builder, threadNum: 2) >= 2, true)
        @Expect(global.GetUsers().size, 4)
        for (fn in functions) {
            var count: Int64 = 0
            for (user in global.GetUsers()) {
                if (user.GetTopLevelFunc().getOrThrow().nodeId == fn.nodeId) {
                    count++
                    @Expect(user.GetExprKind(), ExprKind.LOAD)
                    @Expect(user.GetParentBlock().getOrThrow().GetTerminator().getOrThrow().GetExprKind(), ExprKind.EXIT)
                }
            }
            @Expect(count, 2)
        }
        @Expect(MergeBlocks().RunOnPackage(pkg, builder, threadNum: 2), 0)
        @Expect(global.GetUsers().size, 4)
    }
}
