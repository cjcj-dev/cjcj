package cjcj::chir

import std.collection.ArrayList
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class LazyBlockGroupsTest {
    @TestCase
    public func emptyGroupsRemainAbsentAndSnapshotsAreIndependent(): Unit {
        let ordinary = Expression(ExprKind.CONSTANT, ArrayList<Value>(0), None)
        let explicit = Expression(ExprKind.CONSTANT, ArrayList<Value>(0), ArrayList<BlockGroup>(0), None)
        for (expr in [ordinary, explicit]) {
            expr.ConnectOperandsAndGroups()
            @Expect(expr.GetBlockGroupsOrNone().isNone(), true)
            @Expect(expr.GetNumOfBlockGroups(), 0)
            let snapshot = expr.GetBlockGroups()
            @Expect(snapshot.capacity, 0)
            snapshot.add(BlockGroup("snapshot"))
            @Expect(expr.GetNumOfBlockGroups(), 0)
            @Expect(expr.GetBlockGroups().size, 0)
        }
    }

    @TestCase
    public func connectingAndAppendingGroupsPreserveOwnerAndOrder(): Unit {
        let first = BlockGroup("first")
        let second = BlockGroup("second")
        let input = ArrayList<BlockGroup>(1)
        input.add(first)
        let expr = Expression(ExprKind.FORIN_RANGE, ArrayList<Value>(0), input, None)
        input.clear()
        @Assert(first.GetOwnerExpression().isNone())
        expr.ConnectOperandsAndGroups()
        expr.AppendBlockGroup(second)
        @Assert(expr.GetNumOfBlockGroups(), 2)
        @Expect(refEq(expr.GetBlockGroup(0), first), true)
        @Expect(refEq(expr.GetBlockGroup(1), second), true)
        @Expect(first.GetOwnerExpression().map({ owner => refEq(owner, expr) }) ?? false, true)
        @Expect(second.GetOwnerExpression().map({ owner => refEq(owner, expr) }) ?? false, true)
        let snapshot = expr.GetBlockGroups()
        expr.ClearBlockGroups()
        @Expect(snapshot.size, 2)
        @Expect(expr.GetBlockGroupsOrNone().isNone(), true)
    }
}
