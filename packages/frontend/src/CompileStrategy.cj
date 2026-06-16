package cangjie_compiler::frontend

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
        let beforeErrCnt = ci.diag.GetErrorCount()
        for (pkg in ci.srcPkgs) {
            handleConditionalDirectives(pkg)
        }
        return beforeErrCnt == ci.diag.GetErrorCount()
    }

    public func DesugarAfterSema(): Unit {
        for (pkg in ci.GetSourcePackages()) {
            for (file in pkg.files) {
                for (decl in file.decls) {
                    finalizeDeclAfterSema(pkg, decl)
                }
            }
        }
        ci.RefreshASTContexts()
    }

    public func ImportPackages(): Bool {
        let ret = ci.ImportPackages()
        ParseAndMergeCjds()
        return ret
    }

    public func MacroExpand(): Bool {
        let beforeErrCnt = ci.diag.GetErrorCount()
        for (pkg in ci.srcPkgs) {
            expandMacrosInPackage(pkg)
        }
        ci.RefreshASTContexts()
        ci.diag.EmitCategoryDiagnostics(DiagCategory.PARSE)
        return beforeErrCnt == ci.diag.GetErrorCount()
    }

    public open func Sema(): Bool {
        return false
    }

    public func OverflowStrategy(): Bool {
        let strategyName = FrontendOverflowStrategyName(ci.invocation.globalOptions.overflowStrategy)
        for (pkg in ci.GetSourcePackages()) {
            for (file in pkg.files) {
                for (decl in file.decls) {
                    markDeclTree(decl, "OVERFLOW_" + strategyName)
                }
            }
        }
        return true
    }

    protected func PerformDesugar(): Unit {
        let compatibleSDKVersion = ci.invocation.globalOptions.passedWhenKeyValue.get("APILevel_level") ?? ""
        for (pkg in ci.GetSourcePackages()) {
            for (file in pkg.files) {
                for (decl in file.decls) {
                    normalizeDeclBeforeTypeCheck(pkg, decl, compatibleSDKVersion)
                }
            }
        }
    }

    protected func TypeCheck(): Unit {
        for (pkg in ci.GetSourcePackages()) {
            checkPackageSemantics(pkg)
        }
        ci.RefreshASTContexts()
    }

    protected func InteropConfigTomlCheck(): Unit {
        let opts = ci.invocation.globalOptions
        if (opts.enableInteropCJMapping && opts.interopCJPackageConfigPath != "./" && !FileExist(opts.interopCJPackageConfigPath)) {
            ci.diag.Diagnose(DiagCategory.SEMA, DEFAULT_POSITION,
                "interop Cangjie package config not found: " + opts.interopCJPackageConfigPath)
        }
    }

    private func ParseAndMergeCjds(): Unit {
        let option = ci.invocation.globalOptions
        let hasLevel = option.passedWhenKeyValue.contains("APILevel_level")
        let hasSyscap = option.passedWhenKeyValue.contains("APILevel_syscap")
        if (!hasLevel && !hasSyscap) {
            return
        }
        option.compileCjd = true
        for ((pkgName, cjdPath) in ci.importManager.GetDepPkgCjdPaths()) {
            let readResult = ReadFileContent(cjdPath)
            if (!readResult[0]) {
                continue
            }
            let fileID = ci.GetSourceManager().AddSource(cjdPath, readResult[1], packageName: Some(pkgName),
                isCjmpFile: option.IsCompilingCJMP())
            let parsedFile = ParseSourceFile(fileID, cjdPath, readResult[1], ci.diag, ci.GetSourceManager(),
                option.enableAddCommentToAst, option.compileCjd)
            let sourcePkg = Package(pkgName)
            sourcePkg.AddFile(parsedFile)
            if (let Some(targetPkg) <- ci.importManager.GetPackage(pkgName)) {
                MergeCusAnno(targetPkg, sourcePkg)
            }
        }
        ci.diag.EmitCategoryGroup()
        option.compileCjd = false
    }

    private func handleConditionalDirectives(pkg: Package): Unit {
        let opts = ci.invocation.globalOptions
        for (file in pkg.files) {
            let source = ci.GetSourceManager().GetSource(file.begin.fileID)
            if (source.buffer.isEmpty()) {
                continue
            }
            let activeLines = computeActiveConditionalLines(source.buffer, opts)
            if (activeLines.isEmpty()) {
                continue
            }
            var idx: Int64 = 0
            while (idx < file.decls.size) {
                let decl = file.decls[idx]
                if (decl.begin.line > 0 && activeLines.contains(decl.begin.line) && !activeLines.get(decl.begin.line).getOrThrow()) {
                    file.decls.remove(at: idx)
                } else {
                    idx++
                }
            }
        }
        ci.RefreshASTContexts()
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
                let pkg = strategyImpl.ParseOnePackage(ci.srcFilePaths, ret, DEFAULT_PACKAGE_NAME)
                ci.srcPkgs.add(pkg)
            }
        } else {
            strategyImpl.ParseModule(ret)
        }
        return ret
    }

    public override func Sema(): Bool {
        PerformDesugar()
        InteropConfigTomlCheck()
        TypeCheck()
        return ci.diag.GetErrorCount() == 0
    }
}

