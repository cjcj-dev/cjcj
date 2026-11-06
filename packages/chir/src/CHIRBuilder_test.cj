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
    public func ConstantLiteralIsItsOperand(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let fn = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>(), context.GetUnitTy()), "literal")
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let block = builder.CreateBlock(body)
        body.SetEntryBlock(block)
        let first = IntLiteral(context.GetInt64Ty(), 41)
        let constant = builder.CreateConstant(context.GetInt64Ty(), first, block)
        @Expect(constant.GetNumOfOperands(), 1)
        @Expect(GetOperands(constant).size, 1)
        if (constant.GetNumOfOperands() == 1) {
            @Expect(constant.GetOperand(0).nodeId, first.nodeId)
            let replacement = IntLiteral(context.GetInt64Ty(), 42)
            constant.ReplaceOperand(0, replacement)
            @Expect(constant.GetValue().nodeId, replacement.nodeId)
            @Expect(constant.GetSignedIntLitVal(), 42)
        }
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

    @TestCase
    public func SplitLongSuffixPreservesOrderParentsUsersAndEdges(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let fn = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>(), context.GetUnitTy()), "split-long")
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let block = builder.CreateBlock(body)
        let target = builder.CreateBlock(body)
        let control = builder.CreateBlock(body)
        body.SetEntryBlock(block)
        let prefix = builder.CreateConstant(context.GetInt64Ty(), IntLiteral(7), block)
        let separatorLiteral = IntLiteral(context.GetInt64Ty(), 11)
        let separator = builder.CreateConstant(context.GetInt64Ty(), separatorLiteral, block)
        block.AppendExpressions(ArrayList<Expression>([prefix, separator]))
        let sharedLiteral = IntLiteral(context.GetInt64Ty(), 42)
        let suffix = ArrayList<Expression>()
        for (_ in 0..2048) {
            let expr = builder.CreateConstant(context.GetInt64Ty(), sharedLiteral, block)
            block.AppendExpression(expr)
            suffix.add(expr)
        }
        let outgoing = builder.CreateGoTo(target, block)
        block.AppendExpression(outgoing)
        let controlEdge = builder.CreateGoTo(target, control)
        control.AppendExpression(controlEdge)
        let (before, after) = builder.SplitBlock(separator)
        @Expect(before.GetExpressionsRef().size, 2)
        @Expect(before.GetExpressionByIdx(0).nodeId, prefix.nodeId)
        @Expect(before.GetTerminator().getOrThrow().GetSuccessor(0).nodeId, after.nodeId)
        @Expect(after.GetExpressionsRef().size, suffix.size + 1)
        for (idx in 0..suffix.size) {
            @Expect(after.GetExpressionByIdx(idx).nodeId, suffix[idx].nodeId)
            @Expect(suffix[idx].GetParentBlock().getOrThrow().nodeId, after.nodeId)
        }
        @Expect(after.GetTerminator().getOrThrow().nodeId, outgoing.nodeId)
        @Expect(outgoing.GetParentBlock().getOrThrow().nodeId, after.nodeId)
        @Expect(after.GetPredecessors().size, 1)
        @Expect(after.GetPredecessors()[0].nodeId, before.nodeId)
        @Expect(target.GetPredecessors().size, 2)
        @Expect(target.GetPredecessors().contains(after), true)
        @Expect(target.GetPredecessors().contains(control), true)
        @Expect(target.GetPredecessors().contains(before), false)
        @Expect(sharedLiteral.GetUsers().size, suffix.size)
        @Expect(separatorLiteral.GetUsers().isEmpty(), true)
        @Expect(separator.GetParentBlock().isNone(), true)
        @Expect(separator.GetNumOfOperands(), 0)
        @Expect(control.GetTerminator().getOrThrow().nodeId, controlEdge.nodeId)
    }

    @TestCase
    public func SplitUninsertedSeparatorLeavesExistingBlockUnchanged(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let fn = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>(), context.GetUnitTy()), "split-absent")
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let block = builder.CreateBlock(body)
        body.SetEntryBlock(block)
        let separator = builder.CreateConstant(context.GetInt64Ty(), IntLiteral(11), block)
        let exit = builder.CreateExit(None, block)
        block.AppendExpression(exit)
        let (before, after) = builder.SplitBlock(separator)
        @Expect(before.GetExpressionsRef().size, 1)
        @Expect(before.GetTerminator().getOrThrow().nodeId, exit.nodeId)
        @Expect(exit.GetParentBlock().getOrThrow().nodeId, before.nodeId)
        @Expect(after.GetExpressionsRef().isEmpty(), true)
        @Expect(after.GetPredecessors().isEmpty(), true)
        @Expect(separator.GetNumOfOperands(), 1)
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
        let cast = builder.CreateTryNumericCast(context.GetInt32Ty(), value, normal, error, source)
        let allocate = builder.CreateTryAllocate(context.GetRefTy(context.GetInt64Ty()), context.GetInt64Ty(),
            normal, error, source)
        let raw = builder.CreateTryRawArrayAllocate(context.GetRefTy(context.GetRawArrayTy(context.GetInt64Ty())),
            context.GetInt64Ty(), value, normal, error, source)
        let spawnExpr = builder.CreateTrySpawn(context.GetInt64Ty(), value, normal, error, source)
        @Expect((cast as NumericCastBase).isSome(), true)
        @Expect((allocate as AllocateBase).isSome(), true)
        @Expect((raw as RawArrayAllocateBase).isSome(), true)
        @Expect((spawnExpr as SpawnBase).isSome(), true)
        for (expr in ArrayList<Expression>([cast, allocate, raw, spawnExpr])) {
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

    @TestCase
    public func ExceptionOpsUseDistinctExprKinds(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let fn = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>(), context.GetUnitTy()), "exception-ops")
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let source = builder.CreateBlock(body)
        let normal = builder.CreateBlock(body)
        let error = builder.CreateBlock(body)
        body.SetEntryBlock(source)
        let value = builder.CreateConstant(context.GetInt64Ty(), IntLiteral(7), source).GetResult().getOrThrow()
        let neg = builder.CreateTryUnaryExpression(context.GetInt64Ty(), ExprKind.NEG, value, normal, error, source)
        let add = builder.CreateTryBinaryExpression(context.GetInt64Ty(), ExprKind.ADD, value, value, normal, error, source)
        @Expect(neg.GetExprKind(), ExprKind.TRY_NEG)
        @Expect(add.GetExprKind(), ExprKind.TRY_ADD)
        @Expect(ExprKindName(neg.GetExprKind()), "TryNeg")
        @Expect(ExprKindName(add.GetExprKind()), "TryAdd")
        @Expect(neg.GetExprKind() == add.GetExprKind(), false)
        @Expect((neg as UnaryExpressionBase).isSome(), true)
        @Expect((neg as UnaryExpression).isSome(), false)
        @Expect((add as BinaryExpressionBase).isSome(), true)
        @Expect((add as BinaryExpression).isSome(), false)
        @Expect(neg.GetOpKind(), ExprKind.NEG)
        @Expect(add.GetOpKind(), ExprKind.ADD)
    }

    @TestCase
    public func ReplaceOneDuplicateSuccessorKeepsPredecessor(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let fn = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>(), context.GetUnitTy()), "dup-successor")
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let source = builder.CreateBlock(body)
        let target = builder.CreateBlock(body)
        let other = builder.CreateBlock(body)
        body.SetEntryBlock(source)
        let value = builder.CreateConstant(context.GetInt64Ty(), IntLiteral(3), source).GetResult().getOrThrow()
        let add = builder.CreateTryBinaryExpression(context.GetInt64Ty(), ExprKind.ADD, value, value, target, target, source)
        source.AppendExpression(add)
        @Expect(target.GetPredecessors().size, 1)
        add.ReplaceSuccessor(0, other)
        @Expect(add.GetSuccessor(0).nodeId, other.nodeId)
        @Expect(add.GetSuccessor(1).nodeId, target.nodeId)
        @Expect(target.GetPredecessors().size, 1)
        @Expect(other.GetPredecessors().size, 1)
        add.ReplaceSuccessor(1, other)
        @Expect(target.GetPredecessors().size, 0)
        @Expect(other.GetPredecessors().size, 1)
    }
}

