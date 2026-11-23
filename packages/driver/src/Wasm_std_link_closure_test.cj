package cjcj::driver

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