private class FullCompileStrategyImpl {
    private let s: FullCompileStrategy

    init(strategy: FullCompileStrategy) {
        s = strategy
    }

    public func ParseModule(success: Bool): Unit {
        var mutableSuccess = success
        let moduleSrcPath = s.ci.invocation.globalOptions.moduleSrcPath
        let includeFileSet = HashSet<String>()
        for (srcPath in s.ci.invocation.globalOptions.srcFiles) {
            includeFileSet.add(NormalizePath(srcPath))
        }
        for (srcDir in s.ci.srcDirs) {
            let allSrcFiles = ArrayList<String>()
            var currentPkg = DEFAULT_PACKAGE_NAME
            if (!moduleSrcPath.isEmpty()) {
                let basePath = if (IsDir(moduleSrcPath)) { JoinPath(moduleSrcPath, "") } else { moduleSrcPath }
                currentPkg = GetPkgNameFromRelativePath(GetRelativePath(basePath, srcDir))
            }
            let parseTest = s.ci.invocation.globalOptions.parseTest
            let compileTestsOnly = s.ci.invocation.globalOptions.compileTestsOnly
            let files = GetAllFilesUnderCurrentPath(srcDir, "cj", shouldSkipTestFiles: !parseTest,
                shouldSkipRegularFiles: compileTestsOnly)
            for (srcFile in files) {
                let filename = JoinPath(srcDir, srcFile)
                if (includeFileSet.isEmpty() || includeFileSet.contains(NormalizePath(filename))) {
                    allSrcFiles.add(filename)
                }
            }
            let parsedPkg = ParseOnePackage(allSrcFiles, mutableSuccess, currentPkg)
            if (srcDir == moduleSrcPath) {
                parsedPkg.needExported = false
            }
            s.ci.srcPkgs.add(parsedPkg)
        }
        for (pkg in s.ci.srcPkgs) {
            sort(pkg.files, by: { left: File, right: File => compareString(left.fileName, right.fileName) })
        }
    }

