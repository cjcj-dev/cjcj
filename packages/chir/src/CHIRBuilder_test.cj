package cjcj::chir

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class CHIRBuilderTest {
    @TestCase
    public func CreationKeepsParentWithoutInsertion(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let fn = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>(), context.GetUnitTy()), "creation")
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let block = builder.CreateBlock(body)
        body.SetEntryBlock(block)
        let constant = builder.CreateConstant(context.GetInt64Ty(), IntLiteral(7), block)
        let allocate = builder.CreateAllocate(context.GetRefTy(context.GetInt64Ty()), context.GetInt64Ty(), block)
        let store = builder.CreateStore(constant.GetResult().getOrThrow(), allocate.GetResult().getOrThrow(), block)
        let load = builder.CreateLoad(context.GetInt64Ty(), allocate.GetResult().getOrThrow(), block)
        @Expect(block.GetExpressions().size, 0)
        @Expect(constant.GetParentBlock().getOrThrow().nodeId, block.nodeId)
        @Expect(load.GetParentBlock().getOrThrow().nodeId, block.nodeId)
        block.AppendExpressions(ArrayList<Expression>([constant, allocate, store, load]))
        @Expect(block.GetExpressions().size, 4)
        @Expect(block.GetExpressions()[0].nodeId, constant.nodeId)
        @Expect(block.GetExpressions()[3].nodeId, load.nodeId)
    }

    @TestCase
    public func TerminatorEdgesBelongToInsertion(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let fn = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>(), context.GetUnitTy()), "edge")
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let source = builder.CreateBlock(body)
        let target = builder.CreateBlock(body)
        body.SetEntryBlock(source)
        let goTo = builder.CreateGoTo(target, source)
        @Expect(source.GetExpressions().size, 0)
        @Expect(target.GetPredecessors().size, 0)
        @Expect(goTo.GetParentBlock().getOrThrow().nodeId, source.nodeId)
        source.AppendExpression(goTo)
        @Expect(source.GetTerminator().getOrThrow().nodeId, goTo.nodeId)
        @Expect(target.GetPredecessors().size, 1)
    }

    @TestCase
    public func ConversionReturnsOrderedGroup(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let sourceTy = context.GetGenericTy("T")
        let targetTy = context.GetGenericTy("U")
        let fn = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>(), context.GetUnitTy()), "conversion")
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let block = builder.CreateBlock(body)
        body.SetEntryBlock(block)
        let value = builder.CreateParameter(context.GetRefTy(sourceTy), DebugLocation(), fn)
        let (result, expressions) = TypeCastOrBoxIfNeeded(value, targetTy, builder, block)
        @Expect(block.GetExpressions().size, 0)
        @Expect(expressions.size, 2)
        // The result and its operand are the actual values produced by the helper.
        @Expect(expressions[0].GetExprKind(), ExprKind.LOAD)
        @Expect(expressions[1].GetExprKind(), ExprKind.CLASS_STATIC_CAST)
        @Expect(expressions[1].GetOperand(0).nodeId, expressions[0].GetResult().getOrThrow().nodeId)
        @Expect(result.nodeId, expressions[1].GetResult().getOrThrow().nodeId)
        block.AppendExpressions(expressions)
        @Expect(block.GetExpressions()[0].nodeId, expressions[0].nodeId)
        @Expect(block.GetExpressions()[1].nodeId, expressions[1].nodeId)
    }

    @TestCase
    public func SplitBlockConnectsBothHalves(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let fn = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>(), context.GetUnitTy()), "split")
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let block = builder.CreateBlock(body)
        body.SetEntryBlock(block)
        let separator = builder.CreateConstant(context.GetInt64Ty(), IntLiteral(11), block)
        let exit = builder.CreateExit(None, block)
        block.AppendExpressions(ArrayList<Expression>([separator, exit]))
        let (before, after) = builder.SplitBlock(separator)
        @Expect(before.GetTerminator().isSome(), true)
        if (let Some(term) <- before.GetTerminator()) {
            @Expect(term.GetExprKind(), ExprKind.GOTO)
            @Expect(term.GetSuccessor(0).nodeId, after.nodeId)
        }
        @Expect(after.GetTerminator().getOrThrow().nodeId, exit.nodeId)
        @Expect(after.GetPredecessors().size, 1)
    }

}

@Test
public class ExpressionFamilyEdgesTest {
    @TestCase
    public func ExceptionalFamiliesUseExpressionOperands(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let fn = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>(), context.GetUnitTy()), "families")
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let source = builder.CreateBlock(body)
        let normal = builder.CreateBlock(body)
        let error = builder.CreateBlock(body)
        body.SetEntryBlock(source)
        let value = builder.CreateConstant(context.GetInt64Ty(), IntLiteral(7), source).GetResult().getOrThrow()
        let cast = builder.CreateNumericCastWithException(context.GetInt32Ty(), value, normal, error, source)
        let allocate = builder.CreateAllocateWithException(context.GetRefTy(context.GetInt64Ty()), context.GetInt64Ty(),
            normal, error, source)
        let raw = builder.CreateRawArrayAllocateWithException(context.GetRefTy(context.GetRawArrayTy(context.GetInt64Ty())),
            context.GetInt64Ty(), value, normal, error, source)
        let spawn = builder.CreateSpawnWithException(context.GetInt64Ty(), value, normal, error, source)
        @Expect((cast as NumericCastBase).isSome(), true)
        @Expect((allocate as AllocateBase).isSome(), true)
        @Expect((raw as RawArrayAllocateBase).isSome(), true)
        @Expect((spawn as SpawnBase).isSome(), true)
        for (expr in ArrayList<Expression>([cast, allocate, raw, spawn])) {
            @Expect(expr.IsTerminator(), true)
            @Expect(expr.GetNumOfSuccessor(), 2)
            @Expect(expr.GetOperands().size, expr.GetNumOfNonSuccessorOperands() + 2)
            @Expect(expr.GetSuccessor(0).nodeId, normal.nodeId)
            @Expect(expr.GetSuccessor(1).nodeId, error.nodeId)
        }
        source.AppendExpression(cast)
        @Expect(source.GetTerminator().getOrThrow().nodeId, cast.nodeId)
        @Expect(normal.GetPredecessors().size, 1)
        @Expect(error.GetPredecessors().size, 1)
        cast.RemoveSelfFromBlock()
        @Expect(normal.GetPredecessors().size, 0)
        @Expect(error.GetPredecessors().size, 0)
    }
}
