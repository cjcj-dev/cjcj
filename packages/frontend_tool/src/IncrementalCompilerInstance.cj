package cangjie_compiler::frontend_tool

import std.collection.*
import cangjie_compiler::frontend.*
import cangjie_compiler::incremental_compilation.CachedMangleMap
import cangjie_compiler::incremental_compilation.IncreKind
import cangjie_compiler::incremental_compilation.IncrementalCompilationLogger
import cangjie_compiler::option.OutputMode
import cangjie_compiler::utils.FileUtil
import cangjie_compiler::utils.ProfileRecorder

public class IncrementalCompilerInstance <: DefaultCompilerInstance {
    public let cacheMangles: CachedMangleMap = CachedMangleMap()
    public let changedTypes: HashSet<String> = HashSet<String>()
    public var kind: IncreKind = IncreKind.INVALID
    private let declsToBeReCompiled: HashSet<String> = HashSet<String>()
    private let rawIncrRemovedDecls: ArrayList<String> = ArrayList<String>()
    private let filesToBeReCompiled: HashSet<String> = HashSet<String>()
    private let rawIncrRemovedFiles: ArrayList<String> = ArrayList<String>()
    private var currentCacheText: String = ""

    public init(invocation: CompilerInvocation, diag: DiagnosticEngine) {
        super(invocation, diag)
    }

    public override func InitCompilerInstance(): Bool {
        return core.InitCompilerInstance()
    }

    public override func PerformIncrementalScopeAnalysis(): Bool {
        let recorder = ProfileRecorder("Main Stage", "AST Diff")
        declsToBeReCompiled.clear()
        rawIncrRemovedDecls.clear()
        filesToBeReCompiled.clear()
        rawIncrRemovedFiles.clear()
        currentCacheText = ""
        let calculated = core.CalculateASTCache()
        let sourcePackages = core.GetSourcePackages()
        if (!calculated || sourcePackages.isEmpty()) {
            kind = IncreKind.EMPTY_PKG
        } else if (sourcePackages.size != 1) {
            kind = IncreKind.ROLLBACK
            IncrementalCompilationLogger.GetInstance().LogLn(
                "incremental compilation expects exactly one source package, roll back to full compilation")
        } else if (!invocation.globalOptions.pluginPaths.isEmpty()) {
            kind = IncreKind.ROLLBACK
            IncrementalCompilationLogger.GetInstance().LogLn(
                "enable plugin, roll back to full compilation")
            diag.Warn(DiagCategory.OTHER, DEFAULT_POSITION,
                "`--incremental-compile` is incompatible with `--plugin` and will be ignored.")
        } else {
            kind = AnalyseCurrentFrontendCache()
        }
        LogIncrementalAnalysisResult()
        recorder.close()
        return true
    }

    public override func PerformSema(): Bool {
        LogIncrementalStageDecision("Semantic", "no change, skip sema", "full sema", "incremental sema")
        if (kind == IncreKind.NO_CHANGE || kind == IncreKind.EMPTY_PKG) {
            return true
        }
        return super.PerformSema()
    }

    public override func PerformOverflowStrategy(): Bool {
        if (kind == IncreKind.NO_CHANGE || kind == IncreKind.EMPTY_PKG) {
            return true
        }
        return super.PerformOverflowStrategy()
    }

    public override func PerformDesugarAfterSema(): Bool {
        if (kind == IncreKind.NO_CHANGE || kind == IncreKind.EMPTY_PKG) {
            return true
        }
        return super.PerformDesugarAfterSema()
    }

    public override func PerformGenericInstantiation(): Bool {
        if (kind == IncreKind.NO_CHANGE || kind == IncreKind.EMPTY_PKG) {
            return true
        }
        let ret = super.PerformGenericInstantiation()
        if (ret) {
            CollectChangedTypeNames()
        }
        return ret
    }

    public override func PerformMangling(): Bool {
        if (kind == IncreKind.NO_CHANGE || kind == IncreKind.EMPTY_PKG) {
            return true
        }
        return super.PerformMangling()
    }