    public func ParseOnePackage(files: ArrayList<String>, success: Bool, defaultPackageName: String): Package {
        var mutableSuccess = success
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
                    s.ci.diag.Diagnose(DiagCategory.IMPORT_PACKAGE, DEFAULT_POSITION,
                        "failed to read source file '" + filePath + "': " + readResult[2])
                    mutableSuccess = false
                    continue
                }
                let fileID = addSourceForParse(filePath, readResult[1])
                fileInfos.add((filePath, fileID, readResult[1]))
            }
        }
        let pkg = Package(defaultPackageName)
        addParsedFilesToPackage(pkg, fileInfos)
        CheckPackageConsistency(pkg)
        if (!mutableSuccess) {
            pkg.SetAttr("PARSE_FAILED")
        }
        return pkg
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
        if (!fileInfos.isEmpty()) {
            addParsedFilesToPackage(pkg, fileInfos)
            sort(pkg.files, by: { left: File, right: File => compareString(left.fileName, right.fileName) })
            CheckPackageConsistency(pkg)
            s.ci.diag.EmitCategoryGroup()
        }
    }

    public func CheckPackageConsistency(pkg: Package): Unit {
        if (pkg.files.isEmpty()) {
            return
        }
        if (let Some(packageSpec) <- pkg.files[0].packageSpec) {
            pkg.isMacroPackage = packageSpec.hasMacro
            pkg.fullPackageName = packageSpec.GetPackageName()
            for (file in pkg.files) {
                if (let Some(filePackageSpec) <- file.packageSpec) {
                    if (filePackageSpec.hasMacro != pkg.isMacroPackage) {
                        s.ci.diag.Diagnose(DiagCategory.PARSE, filePackageSpec.begin,
                            "package name inconsistent with macro package marker")
                        return
                    }
                }
            }
        }
    }

    private func addParsedFilesToPackage(pkg: Package, fileInfos: ArrayList<(String, UInt64, String)>): Unit {
        for (info in fileInfos) {
            let fileAst = ParseSourceFile(info[1], info[0], info[2], s.ci.diag, s.ci.GetSourceManager(),
                s.ci.invocation.globalOptions.enableAddCommentToAst, s.ci.invocation.globalOptions.compileCjd)
            pkg.AddFile(fileAst)
            if (pkg.files.size == 1) {
                InitializePackageInfoFromFirstFile(pkg)
            }
        }
        InitializePackageInfoFromFirstFile(pkg)
    }

    private func InitializePackageInfoFromFirstFile(pkg: Package): Unit {
        if (pkg.files.isEmpty()) {
            return
        }
        if (let Some(packageSpec) <- pkg.files[0].packageSpec) {
            pkg.fullPackageName = packageSpec.GetPackageName()
            if (let Some(modifier) <- packageSpec.modifier) {
                if (modifier.name == "protected") {
                    pkg.accessible = AccessLevel.PROTECTED
                } else if (modifier.name == "internal") {
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

public func ParseSourceFile(fileID: UInt64, filePath: String, sourceCode: String, diag: DiagnosticEngine,
    sm: SourceManager, attachComment: Bool, parseDeclFile: Bool): File {
    let _ = diag
    let _ = attachComment
    let _ = parseDeclFile
    let file = File()
    file.filePath = NormalizePath(filePath)
    file.fileName = GetFileName(file.filePath)
    file.fileHash = UInt64(file.filePath.hashCode())
    file.begin = Position(fileID, 1, 1)
    file.end = sm.GetSource(fileID).GetEndPos()
    let tokens = Tokenize(fileID, sourceCode)
    parsePackageAndImports(file, tokens)
    parseTopLevelDecls(file, tokens)
    return file
}

private func parsePackageAndImports(file: File, tokens: ArrayList<FrontendToken>): Unit {
    var idx: Int64 = 0
    while (idx < tokens.size) {
        let tok = tokens[idx]
        if (tok.kind == FrontendTokenKind.NL || tok.kind == FrontendTokenKind.COMMENT) {
            idx++
            continue
        }
        if (tok.value == "macro" && idx + 1 < tokens.size && tokens[idx + 1].value == "package") {
            let spec = PackageSpec()
            spec.hasMacro = true
            spec.macroPos = tok.Begin()
            spec.packagePos = tokens[idx + 1].Begin()
            let parsed = parseQualifiedName(tokens, idx + 2)
            spec.packageName = SrcIdentifier(parsed[0], begin: tokens[idx + 1].Begin(), end: tokens[idx + 1].End())
            spec.begin = tok.Begin()
            spec.end = parsed[1]
            file.packageSpec = Some(spec)
            idx = parsed[2]
            continue
        }
        if (tok.value == "package") {
            let spec = PackageSpec()
            spec.packagePos = tok.Begin()
            let parsed = parseQualifiedName(tokens, idx + 1)
            spec.packageName = SrcIdentifier(parsed[0], begin: tok.Begin(), end: parsed[1])
            spec.begin = tok.Begin()
            spec.end = parsed[1]
            file.packageSpec = Some(spec)
            idx = parsed[2]
            continue
        }
        if (tok.value == "import") {
            let importSpec = ImportSpec()
            importSpec.importPos = tok.Begin()
            let parsed = parseImportContent(tokens, idx + 1)
            importSpec.content = parsed[0]
            importSpec.begin = tok.Begin()
            importSpec.end = parsed[1]
            file.imports.add(importSpec)
            idx = parsed[2]
            continue
        }
        if (isDeclKeyword(tok.value)) {
            return
        }
        idx++
    }
}

private func parseTopLevelDecls(file: File, tokens: ArrayList<FrontendToken>): Unit {
    var idx: Int64 = 0
    while (idx < tokens.size) {
        let tok = tokens[idx]
        if (!isDeclKeyword(tok.value)) {
            idx++
            continue
        }
        let declInfo = createDeclFromKeyword(tokens, idx)
        if (let Some(decl) <- declInfo[0]) {
            decl.begin = tok.Begin()
            decl.end = declInfo[1]
            file.decls.add(decl)
        }
        idx = declInfo[2]
    }
}

private func createDeclFromKeyword(tokens: ArrayList<FrontendToken>, start: Int64): (Option<Decl>, Position, Int64) {
    let keyword = tokens[start].value
    var nameIdx = start + 1
    if (keyword == "public" || keyword == "protected" || keyword == "internal" || keyword == "private" ||
        keyword == "static" || keyword == "abstract" || keyword == "open" || keyword == "sealed") {
        if (nameIdx >= tokens.size) {
            return (None, tokens[start].End(), start + 1)
        }
        return createDeclFromKeyword(tokens, nameIdx)
    }
    var decl: Decl
    if (keyword == "func") {
        decl = FuncDecl()
    } else if (keyword == "main") {
        decl = MainDecl()
    } else if (keyword == "macro") {
        if (nameIdx < tokens.size && tokens[nameIdx].value == "package") {
            return (None, tokens[start].End(), start + 1)
        }
        decl = MacroDecl()
    } else if (keyword == "var" || keyword == "let" || keyword == "const") {
        decl = VarDecl()
    } else if (keyword == "class") {
        decl = ClassDecl()
    } else if (keyword == "interface") {
        decl = InterfaceDecl()
    } else if (keyword == "struct") {
        decl = StructDecl()
    } else if (keyword == "enum") {
        decl = EnumDecl()
    } else if (keyword == "extend") {
        decl = ExtendDecl()
    } else if (keyword == "type") {
        decl = TypeAliasDecl()
    } else if (keyword == "prop") {
        decl = PropDecl()
    } else if (keyword == "init") {
        decl = PrimaryCtorDecl()
    } else {
        return (None, tokens[start].End(), start + 1)
    }
    while (nameIdx < tokens.size && (tokens[nameIdx].kind == FrontendTokenKind.NL ||
        tokens[nameIdx].kind == FrontendTokenKind.COMMENT)) {
        nameIdx++
    }
    if (keyword == "extend") {
        let parsed = parseQualifiedName(tokens, nameIdx)
        decl.identifier = SrcIdentifier(parsed[0], begin: tokens[start].Begin(), end: parsed[1])
        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            extendDecl.extendedType = Some(RefType(parsed[0]))
        }
        return (Some(decl), parsed[1], parsed[2])
    }
    if (nameIdx < tokens.size && (tokens[nameIdx].kind == FrontendTokenKind.IDENTIFIER ||
        tokens[nameIdx].kind == FrontendTokenKind.KEYWORD || tokens[nameIdx].kind == FrontendTokenKind.OPERATOR)) {
        decl.identifier = SrcIdentifier(tokens[nameIdx].value, begin: tokens[nameIdx].Begin(), end: tokens[nameIdx].End())
        return (Some(decl), tokens[nameIdx].End(), nameIdx + 1)
    }
    if (keyword == "init") {
        decl.identifier = SrcIdentifier("init", begin: tokens[start].Begin(), end: tokens[start].End())
        return (Some(decl), tokens[start].End(), start + 1)
    }
    return (None, tokens[start].End(), start + 1)
}

private func parseQualifiedName(tokens: ArrayList<FrontendToken>, start: Int64): (String, Position, Int64) {
    let builder = StringBuilder()
    var idx = start
    var endPos = if (idx < tokens.size) { tokens[idx].End() } else { INVALID_POSITION }
    var expectName = true
    while (idx < tokens.size) {
        let tok = tokens[idx]
        if (expectName && (tok.kind == FrontendTokenKind.IDENTIFIER || tok.kind == FrontendTokenKind.KEYWORD)) {
            if (builder.size > 0) {
                builder.append(".")
            }
            builder.append(tok.value)
            endPos = tok.End()
            expectName = false
            idx++
        } else if (!expectName && tok.value == ".") {
            expectName = true
            idx++
        } else {
            break
        }
    }
    return (builder.toString(), endPos, idx)
}

private func parseImportContent(tokens: ArrayList<FrontendToken>, start: Int64): (ImportContent, Position, Int64) {
    let content = ImportContent()
    let parsed = parseQualifiedName(tokens, start)
    let name = parsed[0]
    let parts = splitByDot(name)
    var idx: Int64 = 0
    while (idx < parts.size) {
        if (idx + 1 == parts.size) {
            content.identifier = SrcIdentifier(parts[idx])
        } else {
            content.prefixPaths.add(parts[idx])
        }
        idx++
    }
    var endPos = parsed[1]
    var nextIdx = parsed[2]
    if (nextIdx + 1 < tokens.size && tokens[nextIdx].value == "as") {
        content.asPos = tokens[nextIdx].Begin()
        content.aliasName = SrcIdentifier(tokens[nextIdx + 1].value, begin: tokens[nextIdx + 1].Begin(),
            end: tokens[nextIdx + 1].End())
        endPos = tokens[nextIdx + 1].End()
        nextIdx += 2
    }
    content.begin = if (start < tokens.size) { tokens[start].Begin() } else { INVALID_POSITION }
    return (content, endPos, nextIdx)
}

private func isDeclKeyword(value: String): Bool {
    return value == "func" || value == "main" || value == "macro" || value == "var" ||
        value == "let" || value == "const" || value == "class" || value == "interface" ||
        value == "struct" || value == "enum" || value == "extend" || value == "type" ||
        value == "prop" || value == "init" || value == "public" || value == "protected" ||
        value == "internal" || value == "private" || value == "static" || value == "abstract" ||
        value == "open" || value == "sealed"
}

private func splitByDot(value: String): ArrayList<String> {
    let out = ArrayList<String>()
    var start: Int64 = 0
    var idx: Int64 = 0
    while (idx < value.size) {
        if (value[idx] == b'.') {
            out.add(value[start..idx])
            start = idx + 1
        }
        idx++
    }
    if (start <= value.size) {
        out.add(value[start..])
    }
    return out
}

private func GetRelativePath(base: String, path: String): String {
    let normalizedBase = NormalizePath(base)
    let normalizedPath = NormalizePath(path)
    if (normalizedPath.startsWith(normalizedBase)) {
        var rest = normalizedPath[normalizedBase.size..]
        if (!rest.isEmpty() && rest[0] == b'/') {
            rest = rest[1..]
        }
        return rest
    }
    return normalizedPath
}

private func GetPkgNameFromRelativePath(path: String): String {
    let normalized = NormalizePath(path)
    if (normalized.isEmpty() || normalized == ".") {
        return DEFAULT_PACKAGE_NAME
    }
    return normalized.replace("/", ".")
}

private func expandMacrosInPackage(pkg: Package): Unit {
    for (file in pkg.files) {
        let expandedDecls = ArrayList<Decl>()
        for (decl in file.decls) {
            if (let Some(macroDecl) <- (decl as MacroExpandDecl)) {
                if (let Some(expanded) <- macroDecl.invocation.decl) {
                    if (macroDecl.invocation.identifier == "APILevel") {
                        ensureAPILevelAnnotation(expanded, macroDecl.invocation)
                    }
                    expanded.fullPackageName = pkg.fullPackageName
                    expandedDecls.add(expanded)
                } else {
                    expandedDecls.add(decl)
                }
            } else {
                expandedDecls.add(decl)
            }
        }
        file.decls.clear()
        for (decl in expandedDecls) {
            file.decls.add(decl)
        }
    }
}

private func ensureAPILevelAnnotation(decl: Decl, invocation: MacroInvocation): Unit {
    for (anno in decl.annotations) {
        if (anno.identifier.Val() == "APILevel") {
            return
        }
    }
    let anno = Annotation()
    anno.identifier = SrcIdentifier("APILevel")
    anno.kind = AnnotationKind.CUSTOM
    var lastIdentifier = ""
    for (attr in invocation.attrs) {
        if (attr.kind == FrontendTokenKind.IDENTIFIER) {
            lastIdentifier = attr.value
        } else if (attr.kind == FrontendTokenKind.STRING_LITERAL || attr.kind == FrontendTokenKind.INTEGER_LITERAL ||
            attr.kind == FrontendTokenKind.BOOL_LITERAL) {
            if (lastIdentifier.isEmpty()) {
                anno.args.add(attr.value)
            } else {
                anno.args.add(lastIdentifier + ":" + attr.value)
            }
        }
    }
    decl.annotations.add(anno)
}

private func normalizeDeclBeforeTypeCheck(pkg: Package, decl: Decl, compatibleSDKVersion: String): Unit {
    decl.fullPackageName = pkg.fullPackageName
    decl.toBeCompiled = true
    if (!compatibleSDKVersion.isEmpty()) {
        decl.SetAttr("APILevel_" + compatibleSDKVersion)
    }
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        if (let Some(generic) <- funcDecl.funcBody.generic) {
            decl.generic = Some(generic)
        }
    }
    for (member in decl.members) {
        normalizeDeclBeforeTypeCheck(pkg, member, compatibleSDKVersion)
    }
}

private func finalizeDeclAfterSema(pkg: Package, decl: Decl): Unit {
    decl.fullPackageName = pkg.fullPackageName
    if (decl.mangledName.isEmpty()) {
        decl.mangledName = "_C" + (pkg.fullPackageName + "." + decl.identifier.Val()).replace(".", "_")
    }
    for (member in decl.members) {
        finalizeDeclAfterSema(pkg, member)
    }
}

private func markDeclTree(decl: Decl, attr: String): Unit {
    decl.SetAttr(attr)
    for (member in decl.members) {
        markDeclTree(member, attr)
    }
}

private func checkPackageSemantics(pkg: Package): Unit {
    let seenTopLevel = HashSet<String>()
    var mainCount: Int64 = 0
    for (file in pkg.files) {
        if (let Some(packageSpec) <- file.packageSpec) {
            if (packageSpec.GetPackageName() != pkg.fullPackageName) {
                packageSpec.SetAttr("PACKAGE_NAME_MISMATCH")
            }
        }
        for (decl in file.decls) {
            let key = ASTKindName(decl.astKind) + ":" + decl.identifier.Val()
            if (seenTopLevel.contains(key)) {
                decl.SetAttr("DUPLICATED_TOP_LEVEL_DECL")
            } else {
                seenTopLevel.add(key)
            }
            if (decl.astKind == ASTKind.MAIN_DECL) {
                mainCount++
            }
            validateDeclShape(pkg, file, decl)
        }
    }
    if (mainCount > 1) {
        pkg.SetAttr("MULTIPLE_MAIN")
    }
}

private func validateDeclShape(pkg: Package, file: File, decl: Decl): Unit {
    let _ = file
    decl.fullPackageName = pkg.fullPackageName
    if (decl.identifier.Empty() && decl.astKind != ASTKind.EXTEND_DECL) {
        decl.SetAttr("INVALID_IDENTIFIER")
    }
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        let seenParams = HashSet<String>()
        for (param in funcDecl.funcBody.params) {
            let name = param.identifier.Val()
            if (!name.isEmpty()) {
                if (seenParams.contains(name)) {
                    param.SetAttr("DUPLICATED_PARAM")
                } else {
                    seenParams.add(name)
                }
            }
        }
    }
    for (member in decl.members) {
        validateDeclShape(pkg, file, member)
    }
}

private func computeActiveConditionalLines(source: String, opts: GlobalOptions): HashMap<Int64, Bool> {
    let activeLines = HashMap<Int64, Bool>()
    let parentStack = ArrayList<Bool>()
    let takenStack = ArrayList<Bool>()
    var active = true
    let lines = SplitLines(source)
    var idx: Int64 = 0
    while (idx < lines.size) {
        let lineNo = idx + 1
        let line = trimAscii(lines[idx])
        if (line.startsWith("#if")) {
            parentStack.add(active)
            let condition = trimAscii(line[3..])
            let condValue = evalConditionalExpr(condition, opts)
            takenStack.add(condValue)
            active = active && condValue
            putBool(activeLines, lineNo, false)
        } else if (line.startsWith("#else")) {
            if (!parentStack.isEmpty() && !takenStack.isEmpty()) {
                let parentActive = parentStack[parentStack.size - 1]
                let alreadyTaken = takenStack[takenStack.size - 1]
                active = parentActive && !alreadyTaken
                takenStack[takenStack.size - 1] = true
            }
            putBool(activeLines, lineNo, false)
        } else if (line.startsWith("#endif")) {
            if (!parentStack.isEmpty()) {
                active = parentStack[parentStack.size - 1]
                parentStack.remove(at: parentStack.size - 1)
            }
            if (!takenStack.isEmpty()) {
                takenStack.remove(at: takenStack.size - 1)
            }
            putBool(activeLines, lineNo, false)
        } else {
            putBool(activeLines, lineNo, active)
        }
        idx++
    }
    return activeLines
}

private func evalConditionalExpr(condition: String, opts: GlobalOptions): Bool {
    let expr = trimAscii(condition)
    if (expr.isEmpty()) {
        return false
    }
    if (let Some(pos) <- expr.indexOf("||")) {
        return evalConditionalExpr(expr[0..pos], opts) || evalConditionalExpr(expr[pos + 2..], opts)
    }
    if (let Some(pos) <- expr.indexOf("&&")) {
        return evalConditionalExpr(expr[0..pos], opts) && evalConditionalExpr(expr[pos + 2..], opts)
    }
    if (expr.startsWith("!")) {
        return !evalConditionalExpr(expr[1..], opts)
    }
    if (expr == "true") {
        return true
    }
    if (expr == "false") {
        return false
    }
    if (let Some(pos) <- expr.indexOf("==")) {
        let key = trimAscii(expr[0..pos])
        let value = stripQuotes(trimAscii(expr[pos + 2..]))
        return (opts.passedWhenKeyValue.get(key) ?? "") == value
    }
    if (let Some(pos) <- expr.indexOf("=")) {
        let key = trimAscii(expr[0..pos])
        let value = stripQuotes(trimAscii(expr[pos + 1..]))
        return (opts.passedWhenKeyValue.get(key) ?? "") == value
    }
    return opts.passedWhenKeyValue.contains(expr)
}

private func putBool(map: HashMap<Int64, Bool>, key: Int64, value: Bool): Unit {
    if (map.contains(key)) {
        map.remove(key)
    }
    map.add(key, value)
}

private func trimAscii(value: String): String {
    var start: Int64 = 0
    var end = value.size
    while (start < end && isAsciiSpace(value[start])) {
        start++
    }
    while (end > start && isAsciiSpace(value[end - 1])) {
        end--
    }
    return value[start..end]
}

private func isAsciiSpace(byte: UInt8): Bool {
    return byte == b' ' || byte == b'\t' || byte == b'\r' || byte == b'\n'
}

private func stripQuotes(value: String): String {
    if (value.size >= 2 && ((value[0] == b'"' && value[value.size - 1] == b'"') ||
        (value[0] == b'\'' && value[value.size - 1] == b'\''))) {
        return value[1..value.size - 1]
    }
    return value
}

private func FrontendOverflowStrategyName(strategy: OverflowStrategy): String {
    return match (strategy) {
        case OverflowStrategy.NA => "na"
        case OverflowStrategy.THROWING => "throwing"
        case OverflowStrategy.WRAPPING => "wrapping"
        case OverflowStrategy.SATURATING => "saturating"
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