@Test
public class ExpressionSuccessorsTest {
    @TestCase
    public func EmptyAndOrdinaryOperandsHaveNoSuccessors(): Unit {
        let context = CHIRContext()
        let empty = Expression(ExprKind.ADD, ArrayList<Value>(), None)
        let ordinary = Expression(ExprKind.ADD,
            ArrayList<Value>([IntLiteral(context.GetInt64Ty(), 1), IntLiteral(context.GetInt64Ty(), 2)]), None)
        @Expect(empty.GetSuccessors().size, 0)
        @Expect(ordinary.GetSuccessors().size, 0)
        @Expect(ordinary.GetOperands().size, 2)
    }

    @TestCase
    public func MixedOperandsPreserveOrderDuplicatesAndOwnership(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let fn = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>(), context.GetUnitTy()), "successors")
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let source = builder.CreateBlock(body)
        let first = builder.CreateBlock(body)
        let second = builder.CreateBlock(body)
        let control = builder.CreateBlock(body)
        body.SetEntryBlock(source)
        let literal = IntLiteral(context.GetInt64Ty(), 7)
        let inputs = ArrayList<Value>([literal, second, literal, first, second, literal])
        let expr = Expression(ExprKind.ADD, inputs, None)
        inputs.clear()
        let successors = expr.GetSuccessors()
        @Expect(successors.size, 3)
        if (successors.size == 3) {
            @Expect(successors[0].nodeId, second.nodeId)
            @Expect(successors[1].nodeId, first.nodeId)
            @Expect(successors[2].nodeId, second.nodeId)
        }
        successors.clear()
        @Expect(expr.GetSuccessors().size, 3)
        @Expect(expr.GetOperands().size, 6)
        let term = builder.CreateMultiBranch(literal, second, ArrayList<UInt64>([1, 2]),
            ArrayList<Block>([first, second]), source)
        source.AppendExpression(term)
        term.SyncSuccessorPredecessors()
        @Expect(first.GetPredecessors().contains(source), true)
        @Expect(second.GetPredecessors().contains(source), true)
        @Expect(second.GetPredecessors().size, 1)
        @Expect(control.GetPredecessors().size, 0)
        term.DetachFromBlockOnly()
        @Expect(term.GetParentBlock().isNone(), true)
        @Expect(first.GetPredecessors().size, 0)
        @Expect(second.GetPredecessors().size, 0)
        @Expect(source.GetExpressions().size, 0)
        @Expect(expr.GetParentBlock().isNone(), true)
        @Expect(expr.GetOperands().size, 6)
    }

    @TestCase
    public func ThrowingTerminatorMaintainsBothEdgesThroughInsertionAndDetach(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let fn = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>(), context.GetUnitTy()), "throw-successors")
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let source = builder.CreateBlock(body)
        let normal = builder.CreateBlock(body)
        let error = builder.CreateBlock(body)
        body.SetEntryBlock(source)
        let value = builder.CreateConstant(context.GetInt64Ty(), IntLiteral(7), source).GetResult().getOrThrow()
        let expr = builder.CreateTryNumericCast(context.GetInt32Ty(), value, normal, error, source)
        let successors = expr.GetSuccessors()
        @Expect(successors.size, 2)
        if (successors.size == 2) {
            @Expect(successors[0].nodeId, normal.nodeId)
            @Expect(successors[1].nodeId, error.nodeId)
        }
        source.AppendExpression(expr)
        @Expect(normal.GetPredecessors().contains(source), true)
        @Expect(error.GetPredecessors().contains(source), true)
        @Expect(source.GetTerminator().getOrThrow().nodeId, expr.nodeId)
        expr.DetachFromBlockOnly()
        @Expect(normal.GetPredecessors().size, 0)
        @Expect(error.GetPredecessors().size, 0)
        @Expect(source.GetExpressions().size, 0)
    }
}
