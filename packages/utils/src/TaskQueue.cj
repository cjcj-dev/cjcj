package cjcj::utils

import std.collection.*
import std.sort.*
import std.sync.*

private struct Task {
    let fn: () -> Unit
    let priority: UInt64

    init(fn: () -> Unit, priority: UInt64) {
        this.fn = fn
        this.priority = priority
    }

    public operator func <(other: Task): Bool {
        return priority < other.priority
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
        let result = value.getOrThrow()
        value = None
        return result
    }

    public func isCompleted(): Bool {
        return completed
    }
}

public class TaskQueue {
    private let tasks = ArrayList<Task>()
    private let threads = ArrayList<Future<Unit>>()
    private let mutex = Mutex()
    private var isStarted = false
    private let threadsNum: Int64

    public init(threadsNum: Int64) {
        this.threadsNum = if (threadsNum > 0) { threadsNum } else { 1 }
    }

    ~init() {
        threads.clear()
    }

    public func AddTask<T>(fn: () -> T, priority!: UInt64 = 0u64): TaskResult<T> {
        CJC_ASSERT_WITH_MSG(!isStarted, "Do not add new tasks while executing.")
        let result = TaskResult<T>()
        tasks.add(Task({ =>
            try {
                result.complete(fn())
            } catch (e: Exception) {
                result.fail(e)
            }
        }, priority))
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
        isStarted = true
        sort(tasks, by: { left: Task, right: Task =>
            if (right < left) {
                Ordering.LT
            } else if (left < right) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        })
        let fixedThreadsNum = if (tasks.size < threadsNum) { tasks.size } else { threadsNum }
        for (_ in 0..fixedThreadsNum) {
            threads.add(spawn {
                doTask()
            })
        }
    }

    private func doTask(): Unit {
        while (true) {
            var task: Option<Task> = None
            synchronized(mutex) {
                if (tasks.isEmpty()) {
                    return
                }
                task = tasks[0]
                tasks.remove(at: 0)
            }
            task.getOrThrow().fn()
        }
    }
}
