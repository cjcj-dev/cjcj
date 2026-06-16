package cangjie_compiler::driver

import std.collection.*

public open class Linux_CJNATIVE <: Gnu {
    public init(driver: Driver, driverOptions: DriverOptions, backendCmds: ArrayList<ToolBatch>) {
        super(driver, driverOptions, backendCmds)
    }

    protected override func AddSystemLibraryPaths(): Unit {
        if (driverOptions.IsCrossCompiling() && driverOptions.customizedSysroot) {
            AddLibraryPaths(ComputeLibPaths())
        }
        super.AddSystemLibraryPaths()
    }
}
