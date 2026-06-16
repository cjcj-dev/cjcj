package cangjie_compiler::frontend_tool

import std.collection.*
import cangjie_compiler::frontend.*
import cangjie_compiler::utils.ProfileRecorder

public enum IncreKind {
    | NO_CHANGE
    | INCR
    | ROLLBACK
    | EMPTY_PKG
    | INVALID
}

private func IncreKindIndex(kind: IncreKind): Int64 {
    return match (kind) {
        case IncreKind.NO_CHANGE => 0
        case IncreKind.INCR => 1
        case IncreKind.ROLLBACK => 2
        case IncreKind.EMPTY_PKG => 3
        case IncreKind.INVALID => 4
    }
}

extend IncreKind <: Equatable<IncreKind> {
    public operator func ==(right: IncreKind): Bool {
        return IncreKindIndex(this) == IncreKindIndex(right)
    }

    public operator func !=(right: IncreKind): Bool {
        return !(this == right)
    }
}

public class CachedMangleMap {
    public let incrRemovedDecls: HashSet<String> = HashSet<String>()
    public let newExternalDecls: HashSet<String> = HashSet<String>()
    public init() {}
}

public class IncrementalCompilerInstance <: DefaultCompilerInstance {
    public let cacheMangles: CachedMangleMap = CachedMangleMap()
    public let changedTypes: HashSet<String> = HashSet<String>()
    public var kind: IncreKind = IncreKind.INVALID
    private let declsToBeReCompiled: HashSet<String> = HashSet<String>()
    private let rawIncrRemovedDecls: ArrayList<String> = ArrayList<String>()
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
        currentCacheText = ""
        let calculated = core.CalculateASTCache()
        if (!calculated || core.GetSourcePackages().isEmpty()) {
            kind = IncreKind.EMPTY_PKG
        } else {
            kind = AnalyseCurrentFrontendCache()
        }
        recorder.close()
        return true
    }

    public override func PerformSema(): Bool {
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
        if (kind == IncreKind.NO_CHANGE || kind == IncreKind.EMPTY_PKG) {
            return true
        }
        if (kind == IncreKind.INCR) {
            return CodegenOnePackage(true)
        }
        return super.PerformCodeGen()
    }

    public override func PerformCjoSaving(): Bool {
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
            SaveIncrementalSignatures()
        }
        return ret
    }

    private func CollectChangedTypeNames(): Unit {
        changedTypes.clear()
        for (pkg in core.GetSourcePackages()) {
            for (file in pkg.files) {
                for (decl in file.decls) {
                    CollectStructNames(decl)
                }
            }
        }
    }

    private func CollectStructNames(decl: Decl): Unit {
        if (decl.astKind == ASTKind.STRUCT_DECL) {
            changedTypes.add(decl.identifier.Val())
        }
        for (member in decl.members) {
            CollectStructNames(member)
        }
    }

    private func SaveIncrementalSignatures(): Unit {
        if (currentCacheText.isEmpty()) {
            currentCacheText = RenderFrontendToolIncrementalCache()
        }
        let cachePath = GetFrontendToolIncrementalCachePath()
        if (!cachePath.isEmpty()) {
            let _ = WriteFileContent(cachePath, currentCacheText)
        }
        for (pkg in core.GetSourcePackages()) {
            if (pkg.IsEmpty()) {
                continue
            }
            let _ = SaveCjo(pkg)
        }
    }

    private func AnalyseCurrentFrontendCache(): IncreKind {
        currentCacheText = RenderFrontendToolIncrementalCache()
        let cachePath = GetFrontendToolIncrementalCachePath()
        if (cachePath.isEmpty() || !FileExist(cachePath)) {
            return IncreKind.ROLLBACK
        }
        let readResult = ReadFileContent(cachePath)
        if (!readResult[0]) {
            return IncreKind.ROLLBACK
        }
        let previousCache = readResult[1]
        if (previousCache == currentCacheText) {
            return IncreKind.NO_CHANGE
        }
        if (GetCacheLineValue(previousCache, "args:") != EscapeCacheLine(core.cachedInfo.compileArgs)) {
            return IncreKind.ROLLBACK
        }
        CollectCacheDelta(previousCache, currentCacheText)
        return if (declsToBeReCompiled.isEmpty() && rawIncrRemovedDecls.isEmpty()) {
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

    private func CollectCacheDelta(previousCache: String, newCache: String): Unit {
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
