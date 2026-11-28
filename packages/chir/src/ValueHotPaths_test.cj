package cjcj::chir

import std.collection.*
import std.sync.SyncCounter
import std.time.MonoTime
import std.unittest.*
import std.unittest.testmacro.*

private func MakeUserBlock(builder: CHIRBuilder, name: String): Block {
    let ctx = builder.context
    let fn = builder.CreateFunction(ctx.GetFuncTy(ArrayList<Type>(), ctx.GetUnitTy()), name)
    let body = builder.CreateBlockGroup(fn)
    fn.InitBody(body)
    let block = builder.CreateBlock(body)
    body.SetEntryBlock(block)
    return block
}

private func AttachUser(block: Option<Block>, operands: ArrayList<Value>): Expression {
    let expr = Expression(ExprKind.TUPLE, operands, block)
    expr.ConnectOperandsAndGroups()
    return expr
}

private func UserIds(value: Value): Array<Int64> {
    let ids = ArrayList<Int64>()
    for (user in value.GetUsers()) { ids.add(user.nodeId) }
    return ids.toArray()
}

@Test
class ValueHotPathsTest {
    @TestCase
    func countHonorsGlobalUserLock(): Unit {
        for (kind in [ValueKind.KIND_GLOBALVAR, ValueKind.KIND_FUNC]) {
            let value = Value(None, "", kind)
            let user = AttachUser(None, ArrayList<Value>([value, value]))
            let gate = SyncCounter(1)
            let reader = synchronized(value.GetUserMutex().getOrThrow()) {
                let reading = spawn {
                    gate.dec()
                    value.GetUsersCount()
                }
                gate.waitUntilZero()
                var blocked = false
                try {
                    let _ = reading.get(250 * Duration.millisecond)
                } catch (_: TimeoutException) {
                    blocked = true
                }
                @Expect(blocked, true)
                reading
            }
            @Expect(reader.get(), 2)
            let writer = spawn {
                for (_ in 0..32) { value.AddUserOnly(user) }
            }
            writer.get()
            @Expect(value.GetUsersCount(), 34)
            @Expect(value.GetUsersCount(), value.GetUsers().size)
        }
    }

    @TestCase
    func loweringCapturesWholeExistingPrefix(): Unit {
        let b = CHIRBuilder(CHIRContext())
        let pkg = b.CreatePackage("lowering_prefix")
        let ctx = b.context
        let fn = b.CreateFunction(ctx.GetFuncTy(ArrayList<Type>(), ctx.GetUnitTy()), "callee")
        let gv = b.CreateGlobalVar(ctx.GetRefTy(ctx.GetInt64Ty()), "shared")
        let _ = AttachUser(None, ArrayList<Value>([fn, gv, gv]))
        let prefixes = CaptureLoweringUserPrefixes(pkg)
        let _ = AttachUser(None, ArrayList<Value>([fn, fn, gv]))
        @Assert(prefixes.size, 2)
        @Expect(refEq(prefixes[0][0], fn))
        @Expect(refEq(prefixes[1][0], gv))
        @Expect(prefixes[0][1], 1)
        @Expect(prefixes[1][1], 2)
        @Expect(fn.GetUsersCount(), 3)
        @Expect(gv.GetUsersCount(), 3)
    }

    @TestCase
    func removeAndMovePreserveStableMultiplicity(): Unit {
        let value = Value(None, "", ValueKind.KIND_GLOBALVAR)
        let a = AttachUser(None, ArrayList<Value>([value]))
        let picked = AttachUser(None, ArrayList<Value>([value, value]))
        let b = AttachUser(None, ArrayList<Value>([value]))
        value.AddUserOnly(picked)
        let c = AttachUser(None, ArrayList<Value>([value, value]))
        value.RemoveUserOccurrenceOnly(picked)
        @Expect(UserIds(value),
            [a.nodeId, picked.nodeId, b.nodeId, picked.nodeId, c.nodeId, c.nodeId])
        value.MoveUserToTail(picked)
        @Expect(UserIds(value),
            [a.nodeId, b.nodeId, c.nodeId, c.nodeId, picked.nodeId, picked.nodeId])
        value.RemoveUserOnly(c)
        @Expect(UserIds(value),
            [a.nodeId, b.nodeId, picked.nodeId, picked.nodeId])
    }

