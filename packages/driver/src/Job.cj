package cjcj::driver

import std.collection.*
import std.sync.*
import cjcj::utils.ProfileRecorder

private func NormalizeJobLimit(jobs: Option<UInt64>): Int64 {
    if (let Some(rawLimit) <- jobs) {
        if (rawLimit == 0u64) {
            return 1
        }
        if (rawLimit > 2147483647u64) {
            return 2147483647
        }
        return Int64(rawLimit)
    }
    return 1
}

private class ToolExecutionResult {
    public let command: String
    public let spawnErrorMessage: String
    public let exitCode: Int64

    public init(command: String, spawnErrorMessage!: String = "", exitCode!: Int64 = 0) {
        this.command = command
        this.spawnErrorMessage = spawnErrorMessage
        this.exitCode = exitCode
    }

    public func Succeeded(): Bool {
        return spawnErrorMessage.isEmpty() && exitCode == 0
    }
}

private func ExecuteToolAndCapture(tool: Tool, verbose: Bool): ToolExecutionResult {
    let commandString = tool.GetCommandString()
    let future = tool.Execute(verbose)
    if (!future.spawnErrorMessage.isEmpty()) {
        return ToolExecutionResult(commandString, spawnErrorMessage: future.spawnErrorMessage, exitCode: future.exitCode)
    }
    if (future.GetState() == ToolFutureState.FAILED) {
        return ToolExecutionResult(commandString, exitCode: future.exitCode)
    }
    return ToolExecutionResult(commandString)
}

private func PrintToolFailure(result: ToolExecutionResult): Unit {
    if (!result.spawnErrorMessage.isEmpty()) {
        eprintln("${result.command}: command failed (${result.spawnErrorMessage})")
    } else {
        eprintln("${result.command}: command failed with exit code ${result.exitCode} (use -V to see invocation)")
    }
}

private class ToolBatchRunner {
    private let commands: ToolBatch
    private let verbose: Bool
    private let mutex: Mutex = Mutex()
    private var nextIndex: Int64 = 0
    private var failure: Option<ToolExecutionResult> = None

    public init(commands: ToolBatch, verbose: Bool) {
        this.commands = commands
        this.verbose = verbose
    }

    public func Run(jobLimit: Int64): Option<ToolExecutionResult> {
        let workerCount = ComputeWorkerCount(jobLimit)
        if (workerCount == 0) {
            return None
        }
        let workers = ArrayList<Future<Unit>>()
        for (_ in 0..workerCount) {
            workers.add(spawn {
                WorkerLoop()
            })
        }
        for (worker in workers) {
            worker.get()
        }
        return failure
    }

    private func ComputeWorkerCount(jobLimit: Int64): Int64 {
        if (commands.isEmpty()) {
            return 0
        }
        let normalizedLimit = if (jobLimit > 0) { jobLimit } else { 1 }
        return if (normalizedLimit < commands.size) { normalizedLimit } else { commands.size }
    }

    private func TakeNextCommand(): Option<Tool> {
        synchronized(mutex) {
            if (let Some(_) <- failure) {
                return None
            }
            if (nextIndex >= commands.size) {
                return None
            }
            let command = commands[nextIndex]
            nextIndex++
            return command
        }
    }

    private func SaveFailure(result: ToolExecutionResult): Unit {
        synchronized(mutex) {
            if (let None <- failure) {
                failure = result
            }
        }
    }

    private func WorkerLoop(): Unit {
        while (true) {
            let nextCommand = TakeNextCommand()
            if (let None <- nextCommand) {
                return
            }
            let result = ExecuteToolAndCapture(nextCommand.getOrThrow(), verbose)
            if (!result.Succeeded()) {
                SaveFailure(result)
                return
            }
        }
    }
}

public class Job {
    private var backend: Option<Backend> = None
    private var verbose: Bool = false
    private var jobLimit: Int64 = 1

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
        jobLimit = NormalizeJobLimit(Some(driverOptions.GetJobs()))
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
            let recorder = ProfileRecorder("Main Stage", "Execute " + FileUtil.GetFileName(cmdBatch[0].GetName()))
            let runner = ToolBatchRunner(cmdBatch, verbose)
            if (let Some(failure) <- runner.Run(jobLimit)) {
                PrintToolFailure(failure)
                return false
            }
        }
        return true
    }
}
