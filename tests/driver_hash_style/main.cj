import cjcj::driver.*
import cjcj::frontend.DiagnosticEngine
import cjcj::option.{ArchType, EnvironmentType, OSType, OrderedInput, OutputMode}

// Exercise the production backend selector and read the resulting Tool batches.
// No linker execution or cross-target runtime installation is required.
main(args: Array<String>): Int64 {
    if (args.size != 1) { return 2 }
    var failures: Int64 = 0
    for ((name, environment) in [("ohos", EnvironmentType.OHOS), ("linux", EnvironmentType.GNU)]) {
        let driver = Driver([], DiagnosticEngine(), executableName: args[0] + "/bin/cjc")
        let options = driver.driverOptions
        options.target.os = OSType.LINUX
        options.target.arch = ArchType.X86_64
        options.target.env = environment
        options.outputMode = OutputMode.EXECUTABLE
        options.output = "hash-style-fixture"
        options.toolChainPaths.add("/usr/bin")
        options.inputObjs.add("hash-style-input.o")
        options.inputFileOrder.add(OrderedInput("hash-style-input.o", 0u64))
        if (!TempFileManager.Instance().Init(options, false)) { return 2 }
        let backend = CJNATIVEBackend(Job(), options, driver)
        if (!backend.Generate()) { return 2 }
        var gnu: Int64 = 0
        var both: Int64 = 0
        for (batch in backend.GetBackendCmds()) {
            for (tool in batch) {
                for (arg in tool.GetArgs()) {
                    if (arg == "--hash-style=gnu") { gnu++ }
                    if (arg == "--hash-style=both") { both++ }
                }
            }
        }
        let ok = if (name == "ohos") { gnu == 1 && both == 0 } else { gnu == 0 && both == 1 }
        println("ASSERT hash_style_${name} executed=true gnu=${gnu} both=${both} pass=${ok}")
        if (!ok) { failures++ }
        TempFileManager.Instance().DeleteTempFiles()
    }
    return if (failures == 0) { 0 } else { 1 }
}
