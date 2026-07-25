package cjcj::driver

import std.collection.*
import std.time.*
import cjcj::utils.{ProfileRecorder, Semaphore}

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
                Semaphore.Get().Release()
                eprintln("${command}: command failed with exit code ${future.exitCode} (use -V to see invocation)")
                finishedCommands.add(command)
                success = false
            } else if (state == ToolFutureState.SUCCESS) {
                Semaphore.Get().Release()
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
                    while (Semaphore.Get().GetCount() == 0) {
                        if (!CheckExecuteResult(childWorkers, returnIfAnyToolFinished: true)) {
                            return false
                        }
                    }
                    let future = command.Execute(verbose)
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
