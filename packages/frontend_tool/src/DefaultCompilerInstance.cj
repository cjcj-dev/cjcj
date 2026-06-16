package cangjie_compiler::frontend_tool

import std.collection.*
import cangjie_compiler::frontend.*
import cangjie_compiler::utils.ProfileRecorder

public open class DefaultCompilerInstance {
    public let invocation: CompilerInvocation
    public let diag: DiagnosticEngine
    public let core: CompilerInstance

    public init(invocation: CompilerInvocation, diag: DiagnosticEngine) {
        this.invocation = invocation
        this.diag = diag
        core = CompilerInstance(invocation, diag)
        core.buildTrie = false
    }

    public func AsCompilerInstance(): CompilerInstance {
        return core
    }

    public open func InitCompilerInstance(): Bool {
        return core.InitCompilerInstance()
    }

    public func Compile(stage!: CompileStage = CompileStage.CHIR): Bool {
        if (!InitCompilerInstance()) {
            diag.ReportErrorAndWarningCount()
            return false
        }
        let endStageNum = CompileStageIndex(stage)
        var idx: Int64 = 0
        var success = true
        while (idx <= endStageNum) {
            if (!PerformStage(FrontendToolStageFromIndex(idx))) {
                success = false
                break
            }
            idx++
        }
        if (invocation.globalOptions.NeedDumpASTToScreen() && idx < CompileStageIndex(CompileStage.MANGLING)) {
            // TODO(selfhost:FrontendTool): call the frontend AST screen dumper once it is public; per-stage file dumps
            // are still produced by the underlying frontend stage methods.
            ()
        }
        diag.ReportErrorAndWarningCount()
        return success
    }

    public open func PerformPluginLoad(): Bool {
        return core.PerformPluginLoad()
    }

    public open func PerformParse(): Bool {
        return ProfiledBool("Main Stage", "Parser", { => core.PerformParse() })
    }

    public open func PerformConditionCompile(): Bool {
        return ProfiledBool("Main Stage", "ConditionalCompilation", { => core.PerformConditionCompile() })
    }

    public open func PerformImportPackage(): Bool {
        return ProfiledBool("Main Stage", "ImportPackages", { => core.PerformImportPackage() })
    }

    public open func PerformMacroExpand(): Bool {
        return ProfiledBool("Main Stage", "MacroExpand", { => core.PerformMacroExpand() })
    }

    public open func PerformIncrementalScopeAnalysis(): Bool {
        return core.PerformIncrementalScopeAnalysis()
    }

    public open func PerformSema(): Bool {
        return ProfiledBool("Main Stage", "Semantic", { => core.PerformSema() })
    }

    public open func PerformOverflowStrategy(): Bool {
        return ProfiledBool("Main Stage", "Overflow Strategy", { => core.PerformOverflowStrategy() })
    }

    public open func PerformDesugarAfterSema(): Bool {
        return ProfiledBool("Main Stage", "Desugar after Sema", { => core.PerformDesugarAfterSema() })
    }

    public open func PerformGenericInstantiation(): Bool {
        return ProfiledBool("Main Stage", "Generic Instantiation", { => core.PerformGenericInstantiation() })
    }

    public open func PerformMangling(): Bool {
        return ProfiledBool("Main Stage", "Perform Mangling", { => core.PerformMangling() })
    }

    public open func PerformCHIRCompilation(): Bool {
        return ProfiledBool("Main Stage", "CHIR", { => core.PerformCHIRCompilation() })
    }

    public open func PerformCodeGen(): Bool {
        return ProfiledBool("Main Stage", "CodeGen", { => PerformCodeGenImpl() })
    }

    public open func PerformCjoSaving(): Bool {
        return ProfiledBool("Main Stage", "Save cjo", { => SaveCjos(core.GetSourcePackages()) })
    }

    public open func PerformResultsSaving(): Bool {
        return ProfiledBool("Main Stage", "Save results", { =>
            if (invocation.frontendOptions.chirDeserialize) {
                return SaveCjos(core.GetSourcePackages())
            }
            return core.PerformResultsSaving()
        })
    }

    public func DumpTokens(): Bool {
        return core.DumpTokens()
    }

    public func DumpSymbols(): Unit {
        core.DumpSymbols()
    }

    public func DeserializeCHIR(): Bool {
        return core.DeserializeCHIR()
    }

    public func GetSourcePackages(): ArrayList<Package> {
        return core.GetSourcePackages()
    }

    public func GetDepPkgInfo(): ArrayList<String> {
        return core.GetDepPkgInfo()
    }

    public func GetAllCHIRPackages(): ArrayList<CHIRPackage> {
        return core.GetAllCHIRPackages()
    }

    public func UpdateAndWriteCachedInfoToDisk(): Bool {
        return core.UpdateAndWriteCachedInfoToDisk()
    }

    public func DumpDepPackage(): Unit {
        for (depPkgInfo in core.GetDepPkgInfo()) {
            println(depPkgInfo)
        }
    }

    public func SaveCjo(pkg: Package): Bool {
        if (pkg.IsEmpty()) {
            return true
        }
        let cjoPath = invocation.globalOptions.GenerateCachedPathName(pkg.fullPackageName, SERIALIZED_FILE_EXTENSION)
        if (!WriteFileContent(cjoPath, RenderPackageCjo(pkg))) {
            diag.Warn(DiagCategory.IMPORT_PACKAGE, DEFAULT_POSITION, "failed to write CJO summary: " + cjoPath)
            return false
        }
        return true
    }

