package cjcj::chir

import cjcj::basic.Linkage as BasicLinkage
import cjcj::option.OptimizationLevel
import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

// Pipeline-independent ownership unit test using real inline and MergeBlocks entries.
// Normal RulesChecking clears for-in flags before inline, and Annotation.Clone
// resets this flag. Explicitly mark the actual caller block after inline below.
// This checks literal isolation, not production reachability or the SIGSEGV.
@Test
class InlineLiteralIsolationTest {
    @TestCase
    func completeThrowKeepsCallAndExceptionHandler(): Unit {
        let builder = CHIRBuilder(CHIRContext())
        let _ = builder.CreatePackage("throw_boundary")
        let ctx = builder.context
        let owner = builder.CreateClass(DebugLocation(), "Failure", "Failure", "throw_boundary", true, false)
        let clsTy = ctx.GetClassTy(owner, ArrayList<Type>())
        owner.SetType(clsTy)
        let exceptionTy = ctx.GetRefTy(clsTy)
        let nothing = ctx.GetNothingType()
        let helper = builder.CreateFunction(ctx.GetFuncTy(ArrayList<Type>([exceptionTy]), nothing), "fail")
        let exception = builder.CreateParameter(exceptionTy, DebugLocation(), helper)
        let helperBody = builder.CreateBlockGroup(helper)
        helper.InitBody(helperBody)
        let throwing = builder.CreateBlock(helperBody)
        // Translator emits a parameter entry followed by the source body. With
        // -g, MergeBlocks retains this GoTo; the direct-entry-only rule missed it.
        let parameterEntry = builder.CreateBlock(helperBody)
        helperBody.SetEntryBlock(parameterEntry)
        parameterEntry.AppendExpression(builder.CreateGoTo(throwing, parameterEntry))
        throwing.AppendExpression(builder.CreateRaiseException(exception, throwing))

        let caller = builder.CreateFunction(ctx.GetFuncTy(ArrayList<Type>([exceptionTy]), nothing), "caller")
        let arg = builder.CreateParameter(exceptionTy, DebugLocation(), caller)
        let body = builder.CreateBlockGroup(caller)
        caller.InitBody(body)
        let entry = builder.CreateBlock(body)
        body.SetEntryBlock(entry)
        let call = builder.CreateApply(nothing, helper, FuncCallContext(args: ArrayList<Value>([arg])), entry)
        entry.AppendExpressions(ArrayList<Expression>([call, builder.CreateExit(None, entry)]))
        let pass = FunctionInline(builder, OptimizationLevel.O2, false)
        // Visit the caller first: protection must not depend on call-graph order.
        pass.Run(caller)
        @Expect(refEq(call.GetParentBlock().getOrThrow(), entry), true)
        @Expect(entry.GetExpressions().contains(call), true)
        @Expect(helper.TestAttr(Attribute.NO_INLINE), true)
        @Expect(caller.TestAttr(Attribute.NO_INLINE), false)

        let caught = builder.CreateFunction(ctx.GetFuncTy(ArrayList<Type>([exceptionTy]), ctx.GetVoidTy()), "caught")
        let caughtArg = builder.CreateParameter(exceptionTy, DebugLocation(), caught)
        let caughtBody = builder.CreateBlockGroup(caught)
        caught.InitBody(caughtBody)
        let tryBlock = builder.CreateBlock(caughtBody)
        caughtBody.SetEntryBlock(tryBlock)
        let success = builder.CreateBlock(caughtBody)
        let handler = builder.CreateBlock(caughtBody)
        let invoke = builder.CreateTryApply(nothing, helper, FuncCallContext(args: ArrayList<Value>([caughtArg])),
            success, handler, tryBlock)
        tryBlock.AppendExpression(invoke)
        success.AppendExpression(builder.CreateExit(None, success))
        handler.AppendExpression(builder.CreateExit(None, handler))
        pass.Run(helper)
        pass.Run(caught)
        @Expect(refEq(invoke.GetSuccessBlock(), success), true)
        @Expect(refEq(invoke.GetErrorBlock(), handler), true)
        @Expect(refEq(throwing.GetTerminator().getOrThrow().GetParentBlock().getOrThrow(), throwing), true)
        let locallyCaught = builder.CreateFunction(ctx.GetFuncTy(ArrayList<Type>([exceptionTy]), nothing),
            "locallyCaught")
        let localArg = builder.CreateParameter(exceptionTy, DebugLocation(), locallyCaught)
        let localBody = builder.CreateBlockGroup(locallyCaught)
        locallyCaught.InitBody(localBody)
        let localEntry = builder.CreateBlock(localBody)
        let localHandler = builder.CreateBlock(localBody)
        localBody.SetEntryBlock(localEntry)
        localEntry.AppendExpression(builder.CreateRaiseException(localArg, localHandler, localEntry))
        localHandler.AppendExpression(builder.CreateGoTo(localHandler, localHandler))
        pass.Run(locallyCaught)
        @Expect(locallyCaught.TestAttr(Attribute.NO_INLINE), false)
    }

