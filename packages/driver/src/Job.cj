package cjcj::driver

import std.collection.*
import cjcj::utils.{ConcurrencyBudget, ProfileRecorder, Semaphore}

// Mirrors Driver/Job.cpp:30-69.
private func CheckExecuteResult(checklist: TreeMap<String, ToolFuture>,
    returnIfAnyToolFinished!: Bool = false, succeeded!: ArrayList<String> = ArrayList<String>()): Bool {
    var success = true
    while (!checklist.isEmpty()) {
        let totalTasks = checklist.size
        let finishedCommands = ArrayList<String>()
        for ((command, future) in checklist) {
            let state = future.GetState()
            if (state == ToolFutureState.FAILED) {
                if (!ConcurrencyBudget.Get().IsEnabled()) {
                    Semaphore.Get().Release()
                }
                eprintln("${command}: command failed with exit code ${future.exitCode} (use -V to see invocation)")
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
            if (let Some(successor) <- cmdBatch[0].successor) {
                stage += "+" + FileUtil.GetFileName(successor.GetName())
            }
            try (recorder = ProfileRecorder("Main Stage", "Execute " + stage)) {
                let childWorkers = TreeMap<String, ToolFuture>()
                let pending = ArrayList<Tool>(cmdBatch)
                let runningTools = HashMap<String, Tool>()
                let succeeded = ArrayList<String>()
                var next: Int64 = 0
                var success = true
                while (true) {
                    while (success && next < pending.size) {
                        let command = pending[next]
                        next++
                        let budget = ConcurrencyBudget.Get()
                        let future = if (budget.IsEnabled()) {
                            var lease = budget.TryAcquire()
                            while (let None <- lease) {
                                if (childWorkers.isEmpty()) {
                                    eprintln("error: no jobserver execution slot is available for a driver command")
                                    return false
                                }
                                if (!CheckExecuteResult(childWorkers, returnIfAnyToolFinished: true,
                                    succeeded: succeeded)) {
                                    return false
                                }
                                lease = budget.TryAcquire()
                            }
                            command.ExecuteWithLease(verbose, lease.getOrThrow())
                        } else {
                            while (Semaphore.Get().GetCount() == 0) {
                                if (!CheckExecuteResult(childWorkers, returnIfAnyToolFinished: true,
                                    succeeded: succeeded)) {
                                    return false
                                }
                            }
                            command.Execute(verbose)
                        }
                        if (!future.spawnErrorMessage.isEmpty()) {
                            eprintln("${command.GetCommandString()}: command failed (${future.spawnErrorMessage})")
                            return false
                        }
                        childWorkers[command.GetCommandString()] = future
                        runningTools[command.GetCommandString()] = command
                    }
                    if (childWorkers.isEmpty()) {
                        break
                    }
                    // A failure stops new starts but still drains every running child, as the batch wait does.
                    success = CheckExecuteResult(childWorkers, returnIfAnyToolFinished: true,
                        succeeded: succeeded) && success
                    for (command in succeeded) {
                        if (let Some(successor) <- runningTools[command].successor) {
                            pending.add(successor)
                        }
                    }
                    succeeded.clear()
                }
                if (!success) {
                    return false
                }
            }
        }
        return true
    }
}