    public override func PerformCHIRCompilation(): Bool {
        if (kind == IncreKind.NO_CHANGE || kind == IncreKind.EMPTY_PKG) {
            return true
        }
        return super.PerformCHIRCompilation()
    }

    public override func PerformCodeGen(): Bool {
        if (kind == IncreKind.NO_CHANGE) {
            for (srcPkg in core.GetSourcePackages()) {
                LoadCachedCodegenResult()
                invocation.globalOptions.UpdateCachedDirName(srcPkg.fullPackageName)
            }
            return true
        }
        if (kind == IncreKind.EMPTY_PKG) {
            return true
        }
        if (kind == IncreKind.INCR) {
            return CodegenOnePackage(true)
        }
        return super.PerformCodeGen()
    }

    public override func PerformCjoSaving(): Bool {
        LogCjoSavingDecision()
        if (kind == IncreKind.NO_CHANGE || kind == IncreKind.EMPTY_PKG) {
            return true
        }
        return super.PerformCjoSaving()
    }

    public override func PerformResultsSaving(): Bool {
        if (kind == IncreKind.NO_CHANGE || kind == IncreKind.EMPTY_PKG) {
            return true
        }
        let ret = super.PerformResultsSaving()
        if (ret) {
            return SaveIncrementalSignatures()
        }
        return ret
    }

    private func LogIncrementalStageDecision(
        stageName: String,
        noChangeMessage: String,
        rollbackMessage: String,
        incrementalMessage: String
    ): Unit {
        let logger = IncrementalCompilationLogger.GetInstance()
        if (!logger.IsEnable()) {
            return
        }
        let message = if (kind == IncreKind.NO_CHANGE) {
            noChangeMessage
        } else if (kind == IncreKind.ROLLBACK) {
            rollbackMessage
        } else if (kind == IncreKind.INCR) {
            incrementalMessage
        } else if (kind == IncreKind.EMPTY_PKG) {
            "empty pkg, skip " + stageName
        } else {
            "invalid incremental state for " + stageName
        }
        logger.LogLn(message)
    }

    private func LogCjoSavingDecision(): Unit {
        let logger = IncrementalCompilationLogger.GetInstance()
        if (!logger.IsEnable()) {
            return
        }
        let message = if (kind == IncreKind.NO_CHANGE) {
            "no change, skip cjo saving"
        } else if (kind == IncreKind.EMPTY_PKG) {
            "empty pkg, skip cjo saving"
        } else if (invocation.globalOptions.outputMode == OutputMode.CHIR) {
            " chir output mode, skip cjo saving"
        } else {
            "incremental cjo saving"
        }
        logger.LogLn(message)
    }

    private func LoadCachedCodegenResult(): Unit {
        // TODO(selfhost:frontend_tool): C++ replays cachedInfo.bitcodeFilesName into frontendOutputFiles.
        // frontend.CompilationCache in the stable DAG does not expose bitcode file names yet.
    }

    private func LogIncrementalAnalysisResult(): Unit {
        let logger = IncrementalCompilationLogger.GetInstance()
        if (!logger.IsEnable()) {
            return
        }
        if (kind == IncreKind.ROLLBACK) {
            logger.LogLn("incremental compile result kind: rollback")
        } else if (kind == IncreKind.EMPTY_PKG) {
            logger.LogLn("incremental compile result kind: empty package")
        } else if (kind == IncreKind.NO_CHANGE) {
            logger.LogLn("incremental compile result kind: no change")
        } else if (kind == IncreKind.INCR) {
            let delimiter = MakeIncrementalDumpDelimiter()
            logger.LogLn(delimiter)
            logger.LogLn("incremental compilation triggered")
            logger.LogLn("begin dump incremental compile result:")
            LogStringSetWithCount("changed decls to recompile: ", "the changed decl after Spreading is:",
                declsToBeReCompiled)
            logger.LogLn(delimiter)
            LogStringListWithCount("deleted decls: ", "the deleted decl is:", rawIncrRemovedDecls)
            logger.LogLn(delimiter)
            LogStringSetWithCount("changed files to recompile: ", "the changed file summary is:",
                filesToBeReCompiled)
            LogStringListWithCount("deleted files: ", "the deleted file summary is:", rawIncrRemovedFiles)
            logger.LogLn(delimiter)
        } else {
            logger.LogLn("incremental compile result kind: invalid")
        }
    }