    @TestCase
    func returningAndNonThrowingNothingFunctionsKeepTheirPolicy(): Unit {
        let builder = CHIRBuilder(CHIRContext())
        let _ = builder.CreatePackage("throw_boundary_controls")
        let ctx = builder.context
        let leaf = builder.CreateFunction(ctx.GetFuncTy(ArrayList<Type>(), ctx.GetVoidTy()), "leaf")
        let leafBody = builder.CreateBlockGroup(leaf)
        leaf.InitBody(leafBody)
        let leafEntry = builder.CreateBlock(leafBody)
        leafBody.SetEntryBlock(leafEntry)
        leafEntry.AppendExpression(builder.CreateExit(None, leafEntry))
        let caller = builder.CreateFunction(ctx.GetFuncTy(ArrayList<Type>(), ctx.GetVoidTy()), "caller")
        let body = builder.CreateBlockGroup(caller)
        caller.InitBody(body)
        let entry = builder.CreateBlock(body)
        body.SetEntryBlock(entry)
        let call = builder.CreateApply(ctx.GetVoidTy(), leaf, FuncCallContext(args: ArrayList<Value>()), entry)
        entry.AppendExpressions(ArrayList<Expression>([call, builder.CreateExit(None, entry)]))
        let pass = FunctionInline(builder, OptimizationLevel.O2, false)
        pass.Run(caller)
        @Expect(entry.GetExpressions().contains(call), false)
        @Expect(leaf.TestAttr(Attribute.NO_INLINE), false)

        let loop = builder.CreateFunction(ctx.GetFuncTy(ArrayList<Type>(), ctx.GetNothingType()), "loop")
        let loopBody = builder.CreateBlockGroup(loop)
        loop.InitBody(loopBody)
        let loopEntry = builder.CreateBlock(loopBody)
        loopBody.SetEntryBlock(loopEntry)
        let loopBack = builder.CreateBlock(loopBody)
        loopEntry.AppendExpression(builder.CreateGoTo(loopBack, loopEntry))
        loopBack.AppendExpression(builder.CreateGoTo(loopEntry, loopBack))
        pass.Run(loop)
        @Expect(loop.TestAttr(Attribute.NO_INLINE), false)
    }

