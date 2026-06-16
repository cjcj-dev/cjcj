package cangjie_compiler::driver

import std.collection.*

public class IOS_CJNATIVE <: Darwin_CJNATIVE {
    public init(driver: Driver, driverOptions: DriverOptions, backendCmds: ArrayList<ToolBatch>) {
        super(driver, driverOptions, backendCmds)
    }

    protected override func GetClangRTProfileLibraryName(): String {
        return "libclang_rt.profile_iossim.a"
    }
}
