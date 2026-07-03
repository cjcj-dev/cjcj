package cangjie_compiler::frontend

import cangjie_compiler::ast.AddCurFile
import cangjie_compiler::ast.TokenKind
import cangjie_compiler::basic.InteropCJPackageConfigReader
import cangjie_compiler::conditional_compilation.ConditionalCompilation
import cangjie_compiler::parse.Parser as RealParser
import cangjie_compiler::basic.GetHash
import cangjie_compiler::utils.FileUtil
import cangjie_compiler::utils.ProfileRecorder
import std.collection.*
import std.sort.*

public enum StrategyType {
    | DEFAULT
    | FULL_COMPILE
    | INCREMENTAL_COMPILE
}

private func StrategyTypeIndex(kind: StrategyType): Int64 {
    return match (kind) {
        case StrategyType.DEFAULT => 0
        case StrategyType.FULL_COMPILE => 1
        case StrategyType.INCREMENTAL_COMPILE => 2
    }
}

extend StrategyType <: Equatable<StrategyType> {
    public operator func ==(rhs: StrategyType): Bool {
        return StrategyTypeIndex(this) == StrategyTypeIndex(rhs)
    }

    public operator func !=(rhs: StrategyType): Bool {
        return !(this == rhs)
    }
}

public open class CompileStrategy {
    protected let ci: CompilerInstance
    public var strategyKind: StrategyType = StrategyType.DEFAULT
    protected let fileIds: HashSet<UInt64> = HashSet<UInt64>()

    public init(ci: CompilerInstance) {
        this.ci = ci
    }

    public open func Parse(): Bool {
        return false
    }

    public func ConditionCompile(): Bool {
        // Faithful port of C++ CompileStrategy::ConditionCompile (Frontend/CompileStrategy.cpp:59-67):
        // run the conditional-compilation pass over each source package; succeed iff it added no errors.
        let basicDiag = ci.diag.AsBasicDiagnosticEngine()
        let beforeErrCnt = basicDiag.GetErrorCount()
        let cc = ConditionalCompilation(ci.invocation.globalOptions, basicDiag)
        for (pkg in ci.srcPkgs) {
            cc.HandleConditionalCompilation(pkg)
        }
        return beforeErrCnt == basicDiag.GetErrorCount()
    }

    public func DesugarAfterSema(): Unit {
        ()
    }

    public func InteropConfigTomlCheck(): Unit {
        try (recorder = ProfileRecorder("Semantic", "InteropConfigTomlCheck")) {
            let packagesFullConfig = InteropCJPackageConfigReader()
            if (ci.invocation.globalOptions.enableInteropCJMapping &&
                ci.invocation.globalOptions.interopCJPackageConfigPath != "./" &&
                !packagesFullConfig.Parse(ci.invocation.globalOptions.interopCJPackageConfigPath)) {
                ci.diag.DiagnoseRefactor(DiagKindRefactor.sema_cj_mapping_generic_method_not_get_instance_config,
                    DEFAULT_POSITION, arguments: [ci.invocation.globalOptions.interopCJPackageConfigPath])
            }
        }
    }

    public func ImportPackages(): Bool {
        return ci.ImportPackages()
    }

    public func MacroExpand(): Bool {
        return true
    }

    public open func Sema(): Bool {
        return true
    }

    public func OverflowStrategy(): Bool {
        return true
    }
}

public class FullCompileStrategy <: CompileStrategy {
    private var impl: Option<FullCompileStrategyImpl> = None

    public init(ci: CompilerInstance) {
        super(ci)
        impl = Some(FullCompileStrategyImpl(this))
        strategyKind = StrategyType.FULL_COMPILE
    }

    public override func Parse(): Bool {
        var ret = true
        let strategyImpl = impl.getOrThrow()
        if (ci.loadSrcFilesFromCache || ci.compileOnePackageFromSrcFiles) {
            let incrParse = ci.loadSrcFilesFromCache && !ci.srcPkgs.isEmpty() && !ci.HasTypeChecker()
            if (incrParse) {
                strategyImpl.ParseOnePackageInPlace(ci.srcPkgs[0])
            } else {
                let parsed = strategyImpl.ParseOnePackage(ci.srcFilePaths, DEFAULT_PACKAGE_NAME)
                ci.srcPkgs.add(parsed[0])
                ret = parsed[1]
            }
        } else {
            ret = strategyImpl.ParseModule()
        }
        ci.RefreshASTContexts()
        ci.diag.EmitCategoryGroup()
        return ret
    }

