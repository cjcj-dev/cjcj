package cangjie_compiler::utils

public class ParallelUtil {
    private let threadsNum: Int64

    public init(threadsNum: Int64) {
        this.threadsNum = threadsNum
    }

    public func ThreadsNum(): Int64 {
        return threadsNum
    }

    public func RunTasksInParallel(tasks: Array<() -> Unit>): Unit {
        let queue = TaskQueue(threadsNum)
        for (task in tasks) {
            queue.AddTask<Unit>({ =>
                task()
            })
        }
        queue.RunAndWaitForAllTasksCompleted()
    }

    public func RunIndexedInParallel<T>(items: Array<T>, worker: (Int64, T) -> Unit): Unit {
        let queue = TaskQueue(threadsNum)
        var idx: Int64 = 0
        while (idx < items.size) {
            let taskIndex = idx
            let item = items[taskIndex]
            queue.AddTask<Unit>({ =>
                worker(taskIndex, item)
            })
            idx++
        }
        queue.RunAndWaitForAllTasksCompleted()
    }

    public func RunAST2CHIRInParallel<T>(decls: Array<T>, translateASTNode: (T) -> Unit): Unit {
        RunIndexedInParallel<T>(decls, { _: Int64, decl: T =>
            translateASTNode(decl)
        })
    }
}
