package cjcj::sema

import cjcj::ast.{Ty, TypeKind}
import cjcj::utils.{TaskQueue, TaskResult}
import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class TypeManagerConcurrentTest {
    @TestCase
    func concurrentPublicTypeFactoriesKeepCanonicalIdentity(): Unit {
        let manager = TypeManager()
        let integer = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
        let queue = TaskQueue(4)
        let results = ArrayList<TaskResult<ArrayList<Int64>>>()
        for (_ in 0..16) {
            results.add(queue.AddTask<ArrayList<Int64>>({ =>
                let ids = ArrayList<Int64>()
                for (_ in 0..16) {
                    for (dimension in 1..9) {
                        let argument: Ty = manager.GetArrayTy(integer, UInt64(dimension))
                        ids.add(manager.GetFunctionTy([argument], integer).objectId)
                    }
                }
                ids
            }))
        }
        queue.RunAndWaitForAllTasksCompleted()
        let expected = results[0].get()
        @Expect(expected.size, 128)
        let identities = HashSet<Int64>()
        for (index in 0..8) { identities.add(expected[index]) }
        @Expect(identities.size, 8)
        for (index in 0..expected.size) { @Expect(expected[index], expected[index % 8]) }
        for (index in 1..results.size) {
            let observed = results[index].get()
            @Expect(observed.size, expected.size)
            for (slot in 0..observed.size) { @Expect(observed[slot], expected[slot]) }
        }
        manager.Clear()
        let argument: Ty = manager.GetArrayTy(integer, 1u64)
        let fresh = manager.GetFunctionTy([argument], integer)
        @Expect(fresh.objectId != expected[0], true)
    }
}
