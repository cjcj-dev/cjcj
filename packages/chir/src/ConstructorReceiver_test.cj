package cjcj::chir

import cjcj::option.OptimizationLevel
import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class ConstructorReceiverTest {
    private func MakeConstructor(builder: CHIRBuilder): Function {
        let context = builder.context
        let owner = builder.CreateClass(DebugLocation(), "Receiver", "Receiver", "receiver_abi", true, false)
        let ty = context.GetClassTy(owner, ArrayList<Type>())
        owner.SetType(ty)
        let refTy = context.GetRefTy(ty)
        let fn = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>([refTy]), refTy),
            "Receiver.init", srcCodeIdentifier: "init", packageName: "receiver_abi")
        owner.AddMethod(fn)
        fn.SetFuncKind(FuncKind.CLASS_CONSTRUCTOR)
        let receiver = builder.CreateParameter(refTy, DebugLocation(), fn)
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let block = builder.CreateBlock(body)
        body.SetEntryBlock(block)
        let slot = builder.CreateAllocate(context.GetRefTy(refTy), refTy, block)
        fn.SetReturnValue(slot.GetResult().getOrThrow())
        let initial = builder.CreateStore(receiver, fn.GetReturnValue().getOrThrow(), block)
        let registration = builder.CreateIntrinsic(refTy,
            IntrisicCallContext(kind: IntrinsicKind.REGISTER_FINALIZER,
                args: ArrayList<Value>([receiver])), block)
        let updated = builder.CreateStore(registration.GetResult().getOrThrow(),
            fn.GetReturnValue().getOrThrow(), block)
        block.AppendExpressions(ArrayList<Expression>([slot, initial, registration, updated,
            builder.CreateExit(None, block)]))
        return fn
    }

    @TestCase
    func serializationPreservesReceiverResultAndRejectsOldABI(): Unit {
        let builder = CHIRBuilder(CHIRContext())
        let pkg = builder.CreatePackage("receiver_abi")
        let ctor = MakeConstructor(builder)
        pkg.SetPackageLiteralInitFunc(ctor)
        let bytes = CHIRSerializer.Serialize(pkg)
        try {
            let restored = CHIRBuilder(CHIRContext())
            @Assert(CHIRDeserializer.Deserialize(bytes.GetBufferPointer(), bytes.size, restored))
            let fn = restored.context.GetCurPackage().getOrThrow().GetGlobalFunctions()[0]
            @Expect(ConstructorReturnsReceiver(fn), true)
            @Expect(ReturnTypeShouldBeVoid(fn), false)
            @Expect(fn.GetReturnType().getOrThrow() == fn.GetParam(0).GetType().getOrThrow(), true)
            let expressions = fn.GetEntryBlock().getOrThrow().GetExpressions()
            let registration = (expressions[2] as Intrinsic).getOrThrow()
            @Expect(registration.GetIntrinsicKind(), IntrinsicKind.REGISTER_FINALIZER)
            let store = (expressions[3] as Store).getOrThrow()
            @Expect(store.GetValue().nodeId, registration.GetResult().getOrThrow().nodeId)
            @Expect(store.GetLocation().nodeId, fn.GetReturnValue().getOrThrow().nodeId)
            // Mutate only this test-owned serialized identifier; tables remain valid.
            unsafe { (bytes.GetBufferPointer() + 4).write(0u8) }
            let rejected = CHIRBuilder(CHIRContext())
            @Expect(CHIRDeserializer.Deserialize(bytes.GetBufferPointer(), bytes.size, rejected), false)
            @Expect(rejected.context.GetCurPackage().isNone(), true)
        } finally {
            bytes.close()
        }
    }

    @TestCase
    func inliningKeepsRegistrationResultConnectedToCallerReturn(): Unit {
        let builder = CHIRBuilder(CHIRContext())
        let _ = builder.CreatePackage("receiver_inline")
        let ctor = MakeConstructor(builder)
        let refTy = ctor.GetReturnType().getOrThrow()
        let host = builder.CreateFunction(builder.context.GetFuncTy(ArrayList<Type>([refTy]), refTy), "caller")
        let receiver = builder.CreateParameter(refTy, DebugLocation(), host)
        let body = builder.CreateBlockGroup(host)
        host.InitBody(body)
        let block = builder.CreateBlock(body)
        body.SetEntryBlock(block)
        let slot = builder.CreateAllocate(builder.context.GetRefTy(refTy), refTy, block)
        host.SetReturnValue(slot.GetResult().getOrThrow())
        let call = builder.CreateApply(refTy, ctor, FuncCallContext(args: ArrayList<Value>([receiver])), block)
        let store = builder.CreateStore(call.GetResult().getOrThrow(), host.GetReturnValue().getOrThrow(), block)
        block.AppendExpressions(ArrayList<Expression>([slot, call, store, builder.CreateExit(None, block)]))
        FunctionInline(builder, OptimizationLevel.O2, false).DoFunctionInline(call, "receiver-test")
        let forwarded = (store.GetValue().AsLocalVar().getOrThrow().GetExpr().getOrThrow() as Load).getOrThrow()
        let registrationStores = ArrayList<Store>()
        Visitor.Visit(body, { expr: Expression =>
            if (let Some(intrinsic) <- (expr as Intrinsic)) {
                if (intrinsic.GetIntrinsicKind() == IntrinsicKind.REGISTER_FINALIZER) {
                    @Expect(intrinsic.GetResult().getOrThrow().GetType().getOrThrow() == refTy, true)
                    for (user in intrinsic.GetResult().getOrThrow().GetUsers()) {
                        if (let Some(updated) <- (user as Store)) { registrationStores.add(updated) }
                    }
                }
            }
            VisitResult.CONTINUE
        })
        @Assert(registrationStores.size == 1)
        @Expect(registrationStores[0].GetLocation().nodeId, forwarded.GetLocation().nodeId)
        @Expect(store.GetLocation().nodeId, host.GetReturnValue().getOrThrow().nodeId)
    }
    @TestCase
    func initializationIdentityDoesNotIncludeAnotherObject(): Unit {
        let builder = CHIRBuilder(CHIRContext())
        let _ = builder.CreatePackage("receiver_identity")
        let ctor = MakeConstructor(builder)
        let block = ctor.GetEntryBlock().getOrThrow()
        let receiverTy = ctor.GetReturnType().getOrThrow()
        let own = builder.CreateLoad(receiverTy, ctor.GetReturnValue().getOrThrow(), block)
        let otherSlot = builder.CreateAllocate(builder.context.GetRefTy(receiverTy), receiverTy, block)
        let other = builder.CreateLoad(receiverTy, otherSlot.GetResult().getOrThrow(), block)
        @Expect(IsCurrentReceiver(own.GetResult().getOrThrow(), ctor.GetParam(0)), true)
        @Expect(IsCurrentReceiver(other.GetResult().getOrThrow(), ctor.GetParam(0)), false)
        let registration = (block.GetExpressions()[2] as Intrinsic).getOrThrow()
        @Expect(IsCurrentReceiver(registration.GetResult().getOrThrow(), ctor.GetParam(0)), true)
    }

    @TestCase
    func staticAndForeignConstructorsKeepTheirABI(): Unit {
        let builder = CHIRBuilder(CHIRContext())
        let staticInit = builder.CreateFunction(builder.context.GetFuncTy(ArrayList<Type>(),
            builder.context.GetUnitTy()), "static.init", srcCodeIdentifier: "static.init")
        staticInit.SetFuncKind(FuncKind.CLASS_CONSTRUCTOR)
        @Expect(ConstructorReturnsReceiver(staticInit), false)
        @Expect(ReturnTypeShouldBeVoid(staticInit), true)
        let foreignInit = builder.CreateFunction(builder.context.GetFuncTy(ArrayList<Type>(),
            builder.context.GetUnitTy()), "foreign.init")
        foreignInit.SetFuncKind(FuncKind.CLASS_CONSTRUCTOR)
        foreignInit.EnableAttr(Attribute.FOREIGN)
        @Expect(ConstructorReturnsReceiver(foreignInit), false)
        @Expect(ReturnTypeShouldBeVoid(foreignInit), true)
    }

}