    public func RearrangeImportedPackageDependence(): Unit {
        let imported = core.importManager.GetAllImportedPackages()
        let _ = core.packageManager.ResolveDependence(imported)
    }

    public func CodegenOnePackage(enableIncrement: Bool): Bool {
        let _ = enableIncrement
        // TODO(selfhost:FrontendTool): wire this to native CodeGen once frontend.CHIRData and codegen.CHIRData share
        // the same model; until then the frontend package's codegen hook is the only compatible implementation.
        return core.PerformCodeGen()
    }

    protected func SaveCjos(pkgs: ArrayList<Package>): Bool {
        var ret = true
        for (pkg in pkgs) {
            ret = SaveCjo(pkg) && ret
        }
        return ret
    }

    private func PerformCodeGenImpl(): Bool {
        let chirPkgs = core.GetAllCHIRPackages()
        if (chirPkgs.size <= 1) {
            return CodegenOnePackage(false)
        }
        var ret = true
        let savedPackage = core.chirData.GetCurrentCHIRPackage()
        for (pkg in chirPkgs) {
            core.chirData.SetCurrentCHIRPackage(Some(pkg))
            core.chirData.ActivateCodegenFuncsForPackage(pkg)
            if (!CodegenOnePackage(false)) {
                ret = false
                break
            }
        }
        core.chirData.SetCurrentCHIRPackage(savedPackage)
        core.FreeCHIRData()
        return ret
    }

    private func PerformStage(stage: CompileStage): Bool {
        if (stage == CompileStage.LOAD_PLUGINS) { return PerformPluginLoad() }
        if (stage == CompileStage.PARSE) { return PerformParse() }
        if (stage == CompileStage.CONDITION_COMPILE) { return PerformConditionCompile() }
        if (stage == CompileStage.IMPORT_PACKAGE) { return PerformImportPackage() }
        if (stage == CompileStage.MACRO_EXPAND) { return PerformMacroExpand() }
        if (stage == CompileStage.AST_DIFF) { return PerformIncrementalScopeAnalysis() }
        if (stage == CompileStage.SEMA) { return PerformSema() }
        if (stage == CompileStage.DESUGAR_AFTER_SEMA) { return PerformDesugarAfterSema() }
        if (stage == CompileStage.GENERIC_INSTANTIATION) { return PerformGenericInstantiation() }
        if (stage == CompileStage.OVERFLOW_STRATEGY) { return PerformOverflowStrategy() }
        if (stage == CompileStage.MANGLING) { return PerformMangling() }
        if (stage == CompileStage.SAVE_CJO) { return PerformCjoSaving() }
        if (stage == CompileStage.CHIR) { return PerformCHIRCompilation() }
        if (stage == CompileStage.CODEGEN) { return PerformCodeGen() }
        if (stage == CompileStage.SAVE_RESULTS) { return PerformResultsSaving() }
        return true
    }
}

private func FrontendToolStageFromIndex(idx: Int64): CompileStage {
    if (idx == 0) { return CompileStage.LOAD_PLUGINS }
    if (idx == 1) { return CompileStage.PARSE }
    if (idx == 2) { return CompileStage.CONDITION_COMPILE }
    if (idx == 3) { return CompileStage.IMPORT_PACKAGE }
    if (idx == 4) { return CompileStage.MACRO_EXPAND }
    if (idx == 5) { return CompileStage.AST_DIFF }
    if (idx == 6) { return CompileStage.SEMA }
    if (idx == 7) { return CompileStage.DESUGAR_AFTER_SEMA }
    if (idx == 8) { return CompileStage.GENERIC_INSTANTIATION }
    if (idx == 9) { return CompileStage.OVERFLOW_STRATEGY }
    if (idx == 10) { return CompileStage.MANGLING }
    if (idx == 11) { return CompileStage.SAVE_CJO }
    if (idx == 12) { return CompileStage.CHIR }
    if (idx == 13) { return CompileStage.CODEGEN }
    return CompileStage.SAVE_RESULTS
}

private func ProfiledBool(title: String, subtitle: String, action: () -> Bool): Bool {
    let recorder = ProfileRecorder(title, subtitle)
    let ret = action()
    recorder.close()
    return ret
}

private func RenderPackageCjo(pkg: Package): String {
    let builder = StringBuilder()
    builder.append("{\n")
    builder.append("  \"package\": \"" + EscapeJson(pkg.fullPackageName) + "\",\n")
    builder.append("  \"files\": [")
    var fileIdx: Int64 = 0
    while (fileIdx < pkg.files.size) {
        if (fileIdx > 0) {
            builder.append(", ")
        }
        builder.append("\"" + EscapeJson(pkg.files[fileIdx].filePath) + "\"")
        fileIdx++
    }
    builder.append("],\n")
    builder.append("  \"declCount\": " + CountPackageDecls(pkg).toString() + "\n")
    builder.append("}\n")
    return builder.toString()
}

private func CountPackageDecls(pkg: Package): Int64 {
    var count: Int64 = 0
    for (file in pkg.files) {
        for (decl in file.decls) {
            count += CountDeclTree(decl)
        }
    }
    return count
}

private func CountDeclTree(decl: Decl): Int64 {
    var count: Int64 = 1
    for (member in decl.members) {
        count += CountDeclTree(member)
    }
    return count
}
