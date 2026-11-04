package cjcj::chir

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

private class UsersMultiplicityFixture {
    public let builder: CHIRBuilder
    public let fn: Function
    public let block: Block
    public let callee: Function
    public let oldValue: Value
    public let newValue: Value
    public let replacement: Value
    public let globalValue: GlobalVar

    public init() {
        builder = CHIRBuilder(CHIRContext())
        let ctx = builder.context
        let valueTy = ctx.GetInt64Ty()
        let _ = builder.CreatePackage("users.multiplicity")
        fn = builder.CreateFunction(ctx.GetFuncTy(ArrayList<Type>(), ctx.GetUnitTy()), "users.fixture")
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        block = builder.CreateBlock(body)
        body.SetEntryBlock(block)
        callee = builder.CreateFunction(ctx.GetFuncTy(
            ArrayList<Type>([valueTy, valueTy, valueTy, ctx.GetRefTy(valueTy)]), ctx.GetUnitTy()), "users.callee")
        oldValue = builder.CreateParameter(valueTy, DebugLocation(), fn)
        newValue = builder.CreateParameter(valueTy, DebugLocation(), fn)
        replacement = builder.CreateParameter(valueTy, DebugLocation(), fn)
        globalValue = builder.CreateGlobalVar(ctx.GetRefTy(valueTy), "users.global")
    }

    public func CreateApply(args: ArrayList<Value>): Apply {
        let callArgs = ArrayList<Value>()
        for (arg in args) { callArgs.add(arg) }
        // Match the callee's reference-typed global formal in every fixture call.
        callArgs.add(globalValue)
        let call = builder.CreateApply(builder.context.GetUnitTy(), callee,
            FuncCallContext(args: callArgs), block)
        block.AppendExpression(call)
        return call
    }
}

@Test
class UsersMultiplicityTest {
    @TestCase
    func bulkReplaceCountsEveryRepeatedValueOccurrence(): Unit {
        let f = UsersMultiplicityFixture()
        let call = f.CreateApply(ArrayList<Value>([f.oldValue, f.oldValue]))
        @Expect(f.oldValue.GetUsers().size, 2)

        call.ReplaceOperand(f.oldValue, f.newValue)

        @Expect(f.oldValue.GetUsers().isEmpty(), true)
        @Expect(f.newValue.GetUsers().size, 2)
        @Expect(call.GetOperand(1).nodeId, f.newValue.nodeId)
        @Expect(call.GetOperand(2).nodeId, f.newValue.nodeId)

        f.newValue.ReplaceWith(f.replacement)
        @Expect(f.newValue.GetUsers().isEmpty(), true)
        @Expect(f.replacement.GetUsers().size, 2)
    }

    @TestCase
    func bulkReplaceAddsToExistingUserOccurrences(): Unit {
        let f = UsersMultiplicityFixture()
        let call = f.CreateApply(ArrayList<Value>([f.oldValue, f.newValue, f.oldValue]))
        @Expect(f.oldValue.GetUsers().size, 2)
        @Expect(f.newValue.GetUsers().size, 1)

        call.ReplaceOperand(f.oldValue, f.newValue)

        @Expect(f.oldValue.GetUsers().isEmpty(), true)
        @Expect(f.newValue.GetUsers().size, 3)
        call.EraseOperands()
        @Expect(f.newValue.GetUsers().isEmpty(), true)
        @Expect(call.GetNumOfOperands(), 0)
    }

    @TestCase
    func indexReplaceRemovesExactlyOneRepeatedOccurrence(): Unit {
        let f = UsersMultiplicityFixture()
        let call = f.CreateApply(ArrayList<Value>([f.oldValue, f.oldValue]))

        call.ReplaceOperand(1, f.newValue)
        @Expect(f.oldValue.GetUsers().size, 1)
        @Expect(f.newValue.GetUsers().size, 1)

        call.ReplaceOperand(1, f.replacement)
        @Expect(f.oldValue.GetUsers().size, 1)
        @Expect(f.newValue.GetUsers().isEmpty(), true)
        @Expect(f.replacement.GetUsers().size, 1)

        call.ReplaceOperand(2, f.replacement)
        @Expect(f.oldValue.GetUsers().isEmpty(), true)
        @Expect(f.replacement.GetUsers().size, 2)
    }

    @TestCase
    func sameValueAndMissingValueAreNoOps(): Unit {
        let f = UsersMultiplicityFixture()
        let call = f.CreateApply(ArrayList<Value>([f.oldValue, f.oldValue]))

        call.ReplaceOperand(f.oldValue, f.oldValue)
        @Expect(f.oldValue.GetUsers().size, 2)
        call.ReplaceOperand(f.newValue, f.replacement)
        @Expect(f.oldValue.GetUsers().size, 2)
        @Expect(f.newValue.GetUsers().isEmpty(), true)
        @Expect(f.replacement.GetUsers().isEmpty(), true)
    }

