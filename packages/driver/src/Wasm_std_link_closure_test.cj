package cjcj::driver

import cjcj::frontend.DiagnosticEngine
import cjcj::option.*
import cjcj::option.TempFileInfo as WasmTempFileInfo
import std.fs.Directory as FSDirectory
import std.fs.removeIfExists
import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

// Builtin dependencies arrive in the forms the frontend actually produces: resolved .cjo
// paths from ImportManager (CompilerInstance.ModularizeCompilation) and bare "<package>.cjo"
// names from object-only inputs (FrontendTool.ProcessObjectOnlyFrontendInputs).
let WASM_TEST_MODULES: String = "/sdk/modules/wasi_wasm32_cjnative/"

func WasmClosurePackages(direct: Array<String>, indirect: Array<String>): HashSet<String> {
    let pkgs = HashSet<String>()
    for (dep in WasmStdLinkClosure(direct, indirect)) {
        pkgs.add(WasmStdDependencyPackage(dep))
    }
    return pkgs
}

@Test
class WasmStdLinkClosureTest {
    @TestCase
    func CjoPathEnvAddsProcess(): Unit {
        let direct = [WASM_TEST_MODULES + "std.env.cjo", WASM_TEST_MODULES + "std.core.cjo"]
        let indirect = [WASM_TEST_MODULES + "std.collection.cjo"]
        let deps = WasmStdLinkClosure(direct, indirect)
        let pkgs = WasmClosurePackages(direct, indirect)
        println("CLOSURE cjo-path deps=${deps}")
        @Expect(pkgs.contains("std.process"), true)
        for (dep in direct) {
            @Expect(deps.contains(dep), true)
        }
        @Expect(deps.contains(indirect[0]), true)
        @Expect(deps.size, 4)
    }

    @TestCase
    func IndirectEnvAddsProcess(): Unit {
        let pkgs = WasmClosurePackages([WASM_TEST_MODULES + "std.core.cjo"], [WASM_TEST_MODULES + "std.env.cjo"])
        @Expect(pkgs.contains("std.process"), true)
    }

    @TestCase
    func ObjectOnlyCjoNameAddsProcess(): Unit {
        let pkgs = WasmClosurePackages(Array<String>(), ["std.env.cjo"])
        @Expect(pkgs.contains("std.process"), true)
    }

    @TestCase
    func ExplicitProcessNotDuplicated(): Unit {
        let direct = [WASM_TEST_MODULES + "std.env.cjo", WASM_TEST_MODULES + "std.process.cjo"]
        let deps = WasmStdLinkClosure(direct, Array<String>())
        @Expect(deps.size, 2)
    }

    @TestCase
    func NoEnvAddsNothing(): Unit {
        let direct = [WASM_TEST_MODULES + "std.core.cjo", WASM_TEST_MODULES + "std.math.cjo"]
        let deps = WasmStdLinkClosure(direct, Array<String>())
        @Expect(deps.size, 2)
        @Expect(WasmClosurePackages(direct, Array<String>()).contains("std.process"), false)
    }

    @TestCase
    func PackageNameFromDependencyEntry(): Unit {
        @Expect(WasmStdDependencyPackage(WASM_TEST_MODULES + "std.collection.concurrent.cjo"), "std.collection.concurrent")
        @Expect(WasmStdDependencyPackage("std.env.cjo"), "std.env")
        @Expect(WasmStdDependencyPackage("std.process"), "std.process")
    }
}

@Test
class WasmFinalLinkTest {
    private func checkFlags(debug: Bool, strip: Bool, expected: Array<String>): Unit {
        let root = FSDirectory.createTemp(".").toString()
        let options = DriverOptions()
        options.output = root
        options.outputMode = OutputMode.EXECUTABLE
        options.moduleName = "wasm_link"
        options.target.arch = ArchType.WASM32
        options.target.os = OSType.WASI
        options.enableCompileDebug = debug
        options.stripSymbolTable = strip
        let manager = TempFileManager.Instance()
        try {
            @Assert(manager.Init(options, false), true)
            let commands = ArrayList<ToolBatch>()
            try (diag = DiagnosticEngine()) {
                let driver = Driver(["cjc"], diag)
                driver.cangjieHome = root
                let chain = Wasm_CJNATIVE(driver, options, commands)
                chain.ldPath = "wasm-ld"
                @Assert(chain.ProcessGeneration(ArrayList<WasmTempFileInfo>()), true)
                @Assert(commands.size, 1)
                @Assert(commands[0].size, 1)
                @Assert(commands[0][0].name, "wasm-ld")
                let flags = ArrayList<String>()
                for (arg in commands[0][0].GetArgs()) {
                    if (arg.startsWith("--strip-") || arg == "--compress-relocations") {
                        flags.add(arg)
                    }
                }
                @Expect(flags.toArray(), expected)
            }
        } finally {
            manager.DeleteTempFiles()
            let _ = removeIfExists(root, recursive: true)
        }
    }

    @TestCase
    func ReleaseStripsAndCompresses(): Unit {
        checkFlags(false, false, ["--strip-all", "--compress-relocations"])
    }

    @TestCase
    func DebugKeepsNamesAndOffsets(): Unit {
        checkFlags(true, false, [])
    }

    @TestCase
    func DebugHonorsExplicitStrip(): Unit {
        checkFlags(true, true, ["--strip-all"])
    }
}
