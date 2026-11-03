package cjcj::compiler_unittest

import cjcj::chir.{AbstractObject, ConstValueDomain, FullStatePool, Ref, Value}
import std.unittest.*
import std.unittest.testmacro.*

// FullStatePool keeps keys and domains in insertion order with a nodeId index
// (chir/src/ValueState.cj). These cases pin the observable state-pool contract the
// value analyses rely on: entry order, which domain object survives CopyFrom, that
// Join visits every rhs entry, and that Clear leaves no stale index behind.
@Test
public class FullStatePoolSemanticsTest {
    private func MakePool(keys: Array<Value>, tops: Array<Bool>): FullStatePool<ConstValueDomain> {
        let pool = FullStatePool<ConstValueDomain>()
        for (i in 0..keys.size) {
            pool.Insert(keys[i], ConstValueDomain.Create(tops[i]))
        }
        return pool
    }

    // Order and index agree: GetAt(i) lists exactly `expected`, and At(key) finds the
    // same domain object that GetAt reports for that position.
    private func HasOrder(pool: FullStatePool<ConstValueDomain>, expected: Array<Value>): Bool {
        if (pool.Size() != expected.size) {
            return false
        }
        for (i in 0..expected.size) {
            let (key, domain) = pool.GetAt(i)
            if (key.nodeId != expected[i].nodeId || !pool.Contains(expected[i])) {
                return false
            }
            if (!refEq(pool.At(expected[i]), domain)) {
                return false
            }
        }
        return true
    }

    @TestCase
    public func copyFromSameLayoutUpdatesExistingDomains(): Unit {
        let a: Value = AbstractObject("a")
        let b: Value = AbstractObject("b")
        let lhs = MakePool([a, b], [false, false])
        let rhs = MakePool([a, b], [true, false])
        let domainA = lhs.At(a)
        let domainB = lhs.At(b)
        lhs.CopyFrom(rhs)
        @Expect(HasOrder(lhs, [a, b]))
        @Expect(refEq(lhs.At(a), domainA))
        @Expect(refEq(lhs.At(b), domainB))
        @Expect(lhs.At(a).IsTop())
        @Expect(lhs.At(b).IsBottom())
        @Expect(!refEq(lhs.At(a), rhs.At(a)))
    }

    @TestCase
    public func copyFromDifferentLayoutTakesRhsOrderKeepsSharedDomains(): Unit {
        let a: Value = AbstractObject("a")
        let b: Value = AbstractObject("b")
        let c: Value = AbstractObject("c")
        let d: Value = AbstractObject("d")
        let lhs = MakePool([a, b, c], [false, true, false])
        let rhs = MakePool([c, d, a], [true, true, false])
        let domainA = lhs.At(a)
        let domainC = lhs.At(c)
        let rhsD = rhs.At(d)
        lhs.CopyFrom(rhs)
        @Expect(HasOrder(lhs, [c, d, a]))
        @Expect(!lhs.Contains(b))
        @Expect(lhs.Find(b).isNone())
        @Expect(refEq(lhs.At(c), domainC))
        @Expect(lhs.At(c).IsTop())
        @Expect(refEq(lhs.At(a), domainA))
        @Expect(lhs.At(a).IsBottom())
        @Expect(!refEq(lhs.At(d), rhsD))
        @Expect(lhs.At(d).IsTop())
        // The rebuilt index must accept a new key at the end.
        lhs.Insert(b, ConstValueDomain.Create(false))
        @Expect(HasOrder(lhs, [c, d, a, b]))
        // Same keys, different order is a layout change too.
        let swapped = MakePool([a, b], [true, false])
        let reversed = MakePool([b, a], [true, false])
        let swappedA = swapped.At(a)
        swapped.CopyFrom(reversed)
        @Expect(HasOrder(swapped, [b, a]))
        @Expect(refEq(swapped.At(a), swappedA))
        @Expect(swapped.At(a).IsBottom())
        @Expect(swapped.At(b).IsTop())
    }

    @TestCase
    public func copyFromSelfKeepsState(): Unit {
        let a: Value = AbstractObject("a")
        let b: Value = AbstractObject("b")
        let pool = MakePool([a, b], [true, false])
        let domainA = pool.At(a)
        pool.CopyFrom(pool)
        @Expect(HasOrder(pool, [a, b]))
        @Expect(refEq(pool.At(a), domainA))
        @Expect(pool.At(a).IsTop())
        @Expect(pool.At(b).IsBottom())
    }

    @TestCase
    public func cloneHasSameOrderAndIndependentDomains(): Unit {
        let a: Value = AbstractObject("a")
        let b: Value = AbstractObject("b")
        let pool = MakePool([a, b], [true, false])
        let copy = pool.Clone()
        @Expect(HasOrder(copy, [a, b]))
        @Expect(!refEq(copy.At(a), pool.At(a)))
        @Expect(copy.At(a).IsTop())
        copy.At(b).SetSelfToBound(true)
        @Expect(pool.At(b).IsBottom())
    }

    @TestCase
    public func joinVisitsEveryRhsEntry(): Unit {
        let a: Value = AbstractObject("a")
        let b: Value = AbstractObject("b")
        let c: Value = AbstractObject("c")
        // An early change must not stop later entries from being joined.
        let lhs = MakePool([a, b], [false, false])
        let rhs = MakePool([a, b, c], [true, true, false])
        @Expect(lhs.Join(rhs))
        @Expect(lhs.At(a).IsTop())
        @Expect(lhs.At(b).IsTop())
        @Expect(HasOrder(lhs, [a, b, c]))
        @Expect(lhs.At(c).IsBottom())
        @Expect(!refEq(lhs.At(c), rhs.At(c)))
        @Expect(!lhs.Join(rhs))
        // Only the last entry changes: Join still reports a change.
        let late = MakePool([a, b], [true, false])
        @Expect(late.Join(MakePool([a, b], [true, true])))
        @Expect(late.At(b).IsTop())
        // Different rhs order: an append shifts positions, lookups go through the index.
        let mixed = MakePool([a, b], [false, false])
        @Expect(mixed.Join(MakePool([c, b, a], [false, true, true])))
        @Expect(HasOrder(mixed, [a, b, c]))
        @Expect(mixed.At(a).IsTop())
        @Expect(mixed.At(b).IsTop())
        @Expect(mixed.At(c).IsBottom())
    }

    @TestCase
    public func clearThenReinsertStartsFresh(): Unit {
        let a: Value = AbstractObject("a")
        let b: Value = AbstractObject("b")
        let c: Value = AbstractObject("c")
        let pool = MakePool([a, b], [true, false])
        pool.Clear()
        @Expect(pool.Size(), 0)
        @Expect(!pool.Contains(a))
        @Expect(pool.Find(b).isNone())
        pool.Insert(b, ConstValueDomain.Create(true))
        pool.Insert(a, ConstValueDomain.Create(false))
        @Expect(HasOrder(pool, [b, a]))
        @Expect(pool.At(b).IsTop())
        @Expect(pool.At(a).IsBottom())
        pool.SetBound(c, true)
        @Expect(HasOrder(pool, [b, a, c]))
        pool.SetRef(a, Ref("r", false))
        @Expect(HasOrder(pool, [b, a, c]))
        @Expect(pool.At(a).IsRef())
    }
}
