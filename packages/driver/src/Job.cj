package cangjie_compiler::driver

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
            for (cmd in cmdBatch) {
                let future = cmd.Execute(verbose)
                if (!future.spawnErrorMessage.isEmpty()) {
                    eprintln("${cmd.GetCommandString()}: command failed (${future.spawnErrorMessage})")
                    return false
                }
                let state = future.GetState()
                if (state == ToolFutureState.FAILED) {
                    eprintln("${cmd.GetCommandString()}: command failed with exit code ${future.exitCode} (use -V to see invocation)")
                    return false
                }
            }
        }
        return true
    }
}
