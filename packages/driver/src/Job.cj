package cjcj::driver

import std.collection.*
import cjcj::utils.{ConcurrencyBudget, ProfileRecorder, Semaphore}

// Mirrors Driver/Job.cpp:30-69.
private func CheckExecuteResult(checklist: TreeMap<String, ToolFuture>,
    returnIfAnyToolFinished!: Bool = false): Bool {
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
            try (recorder = ProfileRecorder("Main Stage", "Execute " + FileUtil.GetFileName(cmdBatch[0].GetName()))) {
                let childWorkers = TreeMap<String, ToolFuture>()
                for (command in cmdBatch) {
                    let budget = ConcurrencyBudget.Get()
                    let future = if (budget.IsEnabled()) {
                        var lease = budget.TryAcquire()
                        while (let None <- lease) {
                            if (childWorkers.isEmpty()) {
                                eprintln("error: no jobserver execution slot is available for a driver command")
                                return false
                            }
                            if (!CheckExecuteResult(childWorkers, returnIfAnyToolFinished: true)) {
                                return false
                            }
                            lease = budget.TryAcquire()
                        }
                        command.ExecuteWithLease(verbose, lease.getOrThrow())
                    } else {
                        while (Semaphore.Get().GetCount() == 0) {
                            if (!CheckExecuteResult(childWorkers, returnIfAnyToolFinished: true)) {
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
                }
                if (!CheckExecuteResult(childWorkers)) {
                    return false
                }
            }
        }
        return true
    }
}
