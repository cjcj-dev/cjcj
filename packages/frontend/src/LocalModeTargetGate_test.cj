package cjcj::frontend

import cjcj::option.{ArchType, EnvironmentType, OSType, OutputMode}
import std.env.getVariable
import std.fs.Directory as FSDirectory
import std.fs.File as FSFile
import std.unittest.*
import std.unittest.testmacro.*

private let LOCAL_TARGET_MESSAGE: String = "local mode lowering is only supported on Linux x86_64 GNU targets"

private func ItemHasText(item: Diagnostic, text: String): Bool {
    return item.errorMessage.contains(text) || item.diagMessage.contains(text)
}

private func HasMessage(diag: DiagnosticEngine, text: String): Bool {
    let stored = diag.AsBasicDiagnosticEngine().GetCategoryDiagnostic(DiagCategory.SEMA)
    for (item in stored) {
        if (ItemHasText(item, text)) { return true }
    }
    let parsed = diag.AsBasicDiagnosticEngine().GetCategoryDiagnostic(DiagCategory.PARSE)
    for (item in parsed) {
        if (ItemHasText(item, text)) { return true }
    }
    return false
}

private func SetTriple(opts: GlobalOptions, arch: ArchType, os: OSType, env: EnvironmentType): Unit {
    opts.target.arch = arch
    opts.target.os = os
    opts.target.env = env
}

private func CompileLocal(root: String, code: String, localMode: Bool, api: String, supported: Bool,
    stage: CompileStage): CompilerInstance {
    FSFile.writeTo(root + "/src.cj", code.toArray())
    let invocation = CompilerInvocation()
    let opts = invocation.globalOptions
    opts.cangjieHome = getVariable("CANGJIE_HOME").getOrThrow()
    opts.executablePath = opts.cangjieHome + "/bin/cjc"
    opts.outputMode = OutputMode.STATIC_LIB
    opts.output = root + "/out"
    opts.disableCodeGen = true
    opts.SetCompilationCachedPath()
    opts.UpdateCachedDirName("default")
    opts.srcFiles.add(root + "/src.cj")
    opts.enableLocalMode = localMode
    if (!api.isEmpty()) { opts.passedWhenKeyValue.add("local_mode_api", api) }
    if (supported) {
        SetTriple(opts, ArchType.X86_64, OSType.LINUX, EnvironmentType.GNU)
    } else {
        SetTriple(opts, ArchType.WASM32, OSType.WASI, EnvironmentType.NOT_AVAILABLE)
    }
    let ci = CompilerInstance(invocation, DiagnosticEngine())
    ci.buildTrie = false
    let _ = ci.Compile(stage: stage)
    return ci
}

@Test
public class LocalModeTargetGateTest {
    @TestCase
    public func StrippedWhenOnWasmPasses(): Unit {
        let root = FSDirectory.createTemp("/tmp").toString()
        let code = "package local_gate\n" +
            "@When[local_mode_api == \"on\"]\n" +
            "public func onlyInOn(v: Int64 @local!): Int64 @local! { v }\n" +
            "public func always(v: Int64): Int64 { v }\n"
        let ci = CompileLocal(root, code, true, "off", false, CompileStage.CONDITION_COMPILE)
        println("EXECUTED StrippedWhenOnWasmPasses rc=" + if (ci.diag.GetErrorCount() == 0) { "true" } else { "false" })
        @Expect(ci.diag.GetErrorCount(), 0u64)
        var survived = 0
        for (pkg in ci.GetSourcePackages()) {
            for (file in pkg.files) {
                for (decl in file.decls) {
                    if (decl.identifier.Val() == "onlyInOn") { survived++ }
                }
            }
        }
        println("EXECUTED StrippedWhenOnWasmPasses survived=" + survived.toString())
        @Expect(survived, 0)
        @Expect(HasMessage(ci.diag, LOCAL_TARGET_MESSAGE), false)
    }

    @TestCase
    public func SurvivingLocalRejectedOnWasm(): Unit {
        let root = FSDirectory.createTemp("/tmp").toString()
        let code = "package local_gate\n" +
            "public func keep(v: Int64 @local!): Int64 @local! { v }\n" +
            "public func region(v: Int64): Int64 { exclave { v } }\n"
        let ci = CompileLocal(root, code, true, "off", false, CompileStage.CONDITION_COMPILE)
        println("EXECUTED SurvivingLocalRejectedOnWasm rc=" + if (ci.diag.GetErrorCount() != 0) { "true" } else { "false" })
        @Expect(ci.diag.GetErrorCount() != 0, true)
        @Expect(HasMessage(ci.diag, LOCAL_TARGET_MESSAGE), true)
    }

    @TestCase
    public func SurvivingLocalAcceptedOnLinux(): Unit {
        let root = FSDirectory.createTemp("/tmp").toString()
        let code = "package local_gate\n" +
            "public func keep(v: Int64 @local!): Int64 @local! { v }\n" +
            "public func region(v: Int64): Int64 { exclave { v } }\n"
        let ci = CompileLocal(root, code, true, "off", true, CompileStage.CONDITION_COMPILE)
        println("EXECUTED SurvivingLocalAcceptedOnLinux stage=CONDITION_COMPILE errors=" + ci.diag.GetErrorCount().toString())
        @Expect(ci.diag.GetErrorCount(), 0u64)
        @Expect(HasMessage(ci.diag, LOCAL_TARGET_MESSAGE), false)
    }

    @TestCase
    public func DefaultModeStillRejectsLocalSyntax(): Unit {
        let root = FSDirectory.createTemp("/tmp").toString()
        let code = "package local_gate\npublic func keep(v: Int64 @local!): Int64 { v }\n"
        let ci = CompileLocal(root, code, false, "", true, CompileStage.PARSE)
        println("EXECUTED DefaultModeStillRejectsLocalSyntax errors=" + ci.diag.GetErrorCount().toString())
        @Expect(ci.diag.GetErrorCount() != 0, true)
        @Expect(HasMessage(ci.diag, LOCAL_TARGET_MESSAGE), false)
    }

    @TestCase
    public func ExplicitNotLocalDoesNotNeedLowering(): Unit {
        let root = FSDirectory.createTemp("/tmp").toString()
        let code = "package local_gate\npublic func plain(v: Int64 @~local): Int64 { v }\n"
        let ci = CompileLocal(root, code, true, "off", false, CompileStage.CONDITION_COMPILE)
        println("EXECUTED ExplicitNotLocalDoesNotNeedLowering errors=" + ci.diag.GetErrorCount().toString())
        @Expect(ci.diag.GetErrorCount(), 0u64)
        @Expect(HasMessage(ci.diag, LOCAL_TARGET_MESSAGE), false)
    }
}