    private func CollectChangedTypeNames(): Unit {
        changedTypes.clear()
        for (pkg in core.GetSourcePackages()) {
            for (file in pkg.files) {
                for (decl in file.decls) {
                    CollectStructNames(pkg, file, decl)
                }
            }
        }
    }

    private func CollectStructNames(pkg: Package, file: File, decl: Decl): Unit {
        let declSummary = EscapeCacheLine(BuildDeclCacheSummary(pkg, file, decl))
        if (decl.astKind == ASTKind.STRUCT_DECL &&
            (kind != IncreKind.INCR || declsToBeReCompiled.contains(declSummary))) {
            changedTypes.add(decl.identifier.Val())
        }
        for (member in decl.members) {
            CollectStructNames(pkg, file, member)
        }
    }

    private func BuildDeclCacheSummary(pkg: Package, file: File, decl: Decl): String {
        let builder = StringBuilder()
        builder.append(pkg.fullPackageName)
        builder.append("|")
        builder.append(file.filePath)
        builder.append("|")
        builder.append(ASTKindName(decl.astKind))
        builder.append("|")
        builder.append(decl.identifier.Val())
        builder.append("|")
        builder.append(decl.begin.line.toString())
        builder.append(":")
        builder.append(decl.begin.column.toString())
        builder.append("-")
        builder.append(decl.end.line.toString())
        builder.append(":")
        builder.append(decl.end.column.toString())
        if (let Some(generic) <- decl.generic) {
            builder.append("|generic:")
            AppendCacheStringList(builder, generic.typeParameters)
        }
        return builder.toString()
    }

    private func SaveIncrementalSignatures(): Bool {
        if (currentCacheText.isEmpty()) {
            currentCacheText = RenderFrontendToolIncrementalCache()
        }
        var ret = true
        let cachePath = GetFrontendToolIncrementalCachePath()
        if (!cachePath.isEmpty()) {
            if (!FileUtil.WriteToFile(cachePath, currentCacheText)) {
                diag.Warn(DiagCategory.IMPORT_PACKAGE, DEFAULT_POSITION,
                    "failed to write FrontendTool incremental cache: " + cachePath)
                ret = false
            }
        }
        for (pkg in core.GetSourcePackages()) {
            if (pkg.IsEmpty()) {
                continue
            }
            ret = SaveCjo(pkg) && ret
        }
        return ret
    }

    private func AnalyseCurrentFrontendCache(): IncreKind {
        currentCacheText = RenderFrontendToolIncrementalCache()
        let cachePath = GetFrontendToolIncrementalCachePath()
        if (cachePath.isEmpty()) {
            LogIncrementalRollback("load cached info failed, roll back to full compilation")
            return IncreKind.ROLLBACK
        }
        if (!FileExist(cachePath)) {
            LogIncrementalRollback("load cached info failed, roll back to full compilation")
            return IncreKind.ROLLBACK
        }
        let readResult = ReadFileContent(cachePath)
        if (!readResult[0]) {
            LogIncrementalRollback("load cached info failed, roll back to full compilation")
            return IncreKind.ROLLBACK
        }
        let previousCache = readResult[1]
        if (GetCacheLineValue(previousCache, "version:") != "1") {
            LogIncrementalRollback("cached FrontendTool incremental cache version changed, roll back to full compilation")
            return IncreKind.ROLLBACK
        }
        if (previousCache == currentCacheText) {
            return IncreKind.NO_CHANGE
        }
        if (GetCacheLineValue(previousCache, "args:") != EscapeCacheLine(core.cachedInfo.compileArgs)) {
            LogIncrementalRollback("compile args changed, roll back to full compilation")
            return IncreKind.ROLLBACK
        }
        let changedFiles = CollectCacheDelta(previousCache, currentCacheText)
        return if (declsToBeReCompiled.isEmpty() && rawIncrRemovedDecls.isEmpty() && !changedFiles) {
            IncreKind.NO_CHANGE
        } else {
            IncreKind.INCR
        }
    }

