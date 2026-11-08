package cjcj::chir

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

private func NewRefMapJoinState(): ConstDomain {
    let state = ConstDomain(ChildrenMap(), AllocatedRefMap(), None, AllocatedObjMap(),
        ArrayList<Ref>(), ArrayList<AbstractObject>())
    state.SetReachable(true)
    return state
}

@Test
public class RefMapJoinTest {
    @TestCase
    public func ExistingTopIsNotOverwrittenByIncomingNarrowRef(): Unit {
        let lhs = NewRefMapJoinState()
        let rhs = NewRefMapJoinState()
        let key = Ref("key", false)
        let narrow = Ref("narrow", false)
        let top = Ref.GetTopRefInstance()
        lhs.refMap.Set(key, RefMapValue.RefTarget(top))
        rhs.refMap.Set(key, RefMapValue.RefTarget(narrow))
        @Expect(lhs.Join(rhs), false)
        @Expect(lhs.refMap.Size(), 1)
        let actual = match (lhs.refMap.GetAt(0)[1]) {
            case RefMapValue.RefTarget(value) => value
            case _ => throw IllegalStateException("Expected reference target")
        }
        @Expect(refEq(actual, top), true)
        let incoming = match (rhs.refMap.GetAt(0)[1]) {
            case RefMapValue.RefTarget(value) => value
            case _ => throw IllegalStateException("Expected incoming reference target")
        }
        @Expect(refEq(incoming, narrow), true)
    }

    @TestCase
    public func MixedJoinPreservesIdentityOrderAndRepeatedJoinStability(): Unit {
        let lhs = NewRefMapJoinState()
        let rhs = NewRefMapJoinState()
        // Equal display IDs are distinct Ref identities, as in the production map.
        let first = Ref("same-id", false)
        let second = Ref("same-id", false)
        let third = Ref("third", false)
        let narrow = Ref("value", false)
        let top = Ref.GetTopRefInstance()
        let obj = AbstractObject.GetTopObjInstance()
        lhs.refMap.Set(first, RefMapValue.RefTarget(narrow))
        rhs.refMap.Set(first, RefMapValue.RefTarget(top))
        rhs.refMap.Set(second, RefMapValue.ObjectTarget(obj))
        rhs.refMap.Set(third, RefMapValue.RefTarget(narrow))
        @Expect(lhs.Join(rhs), true)
        @Expect(lhs.refMap.Size(), 3)
        @Expect(refEq(lhs.refMap.GetAt(0)[0], first), true)
        @Expect(refEq(lhs.refMap.GetAt(1)[0], second), true)
        @Expect(refEq(lhs.refMap.GetAt(2)[0], third), true)
        let joined = match (lhs.refMap.GetAt(0)[1]) {
            case RefMapValue.RefTarget(value) => value
            case _ => throw IllegalStateException("Expected joined reference target")
        }
        @Expect(refEq(joined, top), true)
        let insertedObj = match (lhs.refMap.GetAt(1)[1]) {
            case RefMapValue.ObjectTarget(value) => value
            case _ => throw IllegalStateException("Expected inserted object target")
        }
        @Expect(refEq(insertedObj, obj), true)
        let insertedRef = match (lhs.refMap.GetAt(2)[1]) {
            case RefMapValue.RefTarget(value) => value
            case _ => throw IllegalStateException("Expected inserted reference target")
        }
        @Expect(refEq(insertedRef, narrow), true)
        @Expect(lhs.Join(rhs), false)
        @Expect(lhs.refMap.Size(), 3)
        @Expect(rhs.refMap.Size(), 3)
        @Expect(refEq(rhs.refMap.GetAt(1)[0], second), true)
    }

