package cjcj::sema.resolver_tests

import cjcj::ast.*
import cjcj::compiler_unittest.*
import cjcj::frontend.*
import cjcj::driver.HostTripleInfo
import cjcj::option.{OutputMode, OptimizationLevel}
import cjcj::utils.{FileUtil, GenerateRandomHexString}
import std.env.getVariable

func CompileResolverSource(code: String): TestCompileResult {
    let directory = getVariable("TMPDIR").getOrThrow() + "/resolver-" + GenerateRandomHexString()
    let _ = FileUtil.CreateDirs(directory + "/")
    let path = directory + "/input.cj"
    let _ = FileUtil.WriteToFile(path, code)
    let invocation = CompilerInvocation()
    let opts = invocation.globalOptions
    let home = getVariable("CANGJIE_HOME").getOrThrow()
    opts.cangjieHome = home
    opts.executablePath = home + "/bin/cjc"
    opts.host = HostTripleInfo()
    opts.target = HostTripleInfo()
    opts.srcFiles.add(path)
    opts.outputMode = OutputMode.STATIC_LIB
    opts.output = directory + "/result.a"
    opts.disableCodeGen = true
    // PartialInstantiation.RequireInstantiation uses the real O2 product route.
    opts.optimizationLevel = OptimizationLevel.O2
    opts.SetCompilationCachedPath()
    opts.UpdateCachedDirName("resolver")
    let diag = DiagnosticEngine()
    let instance = CompilerInstance(invocation, diag)
    instance.buildTrie = false
    let ok = instance.Compile(stage: CompileStage.GENERIC_INSTANTIATION)
    return TestCompileResult(ok, diag, instance, instance.GetSourcePackages(), path)
}

func FindResolverDecl(result: TestCompileResult, name: String): Decl {
    for (file in RequireFirstPackage(result).files) {
        for (decl in file.decls) {
            if (decl.identifier.Val() == name) { return decl }
        }
    }
    throw IllegalStateException("missing resolver input declaration: " + name)
}

func FindResolverFunc(decl: Decl, name: String): FuncDecl {
    for (member in decl.GetMemberDecls()) {
        if (member.identifier.Val() == name) {
            if (let Some(fd) <- (member as FuncDecl)) { return fd }
        }
    }
    throw IllegalStateException("missing resolver input function: " + name)
}

