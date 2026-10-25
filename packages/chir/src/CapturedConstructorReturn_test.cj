package cjcj::chir

import cjcj::option.GlobalOptions
import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

private class CapturedReturnFixture {
    let builder = CHIRBuilder(CHIRContext())
    let pkg: Package
    let fn: Function
    let captured: LocalVar
    let updated: Parameter
    let normal = ArrayList<Block>()
    let exceptional: Block

    init(captureReturn: Bool, debug: Bool) {
        let ctx = builder.context
        pkg = builder.CreatePackage("captured_receiver")
        let owner = builder.CreateClass(DebugLocation(), "Receiver", "Receiver", "captured_receiver", true, false)
        let clsTy = ctx.GetClassTy(owner, ArrayList<Type>())
        owner.SetType(clsTy)
        let refTy = ctx.GetRefTy(clsTy)
        fn = builder.CreateFunction(ctx.GetFuncTy(ArrayList<Type>([refTy, refTy, ctx.GetBoolTy(),
            ctx.GetBoolTy()]), refTy), "Receiver.init", srcCodeIdentifier: "init", packageName: "captured_receiver")
        fn.SetFuncKind(FuncKind.CLASS_CONSTRUCTOR)
        owner.AddMethod(fn)
        pkg.SetPackageInitFunc(fn)
        pkg.SetPackageLiteralInitFunc(fn)
        let initial = builder.CreateParameter(refTy, DebugLocation(), fn)
        updated = builder.CreateParameter(refTy, DebugLocation(), fn)
        let first = builder.CreateParameter(ctx.GetBoolTy(), DebugLocation(), fn)
        let second = builder.CreateParameter(ctx.GetBoolTy(), DebugLocation(), fn)
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let entry = builder.CreateBlock(body)
        body.SetEntryBlock(entry)
        let slot = builder.CreateAllocate(ctx.GetRefTy(refTy), refTy, entry)
        fn.SetReturnValue(slot.GetResult().getOrThrow())
        entry.AppendExpressions(ArrayList<Expression>([slot,
            builder.CreateStore(initial, fn.GetReturnValue().getOrThrow(), entry)]))
        if (captureReturn) {
            captured = fn.GetReturnValue().getOrThrow()
        } else {
            let local = builder.CreateAllocate(ctx.GetRefTy(refTy), refTy, entry)
            captured = local.GetResult().getOrThrow()
            entry.AppendExpressions(ArrayList<Expression>([local, builder.CreateStore(initial, captured, entry)]))
        }
        // A stored closure escapes: LambdaInline cannot erase the capture.
        let closureTy = ctx.GetFuncTy(ArrayList<Type>(), refTy)
        let closure = builder.CreateLambda(closureTy, closureTy, entry,
            identifier: "_CN17captured_receiver15captureReceiverEL_E")
        let closureBody = builder.CreateBlockGroup(fn)
        closure.InitBody(closureBody)
        let closureEntry = builder.CreateBlock(closureBody)
        closureBody.SetEntryBlock(closureEntry)
        let closureSlot = builder.CreateAllocate(ctx.GetRefTy(refTy), refTy, closureEntry)
        closure.SetReturnValue(closureSlot.GetResult().getOrThrow())
        let read = builder.CreateLoad(refTy, captured, closureEntry)
        closureEntry.AppendExpressions(ArrayList<Expression>([closureSlot, read,
            builder.CreateStore(read.GetResult().getOrThrow(), closure.GetReturnValue().getOrThrow(), closureEntry),
            builder.CreateExit(None, closureEntry)]))
        let sink = builder.CreateGlobalVar(ctx.GetRefTy(closureTy), "savedClosure")
        entry.AppendExpressions(ArrayList<Expression>([closure,
            builder.CreateStore(closure.GetResult().getOrThrow(), sink, entry)]))
        let choose = builder.CreateBlock(body)
        normal.add(builder.CreateBlock(body))
        normal.add(builder.CreateBlock(body))
        exceptional = builder.CreateBlock(body)
        entry.AppendExpression(builder.CreateBranch(first, normal[0], choose, entry))
        choose.AppendExpression(builder.CreateBranch(second, normal[1], exceptional, choose))
        for (block in normal) {
            block.AppendExpressions(ArrayList<Expression>([builder.CreateStore(updated, captured, block),
                builder.CreateExit(None, block)]))
        }
        exceptional.AppendExpression(builder.CreateRaiseException(initial, exceptional))
        let opts = GlobalOptions()
        opts.enableCompileDebug = debug
        ClosureConversion(builder, opts: opts).RunOnPackage(pkg)
    }
}