    public override func Sema(): Bool {
        return true
    }
}

private class FullCompileStrategyImpl {
    private let s: FullCompileStrategy

    init(strategy: FullCompileStrategy) {
        s = strategy
    }

    public func ParseModule(): Bool {
        var success = true
        let moduleSrcPath = s.ci.invocation.globalOptions.moduleSrcPath
        let includeFileSet = HashSet<String>()
        for (srcPath in s.ci.invocation.globalOptions.srcFiles) {
            includeFileSet.add(srcPath)
        }
        for (srcDir in s.ci.srcDirs) {
            let allSrcFiles = ArrayList<String>()
            var currentPkg = DEFAULT_PACKAGE_NAME
            if (!moduleSrcPath.isEmpty()) {
                let basePath = if (IsDir(moduleSrcPath)) { JoinPath(moduleSrcPath, "") } else { moduleSrcPath }
                currentPkg = FileUtil.GetPkgNameFromRelativePath(FileUtil.GetRelativePath(basePath, srcDir) ?? "")
            }
            let parseTest = s.ci.invocation.globalOptions.parseTest
            let compileTestsOnly = s.ci.invocation.globalOptions.compileTestsOnly
            let files = GetAllFilesUnderCurrentPath(srcDir, "cj", shouldSkipTestFiles: !parseTest,
                shouldSkipRegularFiles: compileTestsOnly)
            for (srcFile in files) {
                let filename = JoinPath(srcDir, srcFile)
                if (includeFileSet.isEmpty() || includeFileSet.contains(filename)) {
                    allSrcFiles.add(filename)
                }
            }
            let parsed = ParseOnePackage(allSrcFiles, currentPkg)
            let parsedPkg = parsed[0]
            success = success && parsed[1]
            if (srcDir == moduleSrcPath) {
                parsedPkg.needExported = false
            }
            s.ci.srcPkgs.add(parsedPkg)
        }
        for (pkg in s.ci.srcPkgs) {
            sort(pkg.files, by: { left: File, right: File => compareString(left.fileName, right.fileName) })
        }
        return success
    }

    public func ParseOnePackage(files: ArrayList<String>, defaultPackageName: String): (Package, Bool) {
        var success = true
        let fileInfos = ArrayList<(String, UInt64, String)>()
        if (s.ci.loadSrcFilesFromCache) {
            for ((path, cacheInfo) in s.ci.bufferCache) {
                if (cacheInfo.state == SrcCodeChangeState.DELETED) {
                    continue
                }
                let fileID = addSourceForParse(path, cacheInfo.code)
                fileInfos.add((path, fileID, cacheInfo.code))
            }
        } else {
            let parseFiles = ArrayList<String>()
            for (file in files) {
                parseFiles.add(file)
            }
            sort(parseFiles, by: { left: String, right: String => compareString(GetFileName(left), GetFileName(right)) })
            for (filePath in parseFiles) {
                let readResult = ReadFileContent(filePath)
                if (!readResult[0]) {
                    s.ci.diag.DiagnoseRefactor(DiagKindRefactor.module_read_file_to_buffer_failed,
                        DEFAULT_POSITION, arguments: [filePath, readResult[2]])
                    success = false
                    continue
                }
                let fileID = addSourceForParse(filePath, readResult[1])
                fileInfos.add((filePath, fileID, readResult[1]))
            }
        }
        let pkg = Package(defaultPackageName)
        for (info in fileInfos) {
            if (!parseRealSourceIntoPackage(pkg, info[0], info[1], info[2])) {
                success = false
            }
        }
        CheckPackageConsistency(pkg)
        AddCurFile(pkg)
        return (pkg, success)
    }

