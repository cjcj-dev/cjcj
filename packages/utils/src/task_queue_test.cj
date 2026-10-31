package cjcj::utils

import std.collection.*
import std.sync.AtomicInt64
import std.unittest.*
import std.unittest.testmacro.*

@Test
class TaskQueueTest {
    @TestCase
    func failedTaskRetainsSiblingCompletionAndFailure(): Unit {
        let count = AtomicInt64(0)
        let queue = TaskQueue(2)
        let failing = queue.AddTask<Int64>({ =>
            count.fetchAdd(1)
            throw IllegalStateException("expected queue failure")
        }, priority: 2u64)
        let sibling = queue.AddTask<Int64>({ =>
            sleep(10 * Duration.millisecond)
            count.fetchAdd(1)
            42
        }, priority: 1u64)
        queue.RunAndWaitForAllTasksCompleted()
        @Expect(count.load(), 2)
        var failure = ""
        try { let _ = failing.get() } catch (e: Exception) { failure = e.message }
        @Expect(failure, "expected queue failure")
        @Expect(sibling.get(), 42)
    }

    @TestCase
    func taskResultGetConsumesValue(): Unit {
        let result = TaskResult<Int64>()
        result.complete(42)

        @Expect(result.get(), 42)

        var secondGetThrew = false
        try {
            let _ = result.get()
        } catch (_: Exception) {
            secondGetThrew = true
        }
        @Expect(secondGetThrew, true)
    }
}

// Match the parser result's two managed references plus Int64 without pulling
// parser state, files, diagnostics or native callbacks into this consumer.
private type TaskQueueReferencePair = (TaskQueueCaptureOwner, TaskQueueCaptureOwner, Int64)

private class TaskQueueCaptureOwner {
    let id: Int64
    var calls: Int64 = 0
    var marker: Int64

    init(id: Int64) {
        this.id = id
        this.marker = id
    }

    func invoke(): TaskQueueReferencePair {
        calls++
        return (this, this, id)
    }
}

// The caller retains no separate owner array: before execution the task closure
// is responsible for retaining its receiver, as in ParseFilesWithTaskQueue.
private func MakeTaskQueueReferencePair(id: Int64): () -> TaskQueueReferencePair {
    let owner = TaskQueueCaptureOwner(id)
    return { => owner.invoke() }
}

@Test
class TaskQueuePublicationTest {
    private func expectPair(pair: TaskQueueReferencePair, id: Int64): Unit {
        @Expect(pair[0].id, id)
        @Expect(pair[1].id, id)
        @Expect(pair[2], id)
        @Expect(pair[0].calls, 1)
        @Expect(pair[1].calls, 1)
        @Expect(pair[0].marker, id)
        // Verify alias preservation without comparing tagged machine addresses.
        pair[0].marker = id + 1000
        @Expect(pair[1].marker, id + 1000)
    }

    @TestCase
    func directGenericPairControl(): Unit {
        let producer = MakeTaskQueueReferencePair(42)
        let result = TaskResult<TaskQueueReferencePair>()
        result.complete(producer())
        expectPair(result.get(), 42)
    }

    private func checkQueuedPairs(permuted: Bool): Unit {
        let queue = TaskQueue(4)
        let results = ArrayList<TaskResult<TaskQueueReferencePair>>()
        for (id in 0..18) {
            // 7 is coprime to 18: this is a permutation with distinct priorities.
            // Equal priorities retain the production parser's default input.
            let priority = if (permuted) { UInt64((id * 7) % 18) } else { 0u64 }
            results.add(queue.AddTask<TaskQueueReferencePair>(
                MakeTaskQueueReferencePair(id), priority: priority))
        }
        queue.RunAndWaitForAllTasksCompleted()
        @Expect(results.size, 18)
        // Result handles remain in submission order; worker order is unconstrained.
        for (id in 0..18) {
            expectPair(results[id].get(), id)
        }
    }

    @TestCase
    func equalPriorityPreservesCapturedReceiverAndPair(): Unit {
        checkQueuedPairs(false)
    }

    @TestCase
    func permutedPriorityPreservesCapturedReceiverAndPair(): Unit {
        checkQueuedPairs(true)
    }
}
