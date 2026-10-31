package cjcj::chir

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

private class ReceiverFutureFixture {
    public let builder = CHIRBuilder(CHIRContext())
    public let pkg: Package
    public let owner: ClassDef
    public let fn: Function
    public let block: Block
    public let closure: Parameter
    public let constructor: Function
    public let allocation: Allocate
    public let initCall: Apply
    public let spawnExpr: Spawn
    public let execute: Function

    public init() {
        pkg = builder.CreatePackage("future_receiver")
        let ctx = builder.context
        owner = builder.CreateClass(DebugLocation(), "Future", "Future", "std.core", true, true)
        let ty = ctx.GetClassTy(owner, ArrayList<Type>())
        owner.SetType(ty)
        let refTy = ctx.GetRefTy(ty)
        let closureTy = ctx.GetFuncTy(ArrayList<Type>(), ctx.GetInt64Ty())
        constructor = builder.CreateFunction(ctx.GetFuncTy(ArrayList<Type>([refTy, closureTy]), refTy),
            "Future.init", srcCodeIdentifier: "init", packageName: "std.core")
        constructor.SetFuncKind(FuncKind.CLASS_CONSTRUCTOR)
        owner.AddMethod(constructor)
        execute = builder.CreateFunction(ctx.GetFuncTy(ArrayList<Type>([closureTy]), ctx.GetUnitTy()),
            "Future.executeClosure", srcCodeIdentifier: "executeClosure", packageName: "std.core")
        owner.AddMethod(execute)
        fn = builder.CreateFunction(ctx.GetFuncTy(ArrayList<Type>([closureTy]), ctx.GetUnitTy()), "spawnCaller")
        closure = builder.CreateParameter(closureTy, DebugLocation(), fn)
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        block = builder.CreateBlock(body)
        body.SetEntryBlock(block)
        allocation = builder.CreateAllocate(refTy, ty, block)
        initCall = builder.CreateApply(refTy, constructor,
            FuncCallContext(args: ArrayList<Value>([allocation.GetResult().getOrThrow(), closure])), block)
        spawnExpr = builder.CreateSpawn(refTy, initCall.GetResult().getOrThrow(), block)
        block.AppendExpressions(ArrayList<Expression>([allocation, initCall, spawnExpr]))
    }

    public func AddGet(withTimeout: Bool): Apply {
        let ctx = builder.context
        let receiver = initCall.GetResult().getOrThrow()
        let args = ArrayList<Value>([receiver])
        let tys = ArrayList<Type>([receiver.GetType().getOrThrow()])
        if (withTimeout) {
            let timeout = builder.CreateConstant(ctx.GetInt64Ty(), IntLiteral(1), block)
            block.AppendExpression(timeout)
            args.add(timeout.GetResult().getOrThrow())
            tys.add(ctx.GetInt64Ty())
        }
        let get = builder.CreateFunction(ctx.GetFuncTy(tys, ctx.GetInt64Ty()), "Future.get",
            srcCodeIdentifier: "get", packageName: "std.core")
        owner.AddMethod(get)
        let call = builder.CreateApply(ctx.GetInt64Ty(), get, FuncCallContext(args: args), block)
        block.AppendExpression(call)
        return call
    }

    public func Finish(): Unit {
        block.AppendExpression(builder.CreateExit(None, block))
    }
}

@Test
class RedundantFutureRemovalTest {
    @TestCase
    func observedFutureGetKeepsReturnedReceiver(): Unit {
        // Actual std.process shape: Allocate -> returned init ref -> Spawn,
        // Debug and get(). The get call has only two operands without timeout.
        for (withTimeout in [false, true]) {
            let f = ReceiverFutureFixture()
            let receiver = f.initCall.GetResult().getOrThrow()
            let debug = f.builder.CreateDebug(f.builder.context.GetUnitTy(), receiver, "future", f.block)
            f.block.AppendExpression(debug)
            let get = f.AddGet(withTimeout)
            f.Finish()
            @Expect(RedundantFutureRemoval(f.pkg).RunOnFunc(f.fn), 0)
            @Expect(f.spawnExpr.IsExecuteClosure(), false)
            // Inspect the operand even if a product cut incorrectly changes the spawn mode.
            @Expect(f.spawnExpr.GetObject().nodeId, receiver.nodeId)
            @Expect(get.GetOperand(1).nodeId, receiver.nodeId)
            @Expect(f.initCall.GetParentBlock().isSome(), true)
            @Expect(f.allocation.GetParentBlock().isSome(), true)
        }
    }

