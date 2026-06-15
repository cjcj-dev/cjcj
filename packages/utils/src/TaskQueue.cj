package cangjie_compiler::utils

import std.collection.*
import std.sort.*
import std.sync.*

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
    private var failure: Option<Exception> = None
    private let counter = SyncCounter(1)

    public init() {}

    public func complete(v: T): Unit {
        value = v
        completed = true
        counter.dec()
    }

    public func fail(e: Exception): Unit {
        failure = e
        completed = true
        counter.dec()
    }

    public func get(): T {
        counter.waitUntilZero()
        if (let Some(e) <- failure) {
            throw e
        }
        return value.getOrThrow()
    }

    public func isCompleted(): Bool {
        return completed
    }
}

public class TaskQueue {
    private let tasks = ArrayList<QueuedTask>()
    private let threads = ArrayList<Future<Unit>>()
    private let mutex = Mutex()
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
            try {
                result.complete(fn())
            } catch (e: Exception) {
                result.fail(e)
                throw e
            }
        }, priority, order))
        return result
    }

    public func RunInBackground(): Unit {
        if (tasks.isEmpty()) {
            return
        }
        createThreads()
    }

    public func WaitForAllTasksCompleted(): Unit {
        for (thread in threads) {
            thread.get()
        }
        threads.clear()
    }

    public func RunAndWaitForAllTasksCompleted(): Unit {
        if (tasks.isEmpty()) {
            return
        }
        createThreads()
        WaitForAllTasksCompleted()
    }

    private func createThreads(): Unit {
        if (isStarted) {
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
        let fixedThreadsNum = if (tasks.size < threadsNum) { tasks.size } else { threadsNum }
        for (_ in 0..fixedThreadsNum) {
            threads.add(spawn {
                doTask()
            })
        }
    }

    private func popTask(): Option<QueuedTask> {
        synchronized(mutex) {
            if (tasks.isEmpty()) {
                return None
            }
            let task = tasks[0]
            tasks.remove(at: 0)
            return task
        }
    }

    private func doTask(): Unit {
        while (true) {
            let task = popTask()
            if (let None <- task) {
                return
            }
            task.getOrThrow().fn()
        }
    }
}