    @TestCase
    public func UnreachableInputDoesNotInsertAndBottomTargetCopies(): Unit {
        let lhs = NewRefMapJoinState()
        let rhs = NewRefMapJoinState()
        let key = Ref("unreachable", false)
        rhs.refMap.Set(key, RefMapValue.RefTarget(Ref.GetTopRefInstance()))
        rhs.SetReachable(false)
        @Expect(lhs.Join(rhs), false)
        @Expect(lhs.refMap.Size(), 0)
        rhs.SetReachable(true)
        lhs.SetReachable(false)
        @Expect(lhs.Join(rhs), true)
        @Expect(lhs.IsBottom(), false)
        @Expect(lhs.refMap.Size(), 1)
        @Expect(refEq(lhs.refMap.GetAt(0)[0], key), true)
        @Expect(lhs.Join(rhs), false)
    }

    @TestCase
    public func IdentityIndexFollowsInsertCloneCopyClearAndJoin(): Unit {
        let a = Ref("same-id", false)
        let b = Ref("same-id", false)
        let c = Ref("c", false)
        let top = Ref.GetTopRefInstance()
        let map = RefMap()
        map.Set(a, RefMapValue.RefTarget(c))
        map.Set(b, RefMapValue.RefTarget(c))
        map.Set(c, RefMapValue.RefTarget(c))
        // Hit overwrites in place; FindOrInsert hit keeps the value; equal names stay distinct keys.
        map.Set(b, RefMapValue.RefTarget(top))
        @Expect(map.FindOrInsert(a, RefMapValue.RefTarget(top)), Some(0))
        @Expect(map.Size(), 3)
        @Expect(map.Find(a), Some(0))
        @Expect(map.Find(b), Some(1))
        @Expect(map.Find(c), Some(2))
        @Expect(refEq(map.GetAt(1)[0], b), true)
        @Expect(IsRefTarget(map.Get(a), c), true)
        @Expect(IsRefTarget(map.Get(b), top), true)
        // Clone owns its index: appends to the clone are invisible to the source.
        let clone = map.Clone()
        let d = Ref("d", false)
        @Expect(clone.FindOrInsert(d, RefMapValue.RefTarget(top)), Option<Int64>.None)
        @Expect(clone.Find(d), Some(3))
        @Expect(map.Find(d), Option<Int64>.None)
        @Expect(clone.Find(b), Some(1))
        // CopyFrom that permutes and truncates: [a, b, c] <- [c, a].
        let src = RefMap()
        src.Set(c, RefMapValue.RefTarget(top))
        src.Set(a, RefMapValue.RefTarget(c))
        map.CopyFrom(src)
        @Expect(map.Size(), 2)
        @Expect(map.Find(c), Some(0))
        @Expect(map.Find(a), Some(1))
        @Expect(map.Find(b), Option<Int64>.None)
        @Expect(refEq(map.GetAt(0)[0], c), true)
        @Expect(refEq(map.GetAt(1)[0], a), true)
        map.Set(b, RefMapValue.RefTarget(c))
        @Expect(map.Find(b), Some(2))
        // Join into a state whose map came from CopyFrom finds existing keys through the index.
        let lhs = NewRefMapJoinState()
        let rhs = NewRefMapJoinState()
        lhs.refMap.CopyFrom(map)
        rhs.refMap.Set(a, RefMapValue.RefTarget(top))
        rhs.refMap.Set(d, RefMapValue.RefTarget(c))
        @Expect(lhs.Join(rhs), true)
        @Expect(lhs.refMap.Size(), 4)
        @Expect(lhs.refMap.Find(a), Some(1))
        @Expect(IsRefTarget(lhs.refMap.Get(a), top), true)
        @Expect(lhs.refMap.Find(d), Some(3))
        map.Clear()
        @Expect(map.Size(), 0)
        @Expect(map.Find(a), Option<Int64>.None)
        map.Set(c, RefMapValue.RefTarget(top))
        @Expect(map.Find(c), Some(0))
    }
}

private func IsRefTarget(value: Option<RefMapValue>, expected: Ref): Bool {
    return match (value) {
        case Some(RefMapValue.RefTarget(actual)) => refEq(actual, expected)
        case _ => false
    }
}
