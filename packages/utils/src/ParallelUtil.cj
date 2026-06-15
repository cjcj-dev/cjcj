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

    public func RunAST2CHIRInParallel(): Unit {
        CJC_ASSERT_WITH_MSG(threadsNum > 0, "parallel AST2CHIR requires a positive worker count")
    }
}
