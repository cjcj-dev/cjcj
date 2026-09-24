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
        @Expect(expressions[1].GetExprKind(), ExprKind.TYPECAST)
        @Expect(expressions[1].GetOperand(0).nodeId, expressions[0].GetResult().getOrThrow().nodeId)
        @Expect(result.nodeId, expressions[1].GetResult().getOrThrow().nodeId)
        block.AppendExpressions(expressions)
        @Expect(block.GetExpressions()[0].nodeId, expressions[0].nodeId)
        @Expect(block.GetExpressions()[1].nodeId, expressions[1].nodeId)
    }
}