    @TestCase
    func scopedHighFanoutReplacePreservesBothUserOrders(): Unit {
        let b = CHIRBuilder(CHIRContext())
        let _ = b.CreatePackage("rewrite_users")
        let inside = MakeUserBlock(b, "inside")
        let outside = MakeUserBlock(b, "outside")
        let old = Value(None, "", ValueKind.KIND_GLOBALVAR)
        let replacement = Value(None, "", ValueKind.KIND_GLOBALVAR)
        let existing = AttachUser(outside, ArrayList<Value>([replacement]))
        let detached = AttachUser(None, ArrayList<Value>([old]))
        let kept = ArrayList<Int64>([detached.nodeId])
        let rewritten = ArrayList<Int64>([existing.nodeId])
        let moved = ArrayList<Expression>()
        for (_ in 0..48) {
            let inScope = AttachUser(inside, ArrayList<Value>([old, replacement]))
            let outOfScope = AttachUser(outside, ArrayList<Value>([old, old]))
            kept.add(outOfScope.nodeId)
            kept.add(outOfScope.nodeId)
            rewritten.add(inScope.nodeId)
            moved.add(inScope)
            // Leave repeated operands interleaved with unrelated uses.
            inScope.AppendOperand(old)
        }
        for (inScope in moved) {
            rewritten.add(inScope.nodeId)
            rewritten.add(inScope.nodeId)
        }

        old.ReplaceWith(replacement, inside.GetParentBlockGroup())
        let remaining = UserIds(old)
        @Expect(remaining, kept.toArray())
        @Expect(UserIds(replacement), rewritten.toArray())
        for (expr in moved) {
            @Expect(expr.GetOperand(0).nodeId, replacement.nodeId)
            @Expect(expr.GetOperand(2).nodeId, replacement.nodeId)
        }
        replaceHighFanoutSuccessors(b, inside)
    }

    private func replaceHighFanoutSuccessors(builder: CHIRBuilder, entry: Block): Unit {
        let group = entry.GetParentBlockGroup().getOrThrow()
        let oldTarget = builder.CreateBlock(group)
        let newTarget = builder.CreateBlock(group)
        let predecessors = ArrayList<Block>()
        let terminators = ArrayList<Int64>()
        let ty = builder.context.GetInt64Ty()
        for (_ in 0..18) {
            let source = builder.CreateBlock(group)
            let value = builder.CreateConstant(ty, IntLiteral(1), source)
            let operand = value.GetResult().getOrThrow()
            let term = builder.CreateTryBinaryExpression(ty, ExprKind.ADD, operand, operand, oldTarget, oldTarget, source)
            source.AppendExpressions(ArrayList<Expression>([value, term]))
            predecessors.add(source)
            terminators.add(term.nodeId)
        }
        @Expect(oldTarget.GetUsersRef().size, 54)
        @Expect(oldTarget.GetPredecessors().size, 18)

        oldTarget.ReplaceWith(newTarget)
        @Expect(oldTarget.GetUsersRef().isEmpty())
        @Expect(oldTarget.GetPredecessors().isEmpty())
        @Expect(UserIds(newTarget), terminators.toArray())
        @Assert(newTarget.GetPredecessors().size, predecessors.size)
        for (idx in 0..predecessors.size) {
            let pred = newTarget.GetPredecessorsRef()[idx]
            @Expect(refEq(pred, predecessors[idx]))
            let term = pred.GetTerminator().getOrThrow()
            @Expect(refEq(term.GetSuccessor(0), newTarget))
            @Expect(refEq(term.GetSuccessor(1), newTarget))
        }
    }

    @TestCase
    func orderLargeUserSuffixStably(): Unit {
        let b = CHIRBuilder(CHIRContext())
        let _ = b.CreatePackage("ordered_users")
        let early = MakeUserBlock(b, "early")
        let late = MakeUserBlock(b, "late")
        let target = Value(None, "", ValueKind.KIND_FUNC)
        let prefix = AttachUser(None, ArrayList<Value>([target, target]))
        let earlyUses = ArrayList<Int64>()
        let lateUses = ArrayList<Int64>()
        for (_ in 0..4096) {
            let l = AttachUser(late, ArrayList<Value>([target]))
            let e = AttachUser(early, ArrayList<Value>([target, target]))
            lateUses.add(l.nodeId)
            earlyUses.add(e.nodeId)
            earlyUses.add(e.nodeId)
        }
        let ownerOrder = HashMap<Int64, Int64>()
        ownerOrder[early.GetTopLevelFunc().getOrThrow().nodeId] = 0
        ownerOrder[late.GetTopLevelFunc().getOrThrow().nodeId] = 1
        let prefixSize = 2
        let start = MonoTime.now()
        target.OrderNewUsers(prefixSize, ownerOrder)
        let elapsed = (MonoTime.now() - start).toNanoseconds()
        println("OrderNewUsers suffix=${earlyUses.size + lateUses.size} ns=${elapsed}")
        let expected = ArrayList<Int64>([prefix.nodeId, prefix.nodeId])
        expected.add(all: earlyUses)
        expected.add(all: lateUses)
        let actual = UserIds(target)
        @Expect(actual == expected.toArray())
    }
}
