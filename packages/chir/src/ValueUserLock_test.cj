package cjcj::chir

import std.collection.*
import std.sync.SyncCounter
import std.unittest.*
import std.unittest.testmacro.*

@Test
class ValueUserLockTest {
    @TestCase
    func localKindsHaveNoMutex(): Unit {
        for (kind in [ValueKind.KIND_LOCALVAR, ValueKind.KIND_BLOCK, ValueKind.KIND_BLOCK_GROUP,
            ValueKind.KIND_PARAMETER, ValueKind.KIND_LITERAL]) {
            let value = Value(None, "", kind)
            @Expect(value.GetUserMutex().isNone(), true)
        }
        let local = Value(None, "", ValueKind.KIND_LOCALVAR)
        let user = Expression(ExprKind.CONSTANT, ArrayList<Value>(0), None)
        local.AddUserOnly(user)
        local.MoveUserToTail(user)
        @Expect(local.GetUsers().size, 1)
        local.RemoveUserOccurrenceOnly(user)
        @Expect(local.GetUsers().size, 0)
    }

    @TestCase
    func globalKindsSerializeUserWrites(): Unit {
        for (kind in [ValueKind.KIND_GLOBALVAR, ValueKind.KIND_FUNC]) {
            let shared = Value(None, "", kind)
            let user = Expression(ExprKind.CONSTANT, ArrayList<Value>(0), None)
            let gate = SyncCounter(1)
            let mutex = shared.GetUserMutex().getOrThrow()
            let added = synchronized(mutex) {
                let writer = spawn {
                    gate.dec()
                    shared.AddUserOnly(user)
                }
                gate.waitUntilZero()
                var waited = false
                try {
                    writer.get(250 * Duration.millisecond)
                } catch (_: TimeoutException) {
                    waited = true
                }
                @Expect(waited, true)
                writer
            }
            added.get()
            @Expect(shared.GetUsers().size, 1)
        }
    }
}
