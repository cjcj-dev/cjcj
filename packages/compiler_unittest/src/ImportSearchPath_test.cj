package cjcj::compiler_unittest

import std.collection.*
import std.env.getVariable
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::frontend.*
import cjcj::utils.{FileUtil, GenerateRandomHexString}

@Test
public class ImportSearchPathTest {
    @TestCase
    public func ScanOptions(): Unit { CheckSearch("options", true) }
    @TestCase
    public func ScanEnvironment(): Unit { CheckSearch("environment", true) }
    @TestCase
    public func ScanModules(): Unit { CheckSearch("modules", true) }
    @TestCase
    public func ScanEmptyEnvironment(): Unit { CheckSearch("empty-environment", true) }
    @TestCase
    public func IndexOptions(): Unit { CheckSearch("options", false) }
    @TestCase
    public func IndexEnvironment(): Unit { CheckSearch("environment", false) }
    @TestCase
    public func IndexModules(): Unit { CheckSearch("modules", false) }
    @TestCase
    public func IndexEmptyEnvironment(): Unit { CheckSearch("empty-environment", false) }

    private func CheckSearch(arm: String, scan: Bool): Unit {
        // Export a real package once; every arm loads that CJO through the
        // production importer, not a filename-only search model.
        let producer = CompileSource("package searchfixture\npublic func value(): Int64 { 42 }")
        @Assert(producer.ok)
        let data = producer.instance.ExportAST(false, RequireFirstPackage(producer))
        let control = CompileSource("package searchcontrol\npublic func value(): Int64 { 7 }")
        @Assert(control.ok)
        let controlData = control.instance.ExportAST(false, RequireFirstPackage(control))
        let root = FileUtil.JoinPath(getVariable("CJO_DIAGNOSTIC_TEST_TMP") ?? "/tmp",
            "import-search-" + GenerateRandomHexString())
        let moduleHome = FileUtil.JoinPath(root, "module-home")
        let modules = FileUtil.JoinPath(moduleHome, "modules/tuple")
        let optionHome = FileUtil.JoinPath(root, "option-home")
        let envHome = FileUtil.JoinPath(root, "env-home")
        let explicitPath = FileUtil.JoinPath(root, "explicit")
        let envPath = FileUtil.JoinPath(root, "environment")
        for (home in [optionHome, envHome, moduleHome]) {
            let flat = FileUtil.JoinPath(home, "third_party/flatbuffers/modules")
            @Assert(FileUtil.CreateDirs(flat + "/"), 0)
            @Assert(FileUtil.WriteBufferToASTFile(FileUtil.JoinPath(flat, "searchfixture.cjo"), data))
        }
        for (directory in [explicitPath, envPath, modules]) {
            @Assert(FileUtil.CreateDirs(directory + "/"), 0)
            @Assert(FileUtil.WriteBufferToASTFile(FileUtil.JoinPath(directory, "searchcontrol.cjo"), controlData))
        }
        let diag = DiagnosticEngine()
        let invocation = CompilerInvocation()
        let opts = invocation.globalOptions
        opts.importPaths.add(explicitPath)
        // Only standard dependencies use this existing target-module path.
        // The tested package is present solely under the selected home.
        let realModules = producer.instance.cangjieModules
        opts.importPaths.add(realModules)
        opts.environment.cangjiePaths.add(envPath)
        opts.cangjieHome = if (arm == "options") { optionHome } else { "" }
        opts.environment.cangjieHome.hasValue = arm != "modules"
        opts.environment.cangjieHome.value = if (arm == "empty-environment") { "" } else { envHome }
        opts.scanDepPkg = scan
        let instance = CompilerInstance(invocation, diag)
        // Instance-only home is the native PackageTest-style fallback.
        instance.cangjieHome = moduleHome
        instance.cangjieModules = modules
        @Assert(instance.ImportPackages())
        let manager = instance.importManager.getOrThrow()
        let selectedHome = if (arm == "options") { optionHome } else if (arm == "environment") {
            envHome
        } else { moduleHome }
        let flat = FileUtil.JoinPath(selectedHome, "third_party/flatbuffers/modules")
        let expected = [explicitPath, realModules, ".", envPath, modules, flat]
        // Exercise an unchanged search route before the target. A product
        // cut removing only the default path must leave this load working.
        @Assert(manager.AnalyzeDepStdPkgsOfBC("searchcontrol"))
        @Assert(manager.GetPackage("searchcontrol").isSome())
        println("IMPORT_SEARCH_CONTROL ${arm} scan=${scan} PASS")
        println("IMPORT_SEARCH_TARGET_BEGIN ${arm} scan=${scan}")
        @Assert(manager.AnalyzeDepStdPkgsOfBC("searchfixture"))
        @Assert(manager.GetPackage("searchfixture").isSome())
        let paths = manager.GetSearchPath()
        @Assert(paths.size, expected.size)
        for (i in 0..expected.size) { @Expect(paths[i], expected[i]) }
        @Expect(FileUtil.FindSerializationFile("searchfixture", ".cjo", paths.toArray()),
            FileUtil.JoinPath(flat, "searchfixture.cjo"))
        @Expect(FileUtil.FindSerializationFile("searchcontrol", ".cjo", paths.toArray()),
            FileUtil.JoinPath(explicitPath, "searchcontrol.cjo"))
        let count = manager.GetSearchPath().size
        @Assert(instance.ImportPackages())
        @Expect(manager.GetSearchPath().size, count)
        println("IMPORT_SEARCH_CONSUMER ${arm} scan=${scan} PASS")
    }
}
