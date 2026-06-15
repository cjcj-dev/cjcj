package cangjie_compiler::utils

import std.collection.*
import std.sort.*

private class QueuedTask {
    let fn: () -> Unit
    let priority: UInt64
    let order: Int64

    init(fn: () -> Unit, priority: UInt64, order: Int64) {
        this.fn = fn
        this.priority = priority
        this.order = order
    }
}

public class TaskResult<T> {
    private var completed = false
    private var value: Option<T> = None

    public init() {}

    public func complete(v: T): Unit {
        value = v
        completed = true
    }

    public func get(): T {
        if (!completed) {
            throw IllegalStateException("task result requested before task completion")
        }
        return value.getOrThrow()
    }

    public func isCompleted(): Bool {
        return completed
    }
}

public class TaskQueue {
    private let tasks = ArrayList<QueuedTask>()
    private var isStarted = false
    private let threadsNum: Int64

    public init(threadsNum: Int64) {
        this.threadsNum = if (threadsNum > 0) { threadsNum } else { 1 }
    }

    public func AddTask<T>(fn: () -> T, priority!: UInt64 = 0u64): TaskResult<T> {
        CJC_ASSERT_WITH_MSG(!isStarted, "Do not add new tasks while executing.")
        let result = TaskResult<T>()
        let order = tasks.size
        tasks.add(QueuedTask({ =>
            result.complete(fn())
        }, priority, order))
        return result
    }

    public func RunInBackground(): Unit {
        RunAndWaitForAllTasksCompleted()
    }

    public func WaitForAllTasksCompleted(): Unit {
    }

    public func RunAndWaitForAllTasksCompleted(): Unit {
        if (tasks.isEmpty()) {
            return
        }
        isStarted = true
        sort(tasks, by: { left: QueuedTask, right: QueuedTask =>
            if (left.priority > right.priority) {
                Ordering.LT
            } else if (left.priority < right.priority) {
                Ordering.GT
            } else {
                left.order.compare(right.order)
            }
        }, stable: true)
        while (!tasks.isEmpty()) {
            let task = tasks[0]
            tasks.remove(at: 0)
            task.fn()
        }
    }
}
