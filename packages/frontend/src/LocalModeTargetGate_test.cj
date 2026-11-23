package cjcj::frontend

import cjcj::option.{ArchType, EnvironmentType, OSType, OptimizationLevel, OutputMode}
import std.collection.*
import std.env.getVariable
import std.fs.Directory as FSDirectory
import std.fs.File as FSFile
import std.unittest.*
import std.unittest.testmacro.*

private let LOCAL_TARGET_MESSAGE: String = "local mode lowering is only supported on Linux x86_64 GNU targets"

private func HasMessage(diag: DiagnosticEngine, text: String): Bool {
    let stored = diag.AsBasicDiagnosticEngine().GetCategoryDiagnostic(DiagCategory.SEMA)
    for (item in stored) {
        if (item.errorMessage.contains(text) || item.diagMessage.contains(text)) { return true }
    }
    let parsed = diag.AsBasicDiagnosticEngine().GetCategoryDiagnostic(DiagCategory.PARSE)
    for (item in parsed) {
        if (item.errorMessage.contains(text) || item.diagMessage.contains(text)) { return true }
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

    @TestCase
    public func MacroDeletesLocalPassesOnWasm(): Unit {
        let root = FSDirectory.createTemp("/tmp").toString()
        let code = "package local_gate\n" +
            "@StripLocal\n" +
            "public func wrapped(v: Int64 @local!): Int64 { v }\n" +
            "public func always(v: Int64): Int64 { v }\n"
        let ci = CompileLocal(root, code, true, "off", false, CompileStage.CONDITION_COMPILE)
        println("EXECUTED MacroDeletesLocalPassesOnWasm errors=" + ci.diag.GetErrorCount().toString() +
            " inputLocal=" + UnexpandedInputHasLocal(ci).toString())
        @Expect(UnexpandedInputHasLocal(ci), true)
        @Expect(ci.diag.GetErrorCount(), 0u64)
        @Expect(HasMessage(ci.diag, LOCAL_TARGET_MESSAGE), false)
    }

    @TestCase
    public func MacroIntroducesLocalRejectedOnWasm(): Unit {
        let root = FSDirectory.createTemp("/tmp").toString()
        let code = "package local_gate\n@Wrap\npublic func plain(v: Int64): Int64 { v }\n"
        let ci = CompileLocal(root, code, true, "off", false, CompileStage.CONDITION_COMPILE)
        let donor = CompileDonor("public func region(v: Int64): Int64 { exclave { v } }\n")
        let introduced = SourceDecl(donor, "region")
        let replaced = ReplaceMacroInputs(ci, introduced)
        println("EXECUTED MacroIntroducesLocalRejectedOnWasm replaced=" + replaced.toString() +
            " exclave=" + CountAstKind(donor, ASTKind.EXCLAVE_EXPR).toString())
        @Expect(ci.diag.GetErrorCount(), 0u64)
        @Expect(replaced, 1)
        @Expect(CountAstKind(donor, ASTKind.EXCLAVE_EXPR) != 0, true)
        @Expect(CheckLocalModeLoweringTarget(ci), false)
        @Expect(HasMessage(ci.diag, LOCAL_TARGET_MESSAGE), true)
    }

    @TestCase
    public func InstantiatedLocalRejectedWhenFileClean(): Unit {
        let host = CompileWasmPlain()
        let donor = CompileDonor("public func keep(v: Int64 @local!): Int64 { v }\n")
        let decl = SourceDecl(donor, "keep")
        @Expect(FirstSurvivingLocalPosition(decl).isSome(), true)
        host.GetSourcePackages()[0].genericInstantiatedDecls.add(decl)
        println("EXECUTED InstantiatedLocalRejectedWhenFileClean")
        @Expect(CheckLocalModeLoweringTarget(host), false)
        @Expect(HasMessage(host.diag, LOCAL_TARGET_MESSAGE), true)
    }

    @TestCase
    public func InstantiatedPlainPasses(): Unit {
        let host = CompileWasmPlain()
        let donor = CompileDonor("public func plain(v: Int64): Int64 { v }\n")
        host.GetSourcePackages()[0].genericInstantiatedDecls.add(SourceDecl(donor, "plain"))
        println("EXECUTED InstantiatedPlainPasses")
        @Expect(CheckLocalModeLoweringTarget(host), true)
        @Expect(HasMessage(host.diag, LOCAL_TARGET_MESSAGE), false)
    }

    @TestCase
    public func SrcImportedBodyRejectedWhenFileClean(): Unit {
        let host = CompileWasmPlain()
        let donor = CompileDonor("public func region(v: Int64): Int64 { exclave { v } }\n")
        let decl = SourceDecl(donor, "region")
        host.GetSourcePackages()[0].srcImportedNonGenericDecls.add(decl)
        println("EXECUTED SrcImportedBodyRejectedWhenFileClean exclave=" +
            CountAstKind(donor, ASTKind.EXCLAVE_EXPR).toString())
        @Expect(CountAstKind(donor, ASTKind.EXCLAVE_EXPR) != 0, true)
        @Expect(CheckLocalModeLoweringTarget(host), false)
        @Expect(HasMessage(host.diag, LOCAL_TARGET_MESSAGE), true)
    }

    @TestCase
    public func ImportedConstBodyRejectedOnWasm(): Unit {
        let host = CompileWasmPlain()
        let donor = CompileDonor("public func region(v: Int64): Int64 { exclave { v } }\n")
        let decl = SourceDecl(donor, "region")
        MarkTranslatedImport(decl, constBody: true, frozenBody: false)
        AddImportedDecl(host, decl, "imported_const_body")
        println("EXECUTED ImportedConstBodyRejectedOnWasm")
        @Expect(FirstSurvivingLocalPosition(decl).isSome(), true)
        @Expect(CheckLocalModeLoweringTarget(host), false)
        @Expect(HasMessage(host.diag, LOCAL_TARGET_MESSAGE), true)
    }

    @TestCase
    public func ImportedUnusedSignaturePasses(): Unit {
        let host = CompileWasmPlain()
        let donor = CompileDonor("public func ext(v: Int64 @local!): Int64 { v }\n")
        let decl = SourceDecl(donor, "ext")
        AddImportedDecl(host, decl, "imported_unused_sig")
        println("EXECUTED ImportedUnusedSignaturePasses local=" + FirstSurvivingLocalPosition(decl).isSome().toString())
        @Expect(FirstSurvivingLocalPosition(decl).isSome(), true)
        @Expect(decl.isUsedImports, false)
        @Expect(CheckLocalModeLoweringTarget(host), true)
        @Expect(HasMessage(host.diag, LOCAL_TARGET_MESSAGE), false)
    }

    @TestCase
    public func ImportedFrozenBodyFollowsOptLevel(): Unit {
        let host = CompileWasmPlain()
        let donor = CompileDonor("public func region(v: Int64): Int64 { exclave { v } }\n")
        let decl = SourceDecl(donor, "region")
        MarkTranslatedImport(decl, constBody: false, frozenBody: true)
        AddImportedDecl(host, decl, "imported_frozen_body")
        host.invocation.globalOptions.optimizationLevel = OptimizationLevel.O0
        host.invocation.globalOptions.disableChirOpt = false
        println("EXECUTED ImportedFrozenBodyFollowsOptLevel belowO2")
        @Expect(CheckLocalModeLoweringTarget(host), true)
        @Expect(HasMessage(host.diag, LOCAL_TARGET_MESSAGE), false)
        host.invocation.globalOptions.optimizationLevel = OptimizationLevel.O2
        println("EXECUTED ImportedFrozenBodyFollowsOptLevel overO2")
        @Expect(CheckLocalModeLoweringTarget(host), false)
        @Expect(HasMessage(host.diag, LOCAL_TARGET_MESSAGE), true)
    }

    @TestCase
    public func StandaloneExclaveRejectedOnWasm(): Unit {
        let root = FSDirectory.createTemp("/tmp").toString()
        let code = "package local_gate\npublic func region(v: Int64): Int64 { exclave { v } }\n"
        let ci = CompileLocal(root, code, true, "off", false, CompileStage.CONDITION_COMPILE)
        println("EXECUTED StandaloneExclaveRejectedOnWasm exclave=" + CountAstKind(ci, ASTKind.EXCLAVE_EXPR).toString())
        @Expect(CountAstKind(ci, ASTKind.EXCLAVE_EXPR) != 0, true)
        @Expect(ci.diag.GetErrorCount() != 0, true)
        @Expect(HasMessage(ci.diag, LOCAL_TARGET_MESSAGE), true)
    }

    @TestCase
    public func DefaultExclaveIsNotLocalSyntax(): Unit {
        let root = FSDirectory.createTemp("/tmp").toString()
        let code = "package local_gate\npublic func region(v: Int64): Int64 { exclave { v } }\n"
        let ci = CompileLocal(root, code, false, "", true, CompileStage.PARSE)
        println("EXECUTED DefaultExclaveIsNotLocalSyntax exclave=" + CountAstKind(ci, ASTKind.EXCLAVE_EXPR).toString() +
            " ref=" + HasRefName(ci, "exclave").toString() + " errors=" + ci.diag.GetErrorCount().toString())
        @Expect(CountAstKind(ci, ASTKind.EXCLAVE_EXPR), 0)
        @Expect(HasRefName(ci, "exclave"), true)
        @Expect(HasMessage(ci.diag, LOCAL_TARGET_MESSAGE), false)
    }

    @TestCase
    public func StandaloneExclaveAcceptedOnLinux(): Unit {
        let root = FSDirectory.createTemp("/tmp").toString()
        let code = "package local_gate\npublic func region(v: Int64): Int64 { exclave { v } }\n"
        let ci = CompileLocal(root, code, true, "off", true, CompileStage.CONDITION_COMPILE)
        println("EXECUTED StandaloneExclaveAcceptedOnLinux exclave=" + CountAstKind(ci, ASTKind.EXCLAVE_EXPR).toString())
        @Expect(CountAstKind(ci, ASTKind.EXCLAVE_EXPR) != 0, true)
        @Expect(ci.diag.GetErrorCount(), 0u64)
        @Expect(HasMessage(ci.diag, LOCAL_TARGET_MESSAGE), false)
    }
}

private func CompileDonor(code: String): CompilerInstance {
    let root = FSDirectory.createTemp("/tmp").toString()
    return CompileLocal(root, "package local_donor\n" + code, true, "off", true, CompileStage.CONDITION_COMPILE)
}

private func CompileWasmPlain(): CompilerInstance {
    let root = FSDirectory.createTemp("/tmp").toString()
    let ci = CompileLocal(root, "package local_gate\npublic func always(v: Int64): Int64 { v }\n", true, "off", false,
        CompileStage.CONDITION_COMPILE)
    if (ci.diag.GetErrorCount() != 0) {
        throw Exception("plain wasm host errors=" + ci.diag.GetErrorCount().toString())
    }
    return ci
}

private func SourceDecl(ci: CompilerInstance, name: String): Decl {
    for (pkg in ci.GetSourcePackages()) {
        for (file in pkg.files) {
            for (decl in file.decls) {
                if (decl.identifier.Val() == name) { return decl }
            }
        }
    }
    throw Exception("missing decl " + name)
}

private func ReplaceMacroInputs(ci: CompilerInstance, replacement: Decl): Int64 {
    var replaced: Int64 = 0
    for (pkg in ci.GetSourcePackages()) {
        for (file in pkg.files) {
            let kept = ArrayList<Decl>()
            for (decl in file.decls) {
                if (decl.astKind == ASTKind.MACRO_EXPAND_DECL) {
                    kept.add(replacement)
                    replaced++
                } else {
                    kept.add(decl)
                }
            }
            file.decls.clear()
            for (decl in kept) { file.decls.add(decl) }
        }
    }
    return replaced
}

private func MarkTranslatedImport(decl: Decl, constBody!: Bool, frozenBody!: Bool): Unit {
    decl.EnableAttr(Attribute.IMPORTED)
    decl.isUsedImports = true
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        funcDecl.isConst = constBody
        funcDecl.isFrozen = frozenBody
    }
}