    @TestCase
    func globalUsersKeepOccurrenceAndEraseContract(): Unit {
        let f = UsersMultiplicityFixture()
        @Expect(f.globalValue.GetType().getOrThrow().nodeId,
            f.builder.context.GetRefTy(f.builder.context.GetInt64Ty()).nodeId)
        let call = f.CreateApply(ArrayList<Value>([f.globalValue, f.globalValue]))
        @Expect(f.globalValue.GetUsers().size, 3)

        call.ReplaceOperand(1, f.newValue)
        @Expect(f.globalValue.GetUsers().size, 2)
        @Expect(f.newValue.GetUsers().size, 1)
        call.EraseOperands()
        @Expect(f.globalValue.GetUsers().isEmpty(), true)
        @Expect(f.newValue.GetUsers().isEmpty(), true)
    }

    @TestCase
    func successorRelationsAreRemovedAsOneBlockEdge(): Unit {
        let builder = CHIRBuilder(CHIRContext())
        let ctx = builder.context
        let pkg = builder.CreatePackage("users.block_edges")
        let ty = ctx.GetInt64Ty()
        let fn = builder.CreateFunction(ctx.GetFuncTy(ArrayList<Type>(), ctx.GetUnitTy()), "block.edges")
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let source = builder.CreateBlock(body)
        let target = builder.CreateBlock(body)
        let replacement = builder.CreateBlock(body)
        body.SetEntryBlock(source)
        let value = builder.CreateConstant(ty, IntLiteral(1), source)
        let term = builder.CreateTryBinaryExpression(ty, ExprKind.ADD,
            value.GetResult().getOrThrow(), value.GetResult().getOrThrow(), target, target, source)
        source.AppendExpressions(ArrayList<Expression>([value, term]))
        @Expect(target.GetPredecessors().size, 1)

        term.ReplaceOperand(target, replacement)
        @Expect(target.GetPredecessors().isEmpty(), true)
        @Expect(replacement.GetPredecessors().size, 1)
        term.DetachFromBlockOnly()
        @Expect(replacement.GetPredecessors().isEmpty(), true)
        term.EraseOperands()
        @Expect(replacement.GetPredecessors().isEmpty(), true)
        @Expect(term.GetNumOfOperands(), 0)
        let term2 = builder.CreateTryBinaryExpression(ty, ExprKind.ADD,
            value.GetResult().getOrThrow(), value.GetResult().getOrThrow(), replacement, replacement, source)
        source.AppendExpression(term2)
        @Expect(replacement.GetPredecessors().size, 1)
        fn.DestroyFuncBody()
        @Expect(replacement.GetPredecessors().isEmpty(), true)
        @Expect(pkg.GetGlobalFuncsWithBody().size, 1)
    }

    @TestCase
    func copyBlockKeepsRepeatedLocalUsersThroughDestroy(): Unit {
        let builder = CHIRBuilder(CHIRContext())
        let ctx = builder.context
        let pkg = builder.CreatePackage("users.copy_block")
        let ty = ctx.GetInt64Ty()
        let fn = builder.CreateFunction(ctx.GetFuncTy(ArrayList<Type>(), ctx.GetUnitTy()), "copy.block")
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let entry = builder.CreateBlock(body)
        let left = builder.CreateBlock(body)
        let right = builder.CreateBlock(body)
        let join = builder.CreateBlock(body)
        body.SetEntryBlock(entry)
        let condition = builder.CreateParameter(ctx.GetBoolTy(), DebugLocation(), fn)
        entry.AppendExpression(builder.CreateBranch(condition, left, right, entry))
        left.AppendExpression(builder.CreateConstant(ty, IntLiteral(1), left))
        left.AppendExpression(builder.CreateGoTo(join, left))
        right.AppendExpression(builder.CreateConstant(ty, IntLiteral(2), right))
        right.AppendExpression(builder.CreateGoTo(join, right))
        @Expect(left.GetExpressions().size > 1, true)
        @Expect(right.GetExpressions().size > 1, true)
        let callee = builder.CreateFunction(ctx.GetFuncTy(ArrayList<Type>([ty, ty]), ty), "copy.callee")
        let constant = builder.CreateConstant(ty, IntLiteral(7), join)
        let call = builder.CreateApply(ty, callee, FuncCallContext(args: ArrayList<Value>([
            constant.GetResult().getOrThrow(), constant.GetResult().getOrThrow()])), join)
        join.AppendExpressions(ArrayList<Expression>([constant, call, builder.CreateExit(None, join)]))
        join.SetGeneratedFromForIn(true)
        @Expect(constant.GetResult().getOrThrow().GetUsers().size, 2)

        @Expect(MergeBlocks().RunOnFunction(fn, CHIRBuilder(ctx)) > 0, true)
        var repeatedCalls: Int64 = 0
        let repeatedValues = ArrayList<Value>()
        for (block in body.GetBlocks()) {
            for (expr in block.GetExpressions()) {
                if (expr.GetExprKind() == ExprKind.APPLY) {
                    let lhs = expr.GetOperand(1)
                    let rhs = expr.GetOperand(2)
                    @Expect(lhs.nodeId, rhs.nodeId)
                    @Expect(lhs.GetUsers().size, 2)
                    for (user in lhs.GetUsers()) {
                        @Expect(refEq(user, expr), true)
                    }
                    repeatedValues.add(lhs)
                    repeatedCalls++
                }
            }
        }
        @Expect(repeatedCalls, 2)
        @Expect(repeatedValues[0].nodeId != repeatedValues[1].nodeId, true)

        fn.DestroyFuncBody()
        for (value in repeatedValues) {
            @Expect(value.GetUsers().isEmpty(), true)
        }
    }
}
