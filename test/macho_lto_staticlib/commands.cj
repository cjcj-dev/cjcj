import std.collection.*
import cjcj::driver.*
import cjcj::frontend.DiagnosticEngine

func check(ok: Bool, name: String): Int64 {
    println("ASSERT ${name} = ${ok}")
    return if (ok) { 0 } else { 1 }
}

// Calls the production backend entry and inspects its actual Tool arguments.
// No driver sources are recompiled into this fixture.
main(args: Array<String>): Int64 {
    let driver = Driver([], DiagnosticEngine())
    driver.cangjieHome = args[0]
    let opts = driver.driverOptions
    opts.cangjieHome = args[0]
    opts.target.arch = ArchType.AARCH64
    let darwinComponent = args[1] == "darwin-component"
    let shared = args[5] == "shared"
    opts.target.os = if (darwinComponent) { OSType.DARWIN } else { OSType.IOS }
    opts.target.env = if (args[1] == "simulator") { EnvironmentType.SIMULATOR } else { EnvironmentType.NOT_AVAILABLE }
    opts.outputMode = if (shared) { OutputMode.SHARED_LIB } else { OutputMode.STATIC_LIB }
    opts.stripSymbolTable = shared
    opts.ltoMod = if (args[3] == "full") { LTOMode.FULL_LTO } else { LTOMode.THIN_LTO }
    if (shared) { opts.ltoMod = LTOMode.NO_LTO }
    opts.incrementalCompileNoChange = args[4] == "incremental"
    let native = args[5] == "native"
    opts.emitStaticLibInLTO = Some(native)
    opts.environment.paths.add("/usr/bin")
    opts.environment.paths.add("/usr/lib/llvm-14/bin")
    opts.output = if (shared) { "library.dylib" } else { "archive.a" }
    opts.moduleName = "fixture"
    opts.linkStaticStd = Some(args[2] != "dynamic")
    opts.directBuiltinDependencies.add("/std/cangjie-std-core.cjo")
    opts.indirectBuiltinDependencies.add("/std/cangjie-std-core.cjo")
    opts.indirectBuiltinDependencies.add("/std/cangjie-std-collection.cjo")
    opts.frontendOutputFiles.add(OptionTempFileInfo(fileName: "fixture", filePath: "fixture.bc", rawPath: "fixture.cj", isFrontendOutput: true))
    if (!TempFileManager.Instance().Init(opts, false)) { return 90 }
    let backend = CJNATIVEBackend(Job(), opts, driver)
    var commands = ArrayList<ToolBatch>()
    if (darwinComponent) {
        // Upstream disallows native Darwin archives at the CLI. Component evidence only.
        let chain = Darwin_CJNATIVE(driver, opts, commands)
        if (!chain.PrepareDependencyPath() || !chain.ProcessGeneration(opts.frontendOutputFiles)) { return 92 }
    } else {
        if (!backend.Generate()) { return 91 }
        commands = backend.GetBackendCmds()
    }
    var fails: Int64 = 0
    var found = false
    for (batch in commands) {
        for (tool in batch) {
            let values = tool.GetArgs()
            println("COMMAND " + tool.GetCommandString())
            if (tool.GetName().endsWith("opt") && !shared) {
                var output = ""
                for (i in 0..values.size) {
                    if (values[i] == "-o") { output = values[i + 1] }
                }
                fails += check(if (native) { !output.endsWith("archive.a") && output.endsWith(".bc") } else { output.endsWith("archive.a") }, "opt-output-kind")
            }
            if (tool.GetName().endsWith("ld64.lld")) {
                found = true
                if (shared) {
                    var installName = ""
                    for (i in 0..values.size) {
                        if (values[i] == "-install_name") { installName = values[i + 1] }
                    }
                    fails += check(installName.endsWith("library.dylib"), "stripped-install-name")
                    fails += check(values.contains("-lcangjie-runtime"), "final-link-retains-runtime")
                    continue
                }
                fails += check(values.contains("-staticlib") && !values.contains("-dylib") &&
                    !values.contains("-lto-emit-obj-only"), "native-staticlib-mode")
                var forbidden = false
                var coreCount: Int64 = 0
                var collectionCount: Int64 = 0
                var user = false
                for (arg in values) {
                    forbidden = forbidden || arg.endsWith(".a") || arg.endsWith(".dylib") ||
                        arg.endsWith("section.o") || arg.endsWith("cjstart.o") || arg.startsWith("-L") ||
                        arg == "-lcangjie-runtime" || arg == "-rpath"
                    if (arg.endsWith("libcangjie-std-core.bc")) { coreCount++ }
                    if (arg.endsWith("libcangjie-std-collection.bc")) { collectionCount++ }
                    if (arg.contains("fixture") && arg.endsWith(".bc")) { user = true }
                }
                fails += check(!forbidden && user, "only-bitcode-inputs")
                let expected: Int64 = if (args[2] == "dynamic") { 0 } else { 1 }
                fails += check(coreCount == expected && collectionCount == expected, "std-selection-dedup")
                fails += check(values.contains(if (darwinComponent) { "macos" } else if (args[1] == "simulator") { "ios-simulator" } else { "ios" }), "platform")
            }
        }
    }
    fails += check(found == (native || shared), "native-link-command-reached")
    TempFileManager.Instance().DeleteTempFiles()
    return fails
}
