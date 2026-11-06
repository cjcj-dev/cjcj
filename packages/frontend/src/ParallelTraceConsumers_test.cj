package cjcj::frontend

import std.collection.ArrayList
import std.env.getVariable
import std.fs.Directory as FSDirectory
import std.fs.File as FSFile
import std.fs.removeIfExists
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::macro_pkg.{MacroCall, MacroCollector, MacroEvaluation, MacroEvalStatus}
import cjcj::option.{MaybeUInt64, OptimizationLevel, OutputMode}

@Test
class ParallelTraceConsumersTest {
    @TestCase
    func ImportedGenericProgramReachesMangling(): Unit {
        let root = FSDirectory.createTemp(getVariable("TMPDIR").getOrThrow()).toString()
        var passed = false
        try {
            let path = root + "/input.cj"
            FSFile.writeTo(path, """
                package tracefixture
                import std.collection.*
                func identity<T>(value: T): T {
                    let first = value
                    let second = first
                    second
                }
                func left(): Int64 { identity<Int64>(1) }
                func right(): Int64 { identity<Int64>(2) }
                main(): Int64 { left() + right() }
                """.toArray())
            let invocation = CompilerInvocation()
            let opts = invocation.globalOptions
            opts.cangjieHome = getVariable("CANGJIE_HOME").getOrThrow()
            opts.executablePath = opts.cangjieHome + "/bin/cjc"
            opts.srcFiles.add(path)
            opts.output = root + "/result.a"
            opts.outputMode = OutputMode.STATIC_LIB
            opts.optimizationLevel = OptimizationLevel.O2
            opts.disableCodeGen = true
            opts.jobs = MaybeUInt64(8u64)
            opts.SetCompilationCachedPath()
            opts.UpdateCachedDirName("trace-consumers")
            let diag = DiagnosticEngine()
            let instance = CompilerInstance(invocation, diag)
            instance.buildTrie = false
            @Assert(instance.Compile(stage: CompileStage.MANGLING))
            @Expect(diag.GetErrorCount(), 0u64)
            @Expect(instance.GetSourcePackages().size, 1)
            @Expect(!instance.GetSourcePackages()[0].genericInstantiatedDecls.isEmpty())
            @Expect(!instance.ExportAST(false, instance.GetSourcePackages()[0]).isEmpty())
            passed = true
        } finally {
            if (passed) { let _ = removeIfExists(root, recursive: true) }
            else { println("PRESERVED_TRACE_CONSUMER ${root}") }
        }
    }

    @TestCase
    func NativeMacroFailureDrainsAllReadyCalls(): Unit {
        let invocation = CompilerInvocation()
        invocation.globalOptions.jobs = MaybeUInt64(8u64)
        let instance = CompilerInstance(invocation, DiagnosticEngine())
        let calls = ArrayList<MacroCall>()
        for (_ in 0..2) { calls.add(MacroCall(MacroExpandExpr())) }
        var failed = false
        try {
            MacroEvaluation(MacroHostAdapter(instance), MacroCollector(), false).EvaluateReadyNativeCalls(calls, flushReports: false)
        } catch (e: IllegalStateException) {
            @Expect(e.message, "macro task submitted to an unavailable runtime")
            failed = true
        }
        @Expect(failed)
        for (call in calls) {
            @Expect(call.status, MacroEvalStatus.FAIL)
            @Expect(call.deferReports)
            @Expect(call.reportsForServer)
            @Expect(!call.isDataReady)
        }
    }
}
