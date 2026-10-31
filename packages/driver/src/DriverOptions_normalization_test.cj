package cjcj::driver

import cjcj::option.*
import cjcj::frontend.DiagnosticEngine
import std.collection.ArrayList
import std.env.getVariable
import std.unittest.*
import std.unittest.testmacro.*

@Test
class DriverOptionsNormalizationTest {
    @TestCase
    func ApcObfuscationNormalization(): Unit {
        let source = (getVariable("PROJECT_SOURCE_DIR") ?? ".") + "/packages/option/testdata/main.cj"
        for (target in ["x86_64-unknown-linux-gnu", "x86_64-w64-mingw32", "aarch64-apple-darwin", "aarch64-apple-ios"]) {
            for (apc in [Array<String>(), ["--apc"], ["--apc=3"], ["--apc-split-num", "5"]]) {
                println("INPUT obfuscation target=${target} apc=${apc}")
                let input = ArrayList<String>()
                input.add(all: ["cjc", "--experimental", "--target", target, "--fobf-string", "-j", "7"])
                input.add(all: apc)
                input.add(source)
                let args = ArgList()
                let table = CreateOptionTable()
                @Expect(table.ParseArgs(input.toArray(), args), true)
                let opts = DriverOptions()
                let success = opts.ParseFromArgs(args)
                println("NORMALIZED obfuscation target=${target} success=${success} enabled=${opts.IsObfuscationEnabled()} value=${opts.aggressiveParallelCompile.value}")
                @Expect(opts.IsObfuscationEnabled(), true)
                @Expect(success, true)
                @Expect(opts.aggressiveParallelCompile.value, 1u64)
            }
        }
    }
}

// Finite option coverage; the installed public macro gate also inspects the
// real linked DSO and runs its macro body and transitive CJ dependencies.
@When[os == "Linux"]
private class MacroRuntimePathProbe <: ToolChain {
    init(driver: Driver, options: DriverOptions) {
        super(driver, options, ArrayList<ToolBatch>())
    }

    func AppendRuntimePath(tool: Tool): Unit {
        GenerateRuntimePath(tool)
    }
}

@When[os == "Linux"]
@Test
class MacroRuntimePathTest {
    @TestCase
    func MacroUsesLogicalEntryAndPreservesExplicitPaths(): Unit {
        try (diag = DiagnosticEngine()) {
            let driver = Driver(["cjc"], diag, executableName: "/target sdk/bin/cjc")
            driver.cangjieHome = "/official-host"
            let opts = driver.driverOptions
            opts.host.arch = ArchType.X86_64
            opts.host.os = OSType.LINUX
            opts.host.env = EnvironmentType.GNU
            opts.target.arch = ArchType.X86_64
            opts.target.os = OSType.LINUX
            opts.target.env = EnvironmentType.GNU
            opts.compileMacroPackage = true
            opts.outputMode = OutputMode.SHARED_LIB
            let tool = Tool("ld", ToolType.BACKEND, opts.environment.allVariables)
            tool.AppendArg("-rpath")
            tool.AppendArg("$ORIGIN/private")
            MacroRuntimePathProbe(driver, opts).AppendRuntimePath(tool)
            let expected = ["-rpath", "$ORIGIN/private", "--disable-new-dtags", "-rpath",
                "/target sdk/bin/../runtime/lib/linux_x86_64_cjnative"]
            @Assert(tool.GetArgs().size, expected.size)
            for (i in 0..expected.size) { @Expect(tool.GetArgs()[i], expected[i]) }
        }
    }

    @TestCase
    func OrdinaryOutputsKeepExplicitRpathSemantics(): Unit {
        try (diag = DiagnosticEngine()) {
            let driver = Driver(["cjc"], diag, executableName: "/target sdk/bin/cjc")
            driver.cangjieHome = "/selected-home"
            let opts = driver.driverOptions
            opts.host.arch = ArchType.X86_64
            opts.host.os = OSType.LINUX
            opts.host.env = EnvironmentType.GNU
            opts.target.arch = ArchType.X86_64
            opts.target.os = OSType.LINUX
            opts.target.env = EnvironmentType.GNU
            for (mode in [OutputMode.EXECUTABLE, OutputMode.SHARED_LIB]) {
                opts.outputMode = mode
                opts.useRuntimeRpath = false
                let ordinary = Tool("ld", ToolType.BACKEND, opts.environment.allVariables)
                MacroRuntimePathProbe(driver, opts).AppendRuntimePath(ordinary)
                @Expect(ordinary.GetArgs().size, 0)
                opts.useRuntimeRpath = true
                let explicit = Tool("ld", ToolType.BACKEND, opts.environment.allVariables)
                MacroRuntimePathProbe(driver, opts).AppendRuntimePath(explicit)
                @Assert(explicit.GetArgs().size, 2)
                @Expect(explicit.GetArgs()[0], "-rpath")
                @Expect(explicit.GetArgs()[1], "/selected-home/runtime/lib/linux_x86_64_cjnative")
            }
        }
    }
}
