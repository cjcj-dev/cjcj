package cjcj::compiler_unittest

import std.collection.*
import std.env.*
import cjcj::ast.*
import cjcj::driver.HostTripleInfo
import cjcj::frontend.*
import cjcj::option.OutputMode
import cjcj::utils.{FileUtil, GenerateRandomHexString}

private let DEFAULT_TEST_CANGJIE_HOME: String = "/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029"

public class TestCompileResult {
    public let ok: Bool
    public let diag: DiagnosticEngine
    public let instance: CompilerInstance
    public let packages: ArrayList<Package>
    public let sourcePath: String

    public init(ok: Bool, diag: DiagnosticEngine, instance: CompilerInstance, packages: ArrayList<Package>,
        sourcePath: String) {
        this.ok = ok
        this.diag = diag
        this.instance = instance
        this.packages = packages
        this.sourcePath = sourcePath
    }

    public func FirstPackage(): Option<Package> {
        if (packages.isEmpty()) {
            return None
        }
        return Some(packages[0])
    }
}

private func CangjieHomeForTest(): String {
    for (entry in getVariables()) {
        if (entry[0] == "CANGJIE_HOME" && !entry[1].isEmpty()) {
            return entry[1]
        }
    }
    return DEFAULT_TEST_CANGJIE_HOME
}

private func NewTestSourcePath(): String {
    let dir = FileUtil.JoinPath("/tmp", "cangjie-selfhost-unittest")
    let _ = FileUtil.CreateDirs(dir + "/")
    return FileUtil.JoinPath(dir, "test_" + GenerateRandomHexString() + ".cj")
}

private func ConfigureInvocation(invocation: CompilerInvocation, sourcePath: String): Unit {
    let home = CangjieHomeForTest()
    let opts = invocation.globalOptions
    opts.srcFiles.add(sourcePath)
    opts.cangjieHome = home
    opts.executablePath = FileUtil.JoinPath(FileUtil.JoinPath(home, "bin"), "cjc")
    opts.host = HostTripleInfo()
    opts.target = HostTripleInfo()
    opts.outputMode = OutputMode.STATIC_LIB
    opts.output = FileUtil.JoinPath("/tmp", "cangjie-selfhost-unittest/out")
    opts.disableCodeGen = true
    opts.SetCompilationCachedPath()
    opts.UpdateCachedDirName("default")
}

public func CompileSource(code: String, stage!: CompileStage = CompileStage.SEMA): TestCompileResult {
    let sourcePath = NewTestSourcePath()
    let _ = FileUtil.WriteToFile(sourcePath, code)
    let diag = DiagnosticEngine()
    let invocation = CompilerInvocation()
    ConfigureInvocation(invocation, sourcePath)
    let instance = CompilerInstance(invocation, diag)
    instance.buildTrie = false
    let ok = instance.Compile(stage: stage)
    return TestCompileResult(ok, diag, instance, instance.GetSourcePackages(), sourcePath)
}

public func RequireFirstPackage(result: TestCompileResult): Package {
    if (let Some(pkg) <- result.FirstPackage()) {
        return pkg
    }
    throw IllegalStateException("compiler test produced no source package")
}

public func FindTopLevelFunc(pkg: Package, name: String): Option<FuncDecl> {
    for (file in pkg.files) {
        for (decl in file.decls) {
            if (let Some(funcDecl) <- (decl as FuncDecl)) {
                if (funcDecl.identifier.Val() == name) {
                    return Some(funcDecl)
                }
            }
        }
    }
    return None
}

public func RequireTopLevelFunc(pkg: Package, name: String): FuncDecl {
    if (let Some(funcDecl) <- FindTopLevelFunc(pkg, name)) {
        return funcDecl
    }
    throw IllegalStateException("missing top-level function: " + name)
}