    private func GetFrontendToolIncrementalCachePath(): String {
        let pkgs = core.GetSourcePackages()
        if (pkgs.isEmpty()) {
            return ""
        }
        return invocation.globalOptions.GenerateCachedPathName(pkgs[0].fullPackageName, ".frontend_tool.incr")
    }

    private func RenderFrontendToolIncrementalCache(): String {
        let builder = StringBuilder()
        builder.append("version:1\n")
        builder.append("args:" + EscapeCacheLine(core.cachedInfo.compileArgs) + "\n")
        for (summary in core.cachedInfo.fileSummaries) {
            builder.append("file:" + EscapeCacheLine(summary) + "\n")
        }
        for (summary in core.cachedInfo.declSummaries) {
            builder.append("decl:" + EscapeCacheLine(summary) + "\n")
        }
        return builder.toString()
    }

    private func CollectCacheDelta(previousCache: String, newCache: String): Bool {
        var filesChanged = false
        let previousFiles = CollectCacheLines(previousCache, "file:")
        let newFiles = CollectCacheLines(newCache, "file:")
        for (oldFile in previousFiles) {
            if (!newFiles.contains(oldFile)) {
                rawIncrRemovedFiles.add(oldFile)
                filesChanged = true
            }
        }
        for (newFile in newFiles) {
            if (!previousFiles.contains(newFile)) {
                filesToBeReCompiled.add(newFile)
                filesChanged = true
            }
        }
        let previousDecls = CollectCacheLines(previousCache, "decl:")
        let newDecls = CollectCacheLines(newCache, "decl:")
        for (oldDecl in previousDecls) {
            if (!newDecls.contains(oldDecl)) {
                rawIncrRemovedDecls.add(oldDecl)
            }
        }
        for (newDecl in newDecls) {
            if (!previousDecls.contains(newDecl)) {
                declsToBeReCompiled.add(newDecl)
            }
        }
        return filesChanged
    }
}

private func LogIncrementalRollback(message: String): Unit {
    let logger = IncrementalCompilationLogger.GetInstance()
    if (logger.IsEnable()) {
        logger.LogLn(message)
    }
}

private func CollectCacheLines(cacheText: String, prefix: String): HashSet<String> {
    let out = HashSet<String>()
    for (line in SplitLines(cacheText)) {
        if (line.startsWith(prefix)) {
            out.add(line[prefix.size..])
        }
    }
    return out
}

private func GetCacheLineValue(cacheText: String, prefix: String): String {
    for (line in SplitLines(cacheText)) {
        if (line.startsWith(prefix)) {
            return line[prefix.size..]
        }
    }
    return ""
}

private func EscapeCacheLine(text: String): String {
    return text.replace("\\", "\\\\").replace("\n", "\\n").replace("\r", "\\r")
}

private func AppendCacheStringList(builder: StringBuilder, values: ArrayList<String>): Unit {
    var idx: Int64 = 0
    while (idx < values.size) {
        if (idx > 0) {
            builder.append(",")
        }
        builder.append(values[idx])
        idx++
    }
}

private func LogStringSetWithCount(title: String, entryPrefix: String, values: HashSet<String>): Unit {
    if (values.isEmpty()) {
        return
    }
    let logger = IncrementalCompilationLogger.GetInstance()
    logger.LogLn(title + values.size.toString())
    for (value in values) {
        logger.LogLn(entryPrefix + value)
    }
}

private func LogStringListWithCount(title: String, entryPrefix: String, values: ArrayList<String>): Unit {
    if (values.isEmpty()) {
        return
    }
    let logger = IncrementalCompilationLogger.GetInstance()
    logger.LogLn(title + values.size.toString())
    for (value in values) {
        logger.LogLn(entryPrefix + value)
    }
}

private func MakeIncrementalDumpDelimiter(): String {
    let builder = StringBuilder()
    var idx: Int64 = 0
    while (idx < 50) {
        builder.append("=")
        idx++
    }
    return builder.toString()
}
