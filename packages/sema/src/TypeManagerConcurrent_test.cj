package cjcj::sema

import cjcj::ast.{Ty, TypeKind, GenericParamDecl, SrcIdentifier, ExtendDecl}
import cjcj::utils.{TaskQueue, TaskResult}
import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class TypeManagerConcurrentTest {
    @TestCase
    func bodySnapshotsOwnConstraintsButShareCanonicalTypes(): Unit {
        let parent = TypeManager()
        let parameter = GenericParamDecl()
        parameter.identifier = SrcIdentifier("Element")
        let variable = parent.GetGenericsTy(parameter)
        let integer = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
        let boolean = TypeManager.GetBoolTy()
        parent.constraints.GetOrCreate(variable).ubs.Add(integer)
        parent.constraints.GetOrCreate(variable).ub2Blames.add(TyBlameEntry(integer))
        let originalArray = parent.GetArrayTy(integer, 1u64)
        let extension = ExtendDecl()
        parent.UpdateBuiltInTyExtendDecl(integer, extension)
        let workers = ArrayList<TypeManager>()
        for (ordinal in 0..4) { workers.add(parent.ForkForBody(UInt64(ordinal))) }
        let queue = TaskQueue(4)
        let results = ArrayList<TaskResult<(String, Int64)>>()
        for (worker in workers) {
            results.add(queue.AddTask<(String, Int64)>({ =>
                let bounds = worker.constraints.GetOrCreate(variable)
                bounds.ubs.Clear()
                bounds.ubs.Add(boolean)
                bounds.ub2Blames.clear()
                worker.RemoveExtendFromMap(extension)
                let localVariable = worker.AllocTyVar()
                let identity = worker.GetArrayTy(integer, 1u64).objectId
                (localVariable.name, identity)
            }))
        }
        queue.RunAndWaitForAllTasksCompleted()
        let names = HashSet<String>()
        for (result in results) {
            let observed = result.get()
            names.add(observed[0])
            @Expect(observed[1], originalArray.objectId)
        }
        @Expect(names.size, 4)
        @Expect(parent.constraints.GetOrCreate(variable).ubs.Contains(integer), true)
        @Expect(parent.constraints.GetOrCreate(variable).ubs.Contains(boolean), false)
        @Expect(parent.constraints.GetOrCreate(variable).ub2Blames.size, 1)
        @Expect(parent.GetBuiltinTyExtends(integer).size, 1)
        for (worker in workers) {
            @Expect(worker.GetBuiltinTyExtends(integer).isEmpty(), true)
            @Expect(worker.constraints.GetOrCreate(variable).ubs.Contains(boolean), true)
            worker.Clear()
        }
        // Clearing a body manager must not invalidate the parent's interner.
        @Expect(parent.GetArrayTy(integer, 1u64).objectId, originalArray.objectId)
    }

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