    @TestCase
    func unobservedReceiverStillUsesExecuteClosure(): Unit {
        for (withDebug in [false, true]) {
            let f = ReceiverFutureFixture()
            let debugs = ArrayList<Debug>()
            if (withDebug) {
                for (value in [f.allocation.GetResult().getOrThrow(), f.initCall.GetResult().getOrThrow()]) {
                    let debug = f.builder.CreateDebug(f.builder.context.GetUnitTy(), value, "future", f.block)
                    f.block.AppendExpression(debug)
                    debugs.add(debug)
                }
            }
            f.Finish()
            @Expect(RedundantFutureRemoval(f.pkg).RunOnFunc(f.fn), 1)
            @Expect(f.spawnExpr.IsExecuteClosure(), true)
            @Expect(f.spawnExpr.GetClosure().nodeId, f.closure.nodeId)
            @Expect(f.spawnExpr.GetExecuteClosure().getOrThrow().nodeId, f.execute.nodeId)
            @Expect(f.initCall.GetParentBlock().isNone(), true)
            @Expect(f.allocation.GetParentBlock().isNone(), true)
            for (debug in debugs) {
                @Expect(debug.GetOperand(0).nodeId, f.closure.nodeId)
            }
            @Expect(RedundantFutureRemoval(f.pkg).RunOnFunc(f.fn), 0)
        }
    }

    @TestCase
    func observedAllocationCannotBeRemoved(): Unit {
        let f = ReceiverFutureFixture()
        let raw = f.allocation.GetResult().getOrThrow()
        let use = f.builder.CreateFunction(f.builder.context.GetFuncTy(
            ArrayList<Type>([raw.GetType().getOrThrow()]), f.builder.context.GetUnitTy()), "observe")
        let call = f.builder.CreateApply(f.builder.context.GetUnitTy(), use,
            FuncCallContext(args: ArrayList<Value>([raw])), f.block)
        f.block.AppendExpression(call)
        f.Finish()
        @Expect(RedundantFutureRemoval(f.pkg).RunOnFunc(f.fn), 0)
        @Expect(call.GetOperand(1).nodeId, raw.nodeId)
        @Expect(f.spawnExpr.GetFuture().nodeId, f.initCall.GetResult().getOrThrow().nodeId)
    }

    @TestCase
    func ordinaryFactoryIsNotAConstructor(): Unit {
        let f = ReceiverFutureFixture()
        f.constructor.SetFuncKind(FuncKind.DEFAULT)
        f.Finish()
        @Expect(RedundantFutureRemoval(f.pkg).RunOnFunc(f.fn), 0)
        @Expect(f.initCall.GetParentBlock().isSome(), true)
    }

    @TestCase
    func foreignConstructorKeepsItsCall(): Unit {
        let f = ReceiverFutureFixture()
        f.constructor.EnableAttr(Attribute.FOREIGN)
        f.Finish()
        @Expect(RedundantFutureRemoval(f.pkg).RunOnFunc(f.fn), 0)
        @Expect(f.initCall.GetParentBlock().isSome(), true)
    }

    @TestCase
    func anotherClassNamedFutureIsNotCoreFuture(): Unit {
        let f = ReceiverFutureFixture()
        let other = f.builder.CreateClass(DebugLocation(), "Future", "other.Future", "example", true, false)
        f.constructor.SetOuterDeclaredOrExtendedDef(other)
        f.Finish()
        @Expect(RedundantFutureRemoval(f.pkg).RunOnFunc(f.fn), 0)
        @Expect(f.spawnExpr.IsExecuteClosure(), false)
    }

    @TestCase
    func multipleSpawnUsersKeepTheFuture(): Unit {
        let f = ReceiverFutureFixture()
        let receiver = f.initCall.GetResult().getOrThrow()
        let second = f.builder.CreateSpawn(receiver.GetType().getOrThrow(), receiver, f.block)
        f.block.AppendExpression(second)
        f.Finish()
        @Expect(RedundantFutureRemoval(f.pkg).RunOnFunc(f.fn), 0)
        @Expect(f.spawnExpr.IsExecuteClosure(), false)
        @Expect(second.IsExecuteClosure(), false)
    }
}