    // Bodyless callees model ordinary imported message/constructor functions.
    // Outlining must use their existing calls, never import their implementation.
    private func MakeThrowConstruction(builder: CHIRBuilder, name: String, captureTy: Type,
        localHandler: Bool): (Function, Block, Apply) {
        let ctx = builder.context
        let aggregate = ctx.GetTupleTy(ArrayList<Type>([ctx.GetInt64Ty(), ctx.GetInt64Ty()]))
        let owner = builder.CreateClass(DebugLocation(), name + "Failure", name + "Failure", "outline", true, false)
        let clsTy = ctx.GetClassTy(owner, ArrayList<Type>())
        owner.SetType(clsTy)
        let exceptionTy = ctx.GetRefTy(clsTy)
        let message = builder.CreateFunction(ctx.GetFuncTy(ArrayList<Type>([captureTy]), aggregate), name + "Message")
        let ctor = builder.CreateFunction(ctx.GetFuncTy(ArrayList<Type>([exceptionTy, aggregate]), exceptionTy),
            name + "Ctor")
        ctor.SetFuncKind(FuncKind.CLASS_CONSTRUCTOR)
        let caller = builder.CreateFunction(ctx.GetFuncTy(ArrayList<Type>([ctx.GetBoolTy(), captureTy]),
            ctx.GetVoidTy()), name)
        let condition = builder.CreateParameter(ctx.GetBoolTy(), DebugLocation(), caller)
        let capture = builder.CreateParameter(captureTy, DebugLocation(), caller)
        let body = builder.CreateBlockGroup(caller)
        caller.InitBody(body)
        let entry = builder.CreateBlock(body)
        body.SetEntryBlock(entry)
        let cold = builder.CreateBlock(body)
        let normal = builder.CreateBlock(body)
        entry.AppendExpression(builder.CreateBranch(condition, cold, normal, entry))
        normal.AppendExpression(builder.CreateExit(None, normal))
        let messageCall = builder.CreateApply(aggregate, message, FuncCallContext(args: ArrayList<Value>([capture])), cold)
        let allocation = builder.CreateAllocate(exceptionTy, clsTy, cold)
        let ctorCall = builder.CreateApply(exceptionTy, ctor, FuncCallContext(args: ArrayList<Value>([
            allocation.GetResult().getOrThrow(), messageCall.GetResult().getOrThrow()])), cold)
        cold.AppendExpressions(ArrayList<Expression>([messageCall, allocation, ctorCall]))
        if (localHandler) {
            cold.AppendExpression(builder.CreateRaiseException(ctorCall.GetResult().getOrThrow(), normal, cold))
        } else {
            cold.AppendExpression(builder.CreateRaiseException(ctorCall.GetResult().getOrThrow(), cold))
        }
        return (caller, cold, messageCall)
    }

    @TestCase
    func completeConstructionOwnsAggregateInOutlinedFrame(): Unit {
        let builder = CHIRBuilder(CHIRContext())
        let _ = builder.CreatePackage("outline")
        let (caller, cold, message) = MakeThrowConstruction(builder, "guarded", builder.context.GetInt64Ty(), false)
        let captured = message.GetArgs()[0]
        let oldExpressions = cold.GetExpressions()
        let oldPredecessors = cold.GetPredecessors()
        let pass = FunctionInline(builder, OptimizationLevel.O2, false)
        pass.Run(caller)
        @Assert(cold.GetExpressions().size == 2)
        let call = (cold.GetExpressions()[0] as Apply).getOrThrow()
        let helper = call.GetCallee().AsFunction().getOrThrow()
        @Expect(helper.TestAttr(Attribute.NO_INLINE), true)
        @Expect(helper.GetLinkTypeInfo() == BasicLinkage.INTERNAL, true)
        @Expect(helper.GetReturnType().getOrThrow().IsNothing(), true)
        // The same Frozen specialization may be emitted in another package;
        // its generated helper must not collide after parallel codegen split.
        let otherBuilder = CHIRBuilder(CHIRContext())
        let _ = otherBuilder.CreatePackage("other_outline")
        let (otherCaller, otherCold, _) = MakeThrowConstruction(otherBuilder, "guarded",
            otherBuilder.context.GetInt64Ty(), false)
        FunctionInline(otherBuilder, OptimizationLevel.O2, false).Run(otherCaller)
        let otherCall = (otherCold.GetExpressions()[0] as Apply).getOrThrow()
        let otherHelper = otherCall.GetCallee().AsFunction().getOrThrow()
        @Expect(helper.GetIdentifier() != otherHelper.GetIdentifier(), true)
        @Expect(call.GetArgs().size, 1)
        @Expect(refEq(call.GetArgs()[0], captured), true)
        @Expect(cold.GetTerminator().getOrThrow().GetExprKind() == ExprKind.EXIT, true)
        @Expect(cold.GetPredecessors().size, oldPredecessors.size)
        let cloned = helper.GetBody().getOrThrow().GetEntryBlock().getOrThrow().GetExpressions()
        @Expect(cloned.size, 4)
        @Expect(cloned[1].GetExprKind() == ExprKind.ALLOCATE, true)
        @Expect(cloned[3].GetExprKind() == ExprKind.RAISE_EXCEPTION, true)
        for (expr in oldExpressions) { @Expect(expr.GetParentBlock().isNone(), true) }
        for (expr in cloned) {
            @Expect(refEq(expr.GetTopLevelFunc().getOrThrow(), helper), true)
            for (operand in expr.GetOperands()) {
                if (operand.IsFunc()) { continue }
                @Expect(call.GetArgs().contains(operand), false)
            }
        }
        // Revisit both functions as later devirtualization rounds do.
        pass.Run(helper)
        pass.Run(caller)
        @Expect(cold.GetExpressions().size, 2)
        @Expect(helper.GetBody().getOrThrow().GetEntryBlock().getOrThrow().GetExpressions().size, 4)
    }

