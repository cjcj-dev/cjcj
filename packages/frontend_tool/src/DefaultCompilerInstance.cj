package cjcj::frontend_tool

import std.collection.*
import cjcj::frontend.*
import cjcj::option.OutputMode
import cjcj::option.TempFileInfo
import cjcj::utils.FileUtil
import cjcj::utils.ProfileRecorder

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
            DumpASTToScreen(core.GetSourcePackages())
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
        return ProfiledBool("Main Stage", "CodeGen", { =>
            if (!PerformCodeGenImpl()) {
                return false
            }
            // Codegen rebuilds frontendOutputFiles from scratch for the emitted .bc modules
            // (CodeGenBridge clears the list first), which drops any .cjo output the earlier SAVE_CJO
            // stage would register. Re-register each serialized package .cjo here, after codegen, so
            // the driver publishes <pkg>.cjo next to the built library, mirroring the C++ driver
            // emitting the package interface alongside the object output.
            if (ShouldSaveCjoForOutputMode()) {
                RegisterCjoOutputs(core.GetSourcePackages())
            }
            return true
        })
    }

    private func RegisterCjoOutputs(pkgs: ArrayList<Package>): Unit {
        for (pkg in pkgs) {
            if (pkg.IsEmpty()) {
                continue
            }
            let cjoPath = invocation.globalOptions.GenerateCachedPathName(pkg.fullPackageName, SERIALIZED_FILE_EXTENSION)
            invocation.globalOptions.cjoOutputFiles.add(TempFileInfo(
                fileName: FileUtil.ToCjoFileName(pkg.fullPackageName),
                filePath: cjoPath,
                rawPath: cjoPath,
                isFrontendOutput: true))
        }
    }

    public open func PerformCjoSaving(): Bool {
        return ProfiledBool("Main Stage", "Save cjo", { =>
            if (!ShouldSaveCjoForOutputMode()) {
                return true
            }
            return SaveCjos(core.GetSourcePackages())
        })
    }

    public open func PerformResultsSaving(): Bool {
        return ProfiledBool("Main Stage", "Save results", { =>
            if (invocation.globalOptions.outputMode != OutputMode.CHIR) {
                return true
            }
            if (invocation.globalOptions.outputMode == OutputMode.CHIR || invocation.frontendOptions.chirDeserialize) {
                return SaveCjos(core.GetSourcePackages())
            }
            return true
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
        let pkgs = ArrayList<Package>()
        pkgs.add(pkg)
        let depInfos = core.importManager.GeneratePkgDepInfo(pkgs)
        let packageDepInfo = if (depInfos.isEmpty()) { "" } else { depInfos[0] }
        let data = SerializePackageToCjoFlatBuffer(pkg, packageDepInfo, core.importManager.GetCjoManager(),
            invocation.globalOptions.enableCompileDebug, invocation.globalOptions.optimizationLevel, diag: diag,
            serializingCommon: invocation.globalOptions.outputMode == OutputMode.CHIR,
            exportContent: core.importManager.IsSourceCodeImported(), exportFuncBody: true)
        if (!FileUtil.WriteBufferToASTFile(cjoPath, data)) {
            diag.Warn(DiagCategory.IMPORT_PACKAGE, DEFAULT_POSITION, "failed to write CJO: " + cjoPath)
            return false
        }
        if (ShouldPublishCjo()) {
            let publishedPath = PublishedCjoPath(pkg)
            if (!FileUtil.WriteBufferToASTFile(publishedPath, data)) {
                diag.Warn(DiagCategory.IMPORT_PACKAGE, DEFAULT_POSITION, "failed to write CJO: " + publishedPath)
                return false
            }
        }
        return true
    }

    private func ShouldPublishCjo(): Bool {
        return ShouldSaveCjoForOutputMode()
    }

    private func ShouldSaveCjoForOutputMode(): Bool {
        return invocation.globalOptions.outputMode == OutputMode.STATIC_LIB ||
            invocation.globalOptions.outputMode == OutputMode.SHARED_LIB
    }

    private func PublishedCjoPath(pkg: Package): String {
        let output = invocation.globalOptions.output
        let dir = if (output.isEmpty() || output == "./") { "." } else { FileUtil.GetDirPath(output) }
        return FileUtil.JoinPath(dir, PublishedCjoFileName(pkg.fullPackageName) + SERIALIZED_FILE_EXTENSION)
    }

    private func PublishedCjoFileName(fullPackageName: String): String {
        if (let Some(pos) <- fullPackageName.indexOf("::")) {
            return fullPackageName[pos + 2..] + "@" + fullPackageName[0..pos]
        }
        return fullPackageName
    }

    public func RearrangeImportedPackageDependence(): Unit {
        let imported = core.importManager.GetAllImportedPackages()
        let _ = core.packageManager.ResolveDependence(imported)
    }

    public func CodegenOnePackage(enableIncrement: Bool): Bool {
        if (invocation.globalOptions.disableCodeGen) {
            return true
        }
        if (enableIncrement) {
            for (pkg in core.GetSourcePackages()) {
                RecordIncrementalCodegenPackage(pkg, invocation.globalOptions.GenerateCachedPathName(
                    pkg.fullPackageName, ".frontend_tool.codegen"))
            }
        }
        return core.PerformCodeGen()
    }

    protected func SaveCjos(pkgs: ArrayList<Package>): Bool {
        if (pkgs.size > 1) {
            PreMangleExportDecls(pkgs)
        }
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

    private func PreMangleExportDecls(pkgs: ArrayList<Package>): Unit {
        let mangler = BaseMangler()
        let seen = HashSet<String>()
        for (pkg in pkgs) {
            if (pkg.IsEmpty()) {
                continue
            }
            for (file in pkg.files) {
                for (decl in file.decls) {
                    PreMangleDeclTree(mangler, pkg.fullPackageName, decl, seen)
                }
            }
            for (decl in pkg.genericInstantiatedDecls) {
                PreMangleDeclTree(mangler, pkg.fullPackageName, decl, seen)
            }
        }
    }

    private func PreMangleDeclTree(
        mangler: BaseMangler,
        pkgName: String,
        decl: Decl,
        seen: HashSet<String>
    ): Unit {
        let ownerKey = if (let Some(outer) <- decl.outerDecl) {
            "|owner|" + outer.identifier.Val() + "|" + ASTKindName(outer.astKind) + "|" +
                outer.begin.line.toString() + ":" + outer.begin.column.toString()
        } else {
            ""
        }
        let defaultOwnerKey = if (let Some(funcDecl) <- (decl as FuncDecl)) {
            if (funcDecl.TestAttr(Attribute.HAS_INITIAL)) {
                if (let Some(owner) <- funcDecl.ownerFunc) {
                    let ownerIdentity = if (!owner.rawMangleName.isEmpty()) {
                        owner.rawMangleName
                    } else if (!owner.mangledName.isEmpty()) {
                        owner.mangledName
                    } else {
                        owner.identifier.Val() + "|" + ASTKindName(owner.astKind) + "|" +
                            owner.begin.line.toString() + ":" + owner.begin.column.toString()
                    }
                    "|default-owner|" + ownerIdentity
                } else {
                    ""
                }
            } else {
                ""
            }
        } else {
            ""
        }
        let key = pkgName + ownerKey + defaultOwnerKey + "|" + ASTKindName(decl.astKind) + "|" + decl.identifier.Val() + "|" +
            decl.begin.line.toString() + ":" + decl.begin.column.toString()
        if (seen.contains(key)) {
            return
        }
        seen.add(key)
        if (decl.fullPackageName.isEmpty()) {
            decl.fullPackageName = pkgName
        }
        if (decl.mangledName.isEmpty()) {
            decl.mangledName = mangler.Mangle(decl)
        }
        if (let Some(generic) <- decl.generic) {
            for (typeParam in generic.typeParameters) {
                typeParam.outerDecl = Some(decl)
                PreMangleDeclTree(mangler, pkgName, typeParam, seen)
            }
        }
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            if (let Some(body) <- funcDecl.funcBody) {
                if (let Some(bodyGeneric) <- body.generic) {
                    for (typeParam2 in bodyGeneric.typeParameters) {
                        typeParam2.outerDecl = Some(decl)
                        PreMangleDeclTree(mangler, pkgName, typeParam2, seen)
                    }
                }
                for (paramList in body.paramLists) {
                    for (param in paramList.params) {
                        if (let Some(desugarDecl) <- param.desugarDecl) {
                            PreMangleDeclTree(mangler, pkgName, desugarDecl, seen)
                        }
                    }
                }
            }
        }
        for (member in decl.GetMemberDecls()) {
            PreMangleDeclTree(mangler, pkgName, member, seen)
        }
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

private func DumpASTToScreen(srcPkgs: ArrayList<Package>): Unit {
    for (pkg in srcPkgs) {
        println(RenderPackageTree(pkg))
    }
}

private func RenderPackageTree(pkg: Package): String {
    let builder = StringBuilder()
    builder.append("Package(" + pkg.fullPackageName + ")\n")
    for (file in pkg.files) {
        builder.append("  File(" + file.filePath + ")\n")
        if (let Some(packageSpec) <- file.packageSpec) {
            builder.append("    package " + packageSpec.GetPackageName() + "\n")
        }
        for (importSpec in file.imports) {
            builder.append("    import " + GetImportedItemFullName(importSpec.content) + "\n")
        }
        for (decl in file.decls) {
            AppendDeclTree(builder, decl, 2)
        }
    }
    return builder.toString()
}

private func AppendDeclTree(builder: StringBuilder, decl: Decl, indent: Int64): Unit {
    var spaces = ""
    var idx: Int64 = 0
    while (idx < indent) {
        spaces += "  "
        idx++
    }
    builder.append(spaces + ASTKindName(decl.astKind) + " " + decl.identifier.Val())
    if (!decl.mangledName.isEmpty()) {
        builder.append(" [" + decl.mangledName + "]")
    }
    builder.append("\n")
    for (member in decl.GetMemberDecls()) {
        AppendDeclTree(builder, member, indent + 1)
    }
}

private func RecordIncrementalCodegenPackage(pkg: Package, markerPath: String): Unit {
    if (!markerPath.isEmpty()) {
        let _ = FileUtil.WriteToFile(markerPath, RenderPackageCjo(pkg))
    }
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
    builder.append("  \"fileSummaries\": [\n")
    var summaryIdx: Int64 = 0
    while (summaryIdx < pkg.files.size) {
        if (summaryIdx > 0) {
            builder.append(",\n")
        }
        AppendFileCjoSummary(builder, pkg.files[summaryIdx])
        summaryIdx++
    }
    builder.append("\n  ],\n")
    builder.append("  \"declCount\": " + CountPackageDecls(pkg).toString() + ",\n")
    builder.append("  \"decls\": [")
    var declIdx: Int64 = 0
    for (file in pkg.files) {
        for (decl in file.decls) {
            if (declIdx > 0) {
                builder.append(", ")
            }
            AppendDeclCjo(builder, decl)
            declIdx++
        }
    }
    builder.append("],\n")
    builder.append("  \"genericInstantiatedDeclCount\": " + CountDeclList(pkg.genericInstantiatedDecls).toString() + ",\n")
    builder.append("  \"genericInstantiatedDecls\": [")
    var genIdx: Int64 = 0
    while (genIdx < pkg.genericInstantiatedDecls.size) {
        if (genIdx > 0) {
            builder.append(", ")
        }
        AppendDeclCjo(builder, pkg.genericInstantiatedDecls[genIdx])
        genIdx++
    }
    builder.append("]\n")
    builder.append("}\n")
    return builder.toString()
}

private func AppendFileCjoSummary(builder: StringBuilder, file: File): Unit {
    builder.append("    {")
    builder.append("\"path\":\"" + EscapeJson(file.filePath) + "\",")
    builder.append("\"hash\":\"" + file.fileHash.toString() + "\",")
    if (let Some(packageSpec) <- file.packageSpec) {
        builder.append("\"packageSpec\":\"" + EscapeJson(packageSpec.GetPackageName()) + "\",")
    } else {
        builder.append("\"packageSpec\":\"\",")
    }
    builder.append("\"imports\":")
    let imports = ArrayList<String>()
    for (importSpec in file.imports) {
        imports.add(GetImportedItemFullName(importSpec.content))
    }
    AppendStringArrayJson(builder, imports)
    builder.append(",\"decls\":[")
    var declIdx: Int64 = 0
    while (declIdx < file.decls.size) {
        if (declIdx > 0) {
            builder.append(", ")
        }
        AppendDeclCjo(builder, file.decls[declIdx])
        declIdx++
    }
    builder.append("],\"exportedInternalDecls\":[")
    var exportedIdx: Int64 = 0
    while (exportedIdx < file.exportedInternalDecls.size) {
        if (exportedIdx > 0) {
            builder.append(", ")
        }
        AppendDeclCjo(builder, file.exportedInternalDecls[exportedIdx])
        exportedIdx++
    }
    builder.append("]}")
}

private func AppendDeclCjo(builder: StringBuilder, decl: Decl): Unit {
    builder.append("{\"kind\":\"" + EscapeJson(ASTKindName(decl.astKind)) + "\",")
    builder.append("\"name\":\"" + EscapeJson(decl.identifier.Val()) + "\",")
    builder.append("\"rawName\":\"" + EscapeJson(decl.identifier.GetRawText()) + "\",")
    builder.append("\"package\":\"" + EscapeJson(decl.fullPackageName) + "\",")
    builder.append("\"mangled\":\"" + EscapeJson(decl.mangledName) + "\",")
    builder.append("\"exported\":" + decl.IsExportedDecl().toString() + ",")
    builder.append("\"range\":")
    AppendRangeJson(builder, decl.begin, decl.end)
    builder.append(",\"annotations\":")
    AppendAnnotationListJson(builder, decl.annotations)
    if (let Some(generic) <- decl.generic) {
        builder.append(",\"genericParams\":")
        AppendGenericParamArrayJson(builder, generic.typeParameters)
        builder.append(",\"genericConstraints\":")
        AppendGenericConstraintArrayJson(builder, generic.genericConstraints)
    } else {
        builder.append(",\"genericParams\":[]")
        builder.append(",\"genericConstraints\":[]")
    }
    let members = decl.GetMemberDecls()
    if (!members.isEmpty()) {
        builder.append(",\"members\":[")
        var memberIdx: Int64 = 0
        for (member in members) {
            if (memberIdx > 0) {
                builder.append(",")
            }
            AppendDeclCjo(builder, member)
            memberIdx++
        }
        builder.append("]")
    }
    builder.append("}")
}

private func AppendRangeJson(builder: StringBuilder, begin: Position, end: Position): Unit {
    builder.append("{\"begin\":{\"line\":" + begin.line.toString() + ",\"column\":" +
        begin.column.toString() + "},")
    builder.append("\"end\":{\"line\":" + end.line.toString() + ",\"column\":" +
        end.column.toString() + "}}")
}

private func AppendAnnotationListJson(builder: StringBuilder, annotations: ArrayList<Annotation>): Unit {
    builder.append("[")
    var annoIdx: Int64 = 0
    while (annoIdx < annotations.size) {
        if (annoIdx > 0) {
        builder.append(", ")
        }
        builder.append("{\"name\":\"" + EscapeJson(annotations[annoIdx].identifier.Val()) + "\",")
        builder.append("\"args\":")
        AppendAnnotationArgArrayJson(builder, annotations[annoIdx].args)
        builder.append("}")
        annoIdx++
    }
    builder.append("]")
}

private func AppendGenericParamArrayJson(builder: StringBuilder, values: ArrayList<GenericParamDecl>): Unit {
    builder.append("[")
    var idx: Int64 = 0
    while (idx < values.size) {
        if (idx > 0) {
            builder.append(", ")
        }
        builder.append("\"" + EscapeJson(values[idx].identifier.Val()) + "\"")
        idx++
    }
    builder.append("]")
}

private func AppendGenericConstraintArrayJson(builder: StringBuilder, values: ArrayList<GenericConstraint>): Unit {
    builder.append("[")
    var idx: Int64 = 0
    while (idx < values.size) {
        if (idx > 0) {
            builder.append(", ")
        }
        builder.append("\"" + EscapeJson(values[idx].ToString()) + "\"")
        idx++
    }
    builder.append("]")
}

private func AppendAnnotationArgArrayJson(builder: StringBuilder, values: ArrayList<FuncArg>): Unit {
    builder.append("[")
    var idx: Int64 = 0
    while (idx < values.size) {
        if (idx > 0) {
            builder.append(", ")
        }
        builder.append("\"" + EscapeJson(values[idx].ToString()) + "\"")
        idx++
    }
    builder.append("]")
}

private func AppendStringArrayJson(builder: StringBuilder, values: ArrayList<String>): Unit {
    builder.append("[")
    var idx: Int64 = 0
    while (idx < values.size) {
        if (idx > 0) {
            builder.append(", ")
        }
        builder.append("\"" + EscapeJson(values[idx]) + "\"")
        idx++
    }
    builder.append("]")
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

private func CountDeclList(decls: ArrayList<Decl>): Int64 {
    var count: Int64 = 0
    for (decl in decls) {
        count += CountDeclTree(decl)
    }
    return count
}

private func CountDeclTree(decl: Decl): Int64 {
    var count: Int64 = 1
    for (member in decl.GetMemberDecls()) {
        count += CountDeclTree(member)
    }
    return count
}
