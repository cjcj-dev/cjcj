package cangjie_compiler::driver

import std.collection.*

public open class Darwin_CJNATIVE <: MachO {
    public init(driver: Driver, driverOptions: DriverOptions, backendCmds: ArrayList<ToolBatch>) {
        super(driver, driverOptions, backendCmds)
    }

    public override func InitializeLibraryPaths(): Unit {
        if (driverOptions.IsCrossCompiling() && driverOptions.customizedSysroot) {
            AddLibraryPaths(ComputeLibPaths())
        }
        super.InitializeLibraryPaths()
    }
}
