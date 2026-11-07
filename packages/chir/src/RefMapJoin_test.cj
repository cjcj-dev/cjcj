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
}