@Test
class CapturedConstructorReturnTest {
    private func CheckReturn(fn: Function): Unit {
        let slot = fn.GetReturnValue().getOrThrow()
        let allocation = slot.GetExpr().getOrThrow()
        @Expect(allocation.GetParentBlock().isSome(), true)
        if (allocation.GetParentBlock().isNone()) { return }
        @Expect(allocation.GetExprKind(), ExprKind.ALLOCATE)
        var exits: Int64 = 0
        var updatedStores: Int64 = 0
        for (block in fn.GetBody().getOrThrow().GetBlocks()) {
            let term = block.GetTerminator().getOrThrow()
            if (term.GetExprKind() != ExprKind.EXIT) { continue }
            exits++
            let exprs = block.GetExpressions()
            let copy = (exprs[exprs.size - 2] as Store).getOrThrow()
            @Expect(copy.GetLocation().nodeId, slot.nodeId)
            let load = (copy.GetValue().AsLocalVar().getOrThrow().GetExpr().getOrThrow() as Load).getOrThrow()
            let field = (load.GetLocation().AsLocalVar().getOrThrow().GetExpr().getOrThrow() as GetElementRef).getOrThrow()
            // The returned receiver must come from the very box receiving the
            // new receiver, not the initial parameter or an unused dummy slot.
            for (expr in exprs) {
                if (let Some(write) <- (expr as StoreElementRef)) {
                    if (write.GetValue().nodeId == fn.GetParam(1).nodeId) {
                        @Expect(write.GetLocation().nodeId, field.GetOperand(0).nodeId)
                        updatedStores++
                    }
                }
            }
        }
        @Expect(exits, 2)
        @Expect(updatedStores, 2)
    }

    @TestCase
    func escapedReceiverPreservesBothNormalExitsAndException(): Unit {
        let fixture = CapturedReturnFixture(true, false)
        CheckReturn(fixture.fn)
        @Expect(fixture.exceptional.GetExpressions().size, 1)
        @Expect(fixture.exceptional.GetTerminator().getOrThrow().GetExprKind(), ExprKind.RAISE_EXCEPTION)
    }

    @TestCase
    func debugBoxAndSerializationPreserveReturnedReceiver(): Unit {
        let fixture = CapturedReturnFixture(true, true)
        CheckReturn(fixture.fn)
        let bytes = CHIRSerializer.Serialize(fixture.pkg)
        try {
            let restored = CHIRBuilder(CHIRContext())
            @Assert(CHIRDeserializer.Deserialize(bytes.GetBufferPointer(), bytes.size, restored))
            let pkg = restored.context.GetCurPackage().getOrThrow()
            let fn = pkg.TryGetGlobalFunc(fixture.fn.GetIdentifier()).getOrThrow()
            CheckReturn(fn)
        } finally { bytes.close() }
    }

    @TestCase
    func ordinaryMutableCaptureStillEliminatesItsOldAllocation(): Unit {
        let fixture = CapturedReturnFixture(false, false)
        @Expect(fixture.captured.GetExpr().getOrThrow().GetParentBlock().isNone(), true)
        let ret = fixture.fn.GetReturnValue().getOrThrow()
        @Expect(ret.GetExpr().getOrThrow().GetParentBlock().isSome(), true)
        @Expect(ret.GetUsers().size, 1)
        @Expect((ret.GetUsers()[0] as Store).getOrThrow().GetValue().nodeId, fixture.fn.GetParam(0).nodeId)
        @Expect(fixture.exceptional.GetExpressions().size, 1)
    }
}