    public func ParseOnePackageInPlace(pkg: Package): Unit {
        let fileInfos = ArrayList<(String, UInt64, String)>()
        let deletedFiles = ArrayList<String>()
        for ((path, cacheInfo) in s.ci.bufferCache) {
            if (cacheInfo.state == SrcCodeChangeState.UNCHANGED) {
                continue
            }
            if (cacheInfo.state == SrcCodeChangeState.DELETED) {
                deleteFileInPackage(pkg, path)
                deletedFiles.add(path)
            } else {
                if (cacheInfo.state == SrcCodeChangeState.CHANGED) {
                    deleteFileInPackage(pkg, path)
                }
                let fileID = addSourceForParse(path, cacheInfo.code)
                fileInfos.add((path, fileID, cacheInfo.code))
            }
        }
        for (path in deletedFiles) {
            s.ci.bufferCache.remove(path)
        }
        var changed = false
        for (info in fileInfos) {
            changed = true
            let _ = parseRealSourceIntoPackage(pkg, info[0], info[1], info[2])
        }
        if (changed) {
            sort(pkg.files, by: { left: File, right: File => compareString(left.fileName, right.fileName) })
            CheckPackageConsistency(pkg)
            AddCurFile(pkg)
            s.ci.diag.EmitCategoryGroup()
        }
    }

    public func CheckPackageConsistency(pkg: Package): Unit {
        if (pkg.files.isEmpty()) {
            return
        }
        if (let Some(packageSpec) <- pkg.files[0].packageSpec) {
            for (file in pkg.files) {
                if (let Some(filePackageSpec) <- file.packageSpec) {
                    if (filePackageSpec.hasMacro != packageSpec.hasMacro) {
                        s.ci.diag.DiagnoseRefactor(DiagKindRefactor.package_name_inconsistent_with_macro,
                            filePackageSpec.begin)
                        return
                    }
                }
            }
            pkg.isMacroPackage = packageSpec.hasMacro
        }
    }

    private func parseRealSourceIntoPackage(pkg: Package, filePath: String, fileID: UInt64, sourceCode: String): Bool {
        let parseDiag = s.ci.diag.AsBasicDiagnosticEngine()
        let errorCountBefore = s.ci.diag.GetErrorCount()
        let parser = RealParser(fileID, sourceCode, parseDiag, s.ci.GetSourceManager())
        let realFile = parser.ParseTopLevel()
        realFile.filePath = NormalizePath(filePath)
        realFile.fileName = GetFileName(realFile.filePath)
        realFile.fileHash = GetHash(realFile.filePath)
        realFile.begin = Position(fileID, 1, 1)
        realFile.end = s.ci.GetSourceManager().GetSource(fileID).GetEndPos()
        realFile.curPackage = Some(pkg)
        realFile.indexOfPackage = UInt64(pkg.files.size)
        pkg.files.add(realFile)
        if (pkg.files.size == 1) {
            initializePackageInfoFromFirstFile(pkg)
        }
        return s.ci.diag.GetErrorCount() == errorCountBefore
    }

    private func initializePackageInfoFromFirstFile(pkg: Package): Unit {
        if (pkg.files.isEmpty()) {
            return
        }
        if (let Some(packageSpec) <- pkg.files[0].packageSpec) {
            pkg.fullPackageName = packageSpec.GetPackageName()
            if (let Some(modifier) <- packageSpec.modifier) {
                if (modifier.modifier == TokenKind.PROTECTED) {
                    pkg.accessible = AccessLevel.PROTECTED
                } else if (modifier.modifier == TokenKind.INTERNAL) {
                    pkg.accessible = AccessLevel.INTERNAL
                } else {
                    pkg.accessible = AccessLevel.PUBLIC
                }
            } else {
                pkg.accessible = AccessLevel.PUBLIC
            }
        }
    }

    private func addSourceForParse(path: String, code: String): UInt64 {
        let isCjmpFile = s.ci.invocation.globalOptions.IsCompilingCJMP()
        let fileID = s.ci.GetSourceManager().AddSource(path, code, isCjmpFile: isCjmpFile)
        if (s.fileIds.contains(fileID)) {
            s.ci.diag.Diagnose(DiagCategory.IMPORT_PACKAGE, DEFAULT_POSITION,
                "source file id conflict for " + path)
        }
        s.fileIds.add(fileID)
        return fileID
    }

    private func deleteFileInPackage(pkg: Package, filePath: String): Unit {
        var idx: Int64 = 0
        while (idx < pkg.files.size) {
            if (pkg.files[idx].filePath == filePath) {
                pkg.files.remove(at: idx)
            } else {
                idx++
            }
        }
    }
}

private func compareString(left: String, right: String): Ordering {
    if (left < right) {
        return Ordering.LT
    }
    if (left > right) {
        return Ordering.GT
    }
    return Ordering.EQ
}