    @TestCase
    func localHandlerAndAggregateCaptureKeepOriginalConstruction(): Unit {
        let builder = CHIRBuilder(CHIRContext())
        let _ = builder.CreatePackage("outline_controls")
        let ctx = builder.context
        let (caught, caughtBlock, caughtCall) = MakeThrowConstruction(builder, "caught", ctx.GetInt64Ty(), true)
        let aggregate = ctx.GetTupleTy(ArrayList<Type>([ctx.GetInt64Ty(), ctx.GetInt64Ty()]))
        let (capturing, captureBlock, captureCall) = MakeThrowConstruction(builder, "capturing", aggregate, false)
        let pass = FunctionInline(builder, OptimizationLevel.O2, false)
        pass.Run(caught)
        pass.Run(capturing)
        @Expect(caughtBlock.GetExpressions().contains(caughtCall), true)
        @Expect(caughtBlock.GetTerminator().getOrThrow().GetSuccessors().size, 1)
        @Expect(captureBlock.GetExpressions().contains(captureCall), true)
        @Expect(captureBlock.GetExpressions().size, 4)
    }

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
        // The caller must not rely on this flag surviving Block.Clone.
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

    private func MarkCallerBlockForCopy(fn: Function): Block {
        let targets = ArrayList<Block>()
        for (block in fn.GetBody().getOrThrow().GetBlocks()) {
            for (expr in block.GetExpressions()) {
                if (let Some(constant) <- (expr as Constant)) {
                    if (constant.IsIntLit() && constant.GetSignedIntLitVal() == 7i64) {
                        @Assert(refEq(constant.GetTopLevelFunc().getOrThrow(), fn))
                        targets.add(block)
                    }
                }
            }
        }
        @Assert(targets.size == 1)
        let target = targets[0]
        @Assert(target.GetPredecessors().size == 2)
        @Assert(!target.GetGeneratedFromForIn())
        // Deliberate unit-test setup after real inline, outside normal pass order.
        target.SetGeneratedFromForIn(true)
        @Assert(target.GetGeneratedFromForIn())
        return target
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
        let firstTarget = MarkCallerBlockForCopy(first)
        @Expect(MergeBlocks().RunOnFunction(first, firstBuilder) > 0, true)
        @Expect(firstTarget.GetGeneratedFromForIn(), false)
        CheckLiteralUsers(callee, first, second, 2, 1)
        @Expect(global.GetUsers().size, 4)
        let secondTarget = MarkCallerBlockForCopy(second)
        @Expect(MergeBlocks().RunOnFunction(second, secondBuilder) > 0, true)
        @Expect(secondTarget.GetGeneratedFromForIn(), false)
        CheckLiteralUsers(callee, first, second, 2, 2)
        @Expect(global.GetUsers().size, 5)
    }
}
