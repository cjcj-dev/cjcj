package metadata_inspector

import std.collection.*
import cjcj::chir.{Attribute, ClassDef}
import cjcj::driver.HostTripleInfo
import cjcj::frontend.{CompilerInvocation, CompileStage, DiagnosticEngine}
import cjcj::frontend_tool.DefaultCompilerInstance
import cjcj::option.{OutputMode, TempFileManager}

// Exercise the frontend's normal compilation stages and retain the actual CHIR
// objects so their attributes can be checked after reflection metadata emission.
main(args: Array<String>): Int64 {
    if (args.size != 3) {
        println("usage: inspect SDK SOURCE OUTPUT")
        return 2
    }
    let invocation = CompilerInvocation()
    let opts = invocation.globalOptions
    opts.srcFiles.add(args[1])
    opts.cangjieHome = args[0]
    opts.executablePath = args[0] + "/bin/cjc"
    opts.host = HostTripleInfo()
    opts.target = HostTripleInfo()
    opts.outputMode = OutputMode.STATIC_LIB
    opts.output = args[2]
    opts.SetCompilationCachedPath()
    opts.UpdateCachedDirName("reflection_attrs")
    if (!TempFileManager.Instance().Init(opts, true)) { return 3 }
    let diag = DiagnosticEngine()
    let instance = DefaultCompilerInstance(invocation, diag)
    instance.core.releaseCHIRMemory = false
    if (!instance.Compile(stage: CompileStage.CHIR)) { return 4 }
    let defs = ArrayList<ClassDef>()
    let before = ArrayList<String>()
    for (pkg in instance.core.chirData.getOrThrow().GetAllRealCHIRPackages()) {
        for (cd in pkg.GetClasses()) {
            defs.add(cd)
            before.add(cd.GetAttributeInfo().ToString())
        }
    }
    if (!instance.PerformCodeGen()) { return 5 }
    var failed = false
    var implicitCount = 0
    for (i in 0..defs.size) {
        let cd = defs[i]
        let name = cd.GetSrcCodeIdentifier()
        let unchanged = cd.GetAttributeInfo().ToString() == before[i]
        println("CHIR " + name + " before=" + before[i] + " after=" + cd.GetAttributeInfo().ToString())
        if (!unchanged) { failed = true }
        if (name == "ImplicitOpen" || name == "GenericOpen") {
            implicitCount++
            let valid = cd.TestAttr(Attribute.ABSTRACT) && !cd.TestAttr(Attribute.VIRTUAL)
            println("ASSERT original_" + name + "=" + valid.toString())
            if (!valid) { failed = true }
        }
    }
    println("ASSERT original_attributes_unchanged=" + (!failed && implicitCount == 2).toString())
    for (file in opts.frontendOutputFiles) { println("BITCODE " + file.filePath) }
    instance.JoinDestroyASTResources()
    return if (failed || implicitCount != 2) { 1 } else { 0 }
}