private func AddImportedDecl(ci: CompilerInstance, decl: Decl, pkgName: String): Unit {
    let pkg = Package(pkgName)
    pkg.EnableAttr(Attribute.IMPORTED)
    let file = File()
    file.begin = decl.begin
    file.decls.add(decl)
    pkg.files.add(file)
    ci.importManager.getOrThrow().AddImportedPackage(pkg)
}

private func UnexpandedInputHasLocal(ci: CompilerInstance): Bool {
    for (pkg in ci.GetSourcePackages()) {
        for (file in pkg.files) {
            for (decl in file.decls) {
                if (let Some(macroDecl) <- (decl as MacroExpandDecl)) {
                    if (let Some(input) <- macroDecl.invocation.decl) {
                        return FirstSurvivingLocalPosition(input).isSome()
                    }
                }
            }
        }
    }
    return false
}

private func CountAstKind(ci: CompilerInstance, kind: ASTKind): Int64 {
    var count: Int64 = 0
    for (pkg in ci.GetSourcePackages()) {
        let hits = ArrayList<Int64>()
        Walker(pkg, visitPre: { node: Node =>
            if (node.astKind == kind) { hits.add(1) }
            VisitAction.WALK_CHILDREN
        }).Walk()
        count = count + hits.size
    }
    return count
}

private func HasRefName(ci: CompilerInstance, name: String): Bool {
    for (pkg in ci.GetSourcePackages()) {
        let hits = ArrayList<Int64>()
        Walker(pkg, visitPre: { node: Node =>
            if (let Some(refExpr) <- (node as RefExpr)) {
                if (refExpr.ref.identifier.Val() == name) {
                    hits.add(1)
                    return VisitAction.STOP_NOW
                }
            }
            VisitAction.WALK_CHILDREN
        }).Walk()
        if (!hits.isEmpty()) { return true }
    }
    return false
}
