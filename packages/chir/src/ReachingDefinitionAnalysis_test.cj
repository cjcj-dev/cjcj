package cjcj::chir

import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class ReachingDefinitionAliasingTest {
    @TestCase
    public func PointerWriteInvalidatesStoreAfterAddressEscape(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let fn = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>(), context.GetInt64Ty()), "pointer")
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let block = builder.CreateBlock(body)
        body.SetEntryBlock(block)
        let x = builder.CreateAllocate(context.GetRefTy(context.GetInt64Ty()), context.GetInt64Ty(), block)
        let address = builder.CreateIntrinsic(context.GetCPointerTy(context.GetInt64Ty()),
            IntrisicCallContext(kind: IntrinsicKind.INOUT_PARAM,
                args: ArrayList<Value>([x.GetResult().getOrThrow()])), block)
        let pointer = builder.CreateIntrinsic(context.GetCPointerTy(context.GetInt64Ty()),
            IntrisicCallContext(kind: IntrinsicKind.CPOINTER_INIT1,
                args: ArrayList<Value>([address.GetResult().getOrThrow()])), block)
        let one = builder.CreateConstant(context.GetInt64Ty(), IntLiteral(1), block)
        let store = builder.CreateStore(one.GetResult().getOrThrow(), x.GetResult().getOrThrow(), block)
        let two = builder.CreateConstant(context.GetInt64Ty(), IntLiteral(2), block)
        let zero = builder.CreateConstant(context.GetInt64Ty(), IntLiteral(0), block)
        let write = builder.CreateIntrinsic(context.GetUnitTy(), IntrisicCallContext(kind: IntrinsicKind.CPOINTER_WRITE,
            args: ArrayList<Value>([pointer.GetResult().getOrThrow(), zero.GetResult().getOrThrow(),
                two.GetResult().getOrThrow()]), instTypeArgs: ArrayList<Type>([context.GetInt64Ty()])), block)
        let load = builder.CreateLoad(context.GetInt64Ty(), x.GetResult().getOrThrow(), block)
        block.AppendExpressions(ArrayList<Expression>([x, address, pointer, one, store, two, zero, write, load,
            builder.CreateExit(Some<Value>(load.GetResult().getOrThrow()), block)]))
        let analysis = ConstAnalysisWrapper(builder).RunOnFunc(fn, BasicDiagnosticEngine()).getOrThrow()
        var observed = false
        analysis.VisitWith(
            { _: ConstDomain, _: Expression, _: Int64 => () },
            { state: ConstDomain, expr: Expression, _: Int64 =>
                if (expr.nodeId == load.nodeId) {
                    observed = true
                    @Expect(state.CheckAbstractValue(load.GetResult().getOrThrow()).isNone(), true)
                }
            },
            { _: ConstDomain, _: Expression, _: Option<Block> => () }
        )
        @Expect(observed, true)
        RedundantLoadElimination().RunOnFunction(fn)
        @Expect(load.GetParentBlock().isSome(), true)
    }

    @TestCase
    public func PointerCallInvalidatesStoreAndPreviousLoad(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let pointerTy = context.GetCPointerTy(context.GetInt64Ty())
        let fn = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>(), context.GetInt64Ty()), "pointerCall")
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let block = builder.CreateBlock(body)
        body.SetEntryBlock(block)
        let x = builder.CreateAllocate(context.GetRefTy(context.GetInt64Ty()), context.GetInt64Ty(), block)
        let address = builder.CreateIntrinsic(pointerTy, IntrisicCallContext(kind: IntrinsicKind.INOUT_PARAM,
            args: ArrayList<Value>([x.GetResult().getOrThrow()])), block)
        let pointer = builder.CreateIntrinsic(pointerTy, IntrisicCallContext(kind: IntrinsicKind.CPOINTER_INIT1,
            args: ArrayList<Value>([address.GetResult().getOrThrow()])), block)
        let one = builder.CreateConstant(context.GetInt64Ty(), IntLiteral(1), block)
        let store = builder.CreateStore(one.GetResult().getOrThrow(), x.GetResult().getOrThrow(), block)
        let callee = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>([pointerTy]), context.GetUnitTy()), "write")
        let call = builder.CreateApply(context.GetUnitTy(), callee,
            FuncCallContext(args: ArrayList<Value>([pointer.GetResult().getOrThrow()])), block)
        let first = builder.CreateLoad(context.GetInt64Ty(), x.GetResult().getOrThrow(), block)
        let secondCall = builder.CreateApply(context.GetUnitTy(), callee,
            FuncCallContext(args: ArrayList<Value>([pointer.GetResult().getOrThrow()])), block)
        let second = builder.CreateLoad(context.GetInt64Ty(), x.GetResult().getOrThrow(), block)
        block.AppendExpressions(ArrayList<Expression>([x, address, pointer, one, store, call, first, secondCall, second,
            builder.CreateExit(Some<Value>(second.GetResult().getOrThrow()), block)]))
        RedundantLoadElimination().RunOnFunction(fn)
        @Expect(first.GetParentBlock().isSome(), true)
        @Expect(second.GetParentBlock().isSome(), true)
    }

    @TestCase
    public func AddressEscapeDoesNotDisableDirectStoreForwarding(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let fn = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>(), context.GetInt64Ty()), "direct")
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let block = builder.CreateBlock(body)
        body.SetEntryBlock(block)
        let x = builder.CreateAllocate(context.GetRefTy(context.GetInt64Ty()), context.GetInt64Ty(), block)
        let address = builder.CreateIntrinsic(context.GetCPointerTy(context.GetInt64Ty()),
            IntrisicCallContext(kind: IntrinsicKind.INOUT_PARAM,
                args: ArrayList<Value>([x.GetResult().getOrThrow()])), block)
        let pointer = builder.CreateIntrinsic(context.GetCPointerTy(context.GetInt64Ty()),
            IntrisicCallContext(kind: IntrinsicKind.CPOINTER_INIT1,
                args: ArrayList<Value>([address.GetResult().getOrThrow()])), block)
        let one = builder.CreateConstant(context.GetInt64Ty(), IntLiteral(1), block)
        let store = builder.CreateStore(one.GetResult().getOrThrow(), x.GetResult().getOrThrow(), block)
        let load = builder.CreateLoad(context.GetInt64Ty(), x.GetResult().getOrThrow(), block)
        block.AppendExpressions(ArrayList<Expression>([x, address, pointer, one, store, load,
            builder.CreateExit(Some<Value>(load.GetResult().getOrThrow()), block)]))
        RedundantLoadElimination().RunOnFunction(fn)
        @Expect(load.GetParentBlock().isNone(), true)
        @Expect(block.GetTerminator().getOrThrow().GetOperand(0).nodeId, one.GetResult().getOrThrow().nodeId)
    }

    @TestCase
    public func NonAliasedStoreStillForwardsAcrossCall(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let fn = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>(), context.GetInt64Ty()), "local")
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let block = builder.CreateBlock(body)
        body.SetEntryBlock(block)
        let x = builder.CreateAllocate(context.GetRefTy(context.GetInt64Ty()), context.GetInt64Ty(), block)
        let one = builder.CreateConstant(context.GetInt64Ty(), IntLiteral(1), block)
        let store = builder.CreateStore(one.GetResult().getOrThrow(), x.GetResult().getOrThrow(), block)
        let callee = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>(), context.GetUnitTy()), "unrelated")
        let call = builder.CreateApply(context.GetUnitTy(), callee, FuncCallContext(), block)
        let load = builder.CreateLoad(context.GetInt64Ty(), x.GetResult().getOrThrow(), block)
        block.AppendExpressions(ArrayList<Expression>([x, one, store, call, load,
            builder.CreateExit(Some<Value>(load.GetResult().getOrThrow()), block)]))
        RedundantLoadElimination().RunOnFunction(fn)
        @Expect(load.GetParentBlock().isNone(), true)
        @Expect(block.GetTerminator().getOrThrow().GetOperand(0).nodeId, one.GetResult().getOrThrow().nodeId)
    }
}
