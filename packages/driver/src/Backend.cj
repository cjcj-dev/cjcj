package cjcj::driver

import std.collection.*

public open class Backend {
    protected let driver: Driver
    protected let driverOptions: DriverOptions
    protected var TC: Option<ToolChain> = None
    protected let ownerJob: Job
    protected let backendCmds: ArrayList<ToolBatch> = ArrayList<ToolBatch>()

    public init(job: Job, driverOptions: DriverOptions, driver: Driver) {
        this.driver = driver
        this.driverOptions = driverOptions
        ownerJob = job
    }

    public func Generate(): Bool {
        if (!GenerateToolChain()) {
            return false
        }
        if (let None <- TC) {
            return false
        }
        if (let Some(toolChain) <- TC) {
            toolChain.InitializeLibraryPaths()
        }
        if (!PrepareDependencyPath()) {
            return false
        }
        if (!FileUtil.IsDir(driverOptions.output) && FileUtil.GetFileExtension(driverOptions.output) == "cjo") {
            eprintln("error: file extension '.cjo' is not allowed, please change it")
            return false
        }
        return ProcessGeneration()
    }

    public func GetBackendCmds(): ArrayList<ToolBatch> {
        return backendCmds
    }

    protected open func GenerateToolChain(): Bool { return false }
    protected open func ProcessGeneration(): Bool { return false }
    protected open func PrepareDependencyPath(): Bool { return false }
}
