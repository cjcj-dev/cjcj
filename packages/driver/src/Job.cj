package cjcj::driver

import std.collection.*
import cjcj::utils.{ConcurrencyBudget, ProfileRecorder, Semaphore}

// Mirrors Driver/Job.cpp:30-69.
private func CheckExecuteResult(checklist: TreeMap<Int64, ToolFuture>,
    returnIfAnyToolFinished!: Bool = false, succeeded!: ArrayList<Int64> = ArrayList<Int64>()): Bool {
    var success = true
    while (!checklist.isEmpty()) {
        let totalTasks = checklist.size
        let finishedCommands = ArrayList<Int64>()
        for ((command, future) in checklist) {
            let state = future.GetState()
            if (state == ToolFutureState.FAILED) {
                if (!ConcurrencyBudget.Get().IsEnabled()) {
                    Semaphore.Get().Release()
                }
                eprintln("backend task ${command}: command failed with exit code ${future.exitCode} (use -V to see invocation)")
                finishedCommands.add(command)
                success = false
            } else if (state == ToolFutureState.SUCCESS) {
                if (!ConcurrencyBudget.Get().IsEnabled()) {
                    Semaphore.Get().Release()
                }
                finishedCommands.add(command)
                succeeded.add(command)
            }
        }
        for (command in finishedCommands) {
            checklist.remove(command)
        }
        if (returnIfAnyToolFinished && totalTasks != checklist.size) {
            return success
        }
        sleep(200 * Duration.microsecond)
    }
    return success
}

public class Job {
    private var backend: Option<Backend> = None
    private var verbose: Bool = false

    public init() {}

    public func Assemble(driverOptions: DriverOptions, driver: Driver): Bool {
        if (driverOptions.backend != BackendType.CJNATIVE) {
            eprintln("error: Toolchain: Unsupported backend")
            return false
        }
        let nextBackend = CJNATIVEBackend(this, driverOptions, driver)
        if (!nextBackend.Generate()) {
            return false
        }
        backend = nextBackend
        verbose = driverOptions.enableVerbose
        return true
    }

    public func Execute(): Bool {
        if (let None <- backend) {
            return false
        }
        let commandList = (backend.getOrThrow()).GetBackendCmds()
        for (cmdBatch in commandList) {
            if (cmdBatch.isEmpty()) {
                continue
            }
            var stage = FileUtil.GetFileName(cmdBatch[0].GetName())
            if (!cmdBatch[0].successors.isEmpty()) {
                stage += "+" + FileUtil.GetFileName(cmdBatch[0].successors[0].GetName())
            }
            try (recorder = ProfileRecorder("Main Stage", "Execute " + stage)) {
                // Numeric task identities retain every child even if two command strings are identical.
                let childWorkers = TreeMap<Int64, ToolFuture>()
                let pending = ArrayList<Tool>(cmdBatch)
                let runningTools = HashMap<Int64, Tool>()
                let succeeded = ArrayList<Int64>()
                var next: Int64 = 0
                var taskId: Int64 = 0
                var success = true
                try {
                    while (true) {
                        // Publish ready successors before checking for an empty running set. The last
                        // opt may have completed while admission was waiting for a token.
                        for (completed in succeeded) {
                            for (successor in runningTools[completed].successors) {
                                pending.add(successor, at: next)
                            }
                            runningTools.remove(completed)
                        }
                        succeeded.clear()
                        if (!success || (next == pending.size && childWorkers.isEmpty())) {
                            break
                        }
                        if (next == pending.size) {
                            success = CheckExecuteResult(childWorkers, returnIfAnyToolFinished: true,
                                succeeded: succeeded)
                            continue
                        }
                        let budget = ConcurrencyBudget.Get()
                        let lease = budget.TryAcquire()
                        if ((budget.IsEnabled() && lease.isNone()) ||
                            (!budget.IsEnabled() && Semaphore.Get().GetCount() == 0)) {
                            if (childWorkers.isEmpty()) {
                                eprintln("error: no execution slot is available for a driver command")
                                success = false
                                break
                            }
                            success = CheckExecuteResult(childWorkers, returnIfAnyToolFinished: true,
                                succeeded: succeeded)
                            continue
                        }
                        let command = pending[next]
                        next++
                        let future = if (budget.IsEnabled()) {
                            command.ExecuteWithLease(verbose, lease.getOrThrow())
                        } else {
                            command.Execute(verbose)
                        }
                        if (!future.spawnErrorMessage.isEmpty()) {
                            // The failed spawn already returned its admission; only live children need draining.
                            eprintln("${command.GetCommandString()}: command failed (${future.spawnErrorMessage})")
                            success = false
                            break
                        }
                        childWorkers[taskId] = future
                        runningTools[taskId] = command
                        taskId++
                    }
                } finally {
                    // On every exit, including a spawn error or exception, join all children before
                    // temporary-file cleanup and return every acquired token exactly once.
                    success = CheckExecuteResult(childWorkers) && success
                }
                if (!success) {
                    return false
                }
            }
        }
        return true
    }
}
