package cangjie_compiler::frontend

import cangjie_compiler::utils.FileUtil
import std.collection.*
import std.convert.*
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
        let strategyName = OverflowStrategyName(ci.invocation.globalOptions.overflowStrategy)
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
            let cjdSource = ReadCjdSource(pkgName, cjdPath, ci.importManager.GetSearchPath())
            if (!cjdSource[0]) {
                continue
            }
            let sourcePath = cjdSource[1]
            let sourceCode = cjdSource[2]
            let isCjmpFile = option.IsCompilingCJMP() || !option.commonPartCjos.isEmpty()
            let fileID = ci.GetSourceManager().AddSource(sourcePath, sourceCode, packageName: Some(pkgName),
                isCjmpFile: isCjmpFile)
            let parsedFile = ParseSourceFile(fileID, sourcePath, sourceCode, ci.diag, ci.GetSourceManager(),
                false, true)
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

private func ReadCjdSource(pkgName: String, configuredPath: String, searchPaths: ArrayList<String>): (Bool, String, String) {
    let configuredRead = ReadFileContent(configuredPath)
    if (configuredRead[0]) {
        return (true, configuredPath, configuredRead[1])
    }
    let discoveredPath = FileUtil.FindSerializationFile(pkgName, CJ_D_FILE_EXTENSION, searchPaths.toArray())
    if (discoveredPath.isEmpty()) {
        return (false, "", "")
    }
    let discoveredRead = ReadFileContent(discoveredPath)
    if (!discoveredRead[0]) {
        return (false, "", "")
    }
    let sourcePath = if (configuredPath.isEmpty()) { discoveredPath } else { configuredPath }
    return (true, sourcePath, discoveredRead[1])
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

    public func ParseModule(): Bool {
        var success = true
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
                currentPkg = FileUtil.GetPkgNameFromRelativePath(FileUtil.GetRelativePath(basePath, srcDir) ?? "")
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
                    s.ci.diag.Diagnose(DiagCategory.IMPORT_PACKAGE, DEFAULT_POSITION,
                        "failed to read source file '" + filePath + "': " + readResult[2])
                    success = false
                    continue
                }
                let fileID = addSourceForParse(filePath, readResult[1])
                fileInfos.add((filePath, fileID, readResult[1]))
            }
        }
        let pkg = Package(defaultPackageName)
        addParsedFilesToPackage(pkg, fileInfos)
        CheckPackageConsistency(pkg)
        if (!success) {
            pkg.SetAttr("PARSE_FAILED")
        }
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
    let _ = parseDeclFile
    let file = File()
    file.filePath = NormalizePath(filePath)
    file.fileName = GetFileName(file.filePath)
    file.fileHash = StableSourcePathHash(file.filePath)
    file.begin = Position(fileID, 1, 1)
    file.end = sm.GetSource(fileID).GetEndPos()
    let tokens = Tokenize(fileID, sourceCode, diag, sm, attachComment: attachComment)
    parsePackageAndImports(file, tokens)
    parseTopLevelDecls(file, tokens)
    // First real-expression slice (additive, gated): promote bodies that need genuine runtime
    // computation to a real CHIR body via the real parser. No-op for every summary-path slice.
    AdaptRealBodies(file, fileID, sourceCode, sm)
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
        var headerIdx = idx
        var headerModifier: Option<Modifier> = None
        if (IsAccessModifier(tok.value) && idx + 1 < tokens.size && IsHeaderKeywordAfterModifier(tokens, idx + 1)) {
            headerModifier = Some(MakeModifier(tok))
            headerIdx = idx + 1
        }
        let headerTok = tokens[headerIdx]
        if (headerTok.value == "macro" && headerIdx + 1 < tokens.size && tokens[headerIdx + 1].value == "package") {
            let spec = PackageSpec()
            spec.modifier = headerModifier
            spec.hasMacro = true
            spec.macroPos = headerTok.Begin()
            spec.packagePos = tokens[headerIdx + 1].Begin()
            let parsed = parseQualifiedName(tokens, headerIdx + 2)
            spec.packageName = SrcIdentifier(parsed[0], begin: tokens[headerIdx + 1].Begin(), end: tokens[headerIdx + 1].End())
            spec.begin = if (let Some(modifier) <- headerModifier) { modifier.begin } else { headerTok.Begin() }
            spec.end = parsed[1]
            file.packageSpec = Some(spec)
            idx = parsed[2]
            continue
        }
        if (headerTok.value == "package") {
            let spec = PackageSpec()
            spec.modifier = headerModifier
            spec.packagePos = headerTok.Begin()
            let parsed = parseQualifiedName(tokens, headerIdx + 1)
            spec.packageName = SrcIdentifier(parsed[0], begin: headerTok.Begin(), end: parsed[1])
            spec.begin = if (let Some(modifier) <- headerModifier) { modifier.begin } else { headerTok.Begin() }
            spec.end = parsed[1]
            file.packageSpec = Some(spec)
            idx = parsed[2]
            continue
        }
        if (headerTok.value == "import") {
            let importSpec = ImportSpec()
            importSpec.modifier = headerModifier
            importSpec.importPos = headerTok.Begin()
            let parsed = parseImportContent(tokens, headerIdx + 1)
            importSpec.content = parsed[0]
            importSpec.begin = if (let Some(modifier) <- headerModifier) { modifier.begin } else { headerTok.Begin() }
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

private func IsAccessModifier(value: String): Bool {
    return value == "public" || value == "protected" || value == "internal" || value == "private"
}

private func IsHeaderKeywordAfterModifier(tokens: ArrayList<FrontendToken>, idx: Int64): Bool {
    if (idx >= tokens.size) {
        return false
    }
    if (tokens[idx].value == "package" || tokens[idx].value == "import") {
        return true
    }
    return tokens[idx].value == "macro" && idx + 1 < tokens.size && tokens[idx + 1].value == "package"
}

private func MakeModifier(tok: FrontendToken): Modifier {
    let modifier = Modifier()
    modifier.name = tok.value
    modifier.begin = tok.Begin()
    modifier.end = tok.End()
    return modifier
}

private func parseTopLevelDecls(file: File, tokens: ArrayList<FrontendToken>): Unit {
    var idx: Int64 = 0
    while (idx < tokens.size) {
        idx = skipTrivia(tokens, idx)
        if (idx >= tokens.size) {
            break
        }
        let annoInfo = parseLeadingAnnotations(tokens, idx)
        let declStart = annoInfo[2]
        if (declStart >= tokens.size || !isDeclKeyword(tokens[declStart].value)) {
            idx++
            continue
        }
        let declInfo = createDeclFromKeyword(tokens, declStart)
        if (let Some(rawDecl) <- declInfo[0]) {
            let decl = rawDecl
            for (anno in annoInfo[0]) {
                decl.annotations.add(anno)
            }
            let tok = tokens[declStart]
            if (!annoInfo[3].IsZero()) {
                decl.begin = annoInfo[3]
            } else {
                decl.begin = tok.Begin()
            }
            decl.end = declInfo[1]
            if (let Some(invocation) <- annoInfo[1]) {
                invocation.decl = Some(decl)
                let macroDecl = MacroExpandDecl()
                macroDecl.invocation = invocation
                macroDecl.identifier = decl.identifier
                macroDecl.begin = invocationBegin(invocation, decl.begin)
                macroDecl.end = decl.end
                file.decls.add(macroDecl)
            } else {
                file.decls.add(decl)
            }
        }
        idx = declInfo[2]
    }
}

private func createDeclFromKeyword(tokens: ArrayList<FrontendToken>, start: Int64): (Option<Decl>, Position, Int64) {
    let keyword = tokens[start].value
    var nameIdx = start + 1
    if (isModifierKeyword(keyword)) {
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
        return finishParsedDecl(tokens, keyword, decl, parsed[2], parsed[1])
    }
    if (nameIdx < tokens.size && (tokens[nameIdx].kind == FrontendTokenKind.IDENTIFIER ||
        tokens[nameIdx].kind == FrontendTokenKind.KEYWORD || tokens[nameIdx].kind == FrontendTokenKind.OPERATOR)) {
        decl.identifier = SrcIdentifier(tokens[nameIdx].value, begin: tokens[nameIdx].Begin(), end: tokens[nameIdx].End())
        return finishParsedDecl(tokens, keyword, decl, nameIdx + 1, tokens[nameIdx].End())
    }
    if (keyword == "init") {
        decl.identifier = SrcIdentifier("init", begin: tokens[start].Begin(), end: tokens[start].End())
        return finishParsedDecl(tokens, keyword, decl, start + 1, tokens[start].End())
    }
    return (None, tokens[start].End(), start + 1)
}

private func finishParsedDecl(tokens: ArrayList<FrontendToken>, keyword: String, decl: Decl, start: Int64,
    fallbackEnd: Position): (Option<Decl>, Position, Int64) {
    var idx = skipTrivia(tokens, start)
    let genericInfo = parseGenericAt(tokens, idx)
    if (let Some(generic) <- genericInfo[0]) {
        decl.generic = Some(generic)
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            funcDecl.funcBody.generic = Some(generic)
        }
    }
    idx = skipTrivia(tokens, genericInfo[1])
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        if (idx < tokens.size && tokens[idx].value == "(") {
            idx = parseParameterListInto(tokens, idx, funcDecl.funcBody)
        }
        idx = skipTrivia(tokens, idx)
        if (idx < tokens.size && (tokens[idx].value == ":" || tokens[idx].value == "->")) {
            let typeInfo = parseTypeAt(tokens, idx + 1)
            funcDecl.funcBody.retType = typeInfo[0]
            idx = typeInfo[1]
        }
    } else if (let Some(varDecl) <- (decl as VarDecl)) {
        idx = parseVarLikeType(tokens, idx, varDecl)
    } else if (let Some(typeAliasDecl) <- (decl as TypeAliasDecl)) {
        idx = parseTypeAliasTarget(tokens, idx, typeAliasDecl)
    } else if (let Some(inheritableDecl) <- (decl as InheritableDecl)) {
        idx = parseInheritedTypes(tokens, idx, inheritableDecl)
    }
    let bodyInfo = finishDeclExtent(tokens, keyword, decl, idx, fallbackEnd)
    return (Some(decl), bodyInfo[0], bodyInfo[1])
}

private func skipTrivia(tokens: ArrayList<FrontendToken>, start: Int64): Int64 {
    var idx = start
    while (idx < tokens.size && (tokens[idx].kind == FrontendTokenKind.NL ||
        tokens[idx].kind == FrontendTokenKind.COMMENT)) {
        idx++
    }
    return idx
}

private func isModifierKeyword(value: String): Bool {
    return value == "public" || value == "protected" || value == "internal" || value == "private" ||
        value == "static" || value == "abstract" || value == "open" || value == "sealed" ||
        value == "foreign" || value == "unsafe" || value == "mut" || value == "operator" ||
        value == "override" || value == "redef"
}

private func parseLeadingAnnotations(tokens: ArrayList<FrontendToken>, start: Int64):
    (ArrayList<Annotation>, Option<MacroInvocation>, Int64, Position) {
    let annotations = ArrayList<Annotation>()
    var macroInvocation: Option<MacroInvocation> = None
    var idx = skipTrivia(tokens, start)
    var begin = INVALID_POSITION
    while (idx < tokens.size && tokens[idx].value == "@") {
        if (begin.IsZero()) {
            begin = tokens[idx].Begin()
        }
        let parsed = parseAnnotationOrMacro(tokens, idx)
        if (let Some(anno) <- parsed[0]) {
            annotations.add(anno)
        }
        if (let Some(invocation) <- parsed[1]) {
            macroInvocation = Some(invocation)
        }
        if (parsed[2] <= idx) {
            idx++
        } else {
            idx = skipTrivia(tokens, parsed[2])
        }
    }
    return (annotations, macroInvocation, idx, begin)
}

private func parseAnnotationOrMacro(tokens: ArrayList<FrontendToken>, start: Int64):
    (Option<Annotation>, Option<MacroInvocation>, Int64) {
    var idx = start + 1
    var isMacro = false
    if (idx < tokens.size && tokens[idx].value == "!") {
        isMacro = true
        idx++
    }
    let nameInfo = parseQualifiedName(tokens, idx)
    let name = nameInfo[0]
    if (name.isEmpty()) {
        return (None, None, start + 1)
    }
    idx = nameInfo[2]
    let argsInfo = parseDelimitedArgumentTokens(tokens, idx)
    idx = argsInfo[1]
    if (isMacro) {
        let invocation = MacroInvocation()
        invocation.fullName = name
        invocation.identifier = lastQualifiedNamePart(name)
        invocation.begin = tokens[start].Begin()
        invocation.end = argsInfo[2]
        for (argToken in argsInfo[0]) {
            invocation.attrs.add(argToken)
        }
        return (None, Some(invocation), idx)
    }
    let anno = Annotation()
    anno.identifier = SrcIdentifier(lastQualifiedNamePart(name), begin: tokens[start].Begin(), end: nameInfo[1])
    anno.begin = tokens[start].Begin()
    anno.end = argsInfo[2]
    for (argToken in argsInfo[0]) {
        if (argToken.value != ",") {
            anno.args.add(argToken.value)
        }
    }
    return (Some(anno), None, idx)
}

private func parseDelimitedArgumentTokens(tokens: ArrayList<FrontendToken>, start: Int64):
    (ArrayList<FrontendToken>, Int64, Position) {
    let out = ArrayList<FrontendToken>()
    if (start >= tokens.size || (tokens[start].value != "(" && tokens[start].value != "[")) {
        let pos = if (start > 0 && start - 1 < tokens.size) { tokens[start - 1].End() } else { INVALID_POSITION }
        return (out, start, pos)
    }
    let openValue = tokens[start].value
    let closeValue = if (openValue == "(") { ")" } else { "]" }
    var depth: Int64 = 1
    var idx = start + 1
    var endPos = tokens[start].End()
    while (idx < tokens.size && depth > 0) {
        if (tokens[idx].value == openValue) {
            depth++
            out.add(tokens[idx])
        } else if (tokens[idx].value == closeValue) {
            depth--
            if (depth > 0) {
                out.add(tokens[idx])
            }
            endPos = tokens[idx].End()
        } else {
            out.add(tokens[idx])
        }
        idx++
    }
    return (out, idx, endPos)
}

private func invocationBegin(invocation: MacroInvocation, fallback: Position): Position {
    if (!invocation.begin.IsZero()) {
        return invocation.begin
    }
    return fallback
}

private func parseGenericAt(tokens: ArrayList<FrontendToken>, start: Int64): (Option<Generic>, Int64) {
    if (start >= tokens.size || tokens[start].value != "<") {
        return (None, start)
    }
    if (start + 1 < tokens.size && tokens[start + 1].value == ":") {
        return (None, start)
    }
    let generic = Generic()
    var idx = start + 1
    var currentName = ""
    while (idx < tokens.size) {
        let tok = tokens[idx]
        if (tok.value == ">") {
            if (!currentName.isEmpty()) {
                generic.typeParameters.add(currentName)
            }
            return (Some(generic), idx + 1)
        }
        if (tok.value == ",") {
            if (!currentName.isEmpty()) {
                generic.typeParameters.add(currentName)
                currentName = ""
            }
        } else if (tok.value == "where") {
            let constraints = collectUntilTopLevel(tokens, idx + 1, "{")
            generic.genericConstraints.add(constraints[0])
            return (Some(generic), constraints[1])
        } else if (isNameToken(tok) && currentName.isEmpty()) {
            currentName = tok.value
        }
        idx++
    }
    return (Some(generic), idx)
}

private func parseParameterListInto(tokens: ArrayList<FrontendToken>, start: Int64, body: FuncBody): Int64 {
    var idx = start + 1
    var depth: Int64 = 1
    var paramStart = idx
    while (idx < tokens.size && depth > 0) {
        if (tokens[idx].value == "(") {
            depth++
        } else if (tokens[idx].value == ")") {
            depth--
            if (depth == 0) {
                parseOneParam(tokens, paramStart, idx, body)
                return idx + 1
            }
        } else if (tokens[idx].value == "," && depth == 1) {
            parseOneParam(tokens, paramStart, idx, body)
            paramStart = idx + 1
        }
        idx++
    }
    return idx
}

private func parseOneParam(tokens: ArrayList<FrontendToken>, start: Int64, end: Int64, body: FuncBody): Unit {
    var idx = skipTrivia(tokens, start)
    if (idx >= end) {
        return
    }
    let annotations = ArrayList<Annotation>()
    while (idx < end && tokens[idx].value == "@") {
        let parsed = parseAnnotationOrMacro(tokens, idx)
        if (let Some(anno) <- parsed[0]) {
            annotations.add(anno)
        }
        idx = parsed[2]
        idx = skipTrivia(tokens, idx)
    }
    if (idx >= end || !isNameToken(tokens[idx])) {
        return
    }
    let param = FuncParam()
    param.identifier = SrcIdentifier(tokens[idx].value, begin: tokens[idx].Begin(), end: tokens[idx].End())
    param.begin = tokens[idx].Begin()
    param.end = tokens[idx].End()
    for (anno in annotations) {
        param.annotations.add(anno)
    }
    idx++
    if (idx < end && tokens[idx].value == ":") {
        let typeInfo = parseTypeAtBounded(tokens, idx + 1, end)
        param.typeNode = typeInfo[0]
        if (let Some(typeNode) <- typeInfo[0]) {
            param.end = typeNode.end
        }
    }
    body.params.add(param)
}

private func parseVarLikeType(tokens: ArrayList<FrontendToken>, start: Int64, decl: VarDecl): Int64 {
    var idx = start
    if (idx < tokens.size && tokens[idx].value == ":") {
        let typeInfo = parseTypeAt(tokens, idx + 1)
        decl.typeNode = typeInfo[0]
        return typeInfo[1]
    }
    return idx
}

private func parseTypeAliasTarget(tokens: ArrayList<FrontendToken>, start: Int64, decl: TypeAliasDecl): Int64 {
    var idx = start
    if (idx < tokens.size && tokens[idx].value == "=") {
        let typeInfo = parseTypeAt(tokens, idx + 1)
        decl.typeNode = typeInfo[0]
        return typeInfo[1]
    }
    return idx
}

private func parseInheritedTypes(tokens: ArrayList<FrontendToken>, start: Int64, decl: InheritableDecl): Int64 {
    var idx = start
    while (idx < tokens.size) {
        if (tokens[idx].value == "<" && idx + 1 < tokens.size && tokens[idx + 1].value == ":") {
            idx += 2
        } else if (tokens[idx].value == ":") {
            idx++
        } else {
            break
        }
        while (idx < tokens.size && tokens[idx].value != "{" && tokens[idx].kind != FrontendTokenKind.NL) {
            let typeInfo = parseTypeAt(tokens, idx)
            if (let Some(typeNode) <- typeInfo[0]) {
                decl.inheritedTypes.add(typeNode)
            }
            idx = typeInfo[1]
            if (idx < tokens.size && tokens[idx].value == ",") {
                idx++
            } else {
                break
            }
        }
    }
    return idx
}

private func parseTypeAt(tokens: ArrayList<FrontendToken>, start: Int64): (Option<Type>, Int64) {
    return parseTypeAtBounded(tokens, start, tokens.size)
}

private func parseTypeAtBounded(tokens: ArrayList<FrontendToken>, start: Int64, end: Int64): (Option<Type>, Int64) {
    var idx = skipTrivia(tokens, start)
    if (idx >= end) {
        return (None, idx)
    }
    let parsed = parseQualifiedName(tokens, idx)
    if (parsed[0].isEmpty()) {
        return (None, idx)
    }
    idx = parsed[2]
    let typeNode = if (isPrimitiveTypeName(parsed[0])) {
        PrimitiveType(parsed[0])
    } else {
        RefType(parsed[0])
    }
    typeNode.begin = tokens[start].Begin()
    typeNode.end = parsed[1]
    if (idx < end && tokens[idx].value == "<") {
        let argsInfo = parseTypeArguments(tokens, idx, end)
        for (argType in argsInfo[0]) {
            typeNode.typeArguments.add(argType)
        }
        idx = argsInfo[1]
        if (idx > 0 && idx - 1 < tokens.size) {
            typeNode.end = tokens[idx - 1].End()
        }
    }
    return (Some(typeNode), idx)
}

private func parseTypeArguments(tokens: ArrayList<FrontendToken>, start: Int64, end: Int64): (ArrayList<Type>, Int64) {
    let out = ArrayList<Type>()
    var idx = start + 1
    while (idx < end) {
        if (tokens[idx].value == ">") {
            return (out, idx + 1)
        }
        if (tokens[idx].value == ",") {
            idx++
            continue
        }
        let typeInfo = parseTypeAtBounded(tokens, idx, end)
        if (let Some(typeNode) <- typeInfo[0]) {
            out.add(typeNode)
            idx = typeInfo[1]
        } else {
            idx++
        }
    }
    return (out, idx)
}

private func finishDeclExtent(tokens: ArrayList<FrontendToken>, keyword: String, decl: Decl, start: Int64,
    fallbackEnd: Position): (Position, Int64) {
    var idx = skipTrivia(tokens, start)
    while (idx < tokens.size && tokens[idx].kind != FrontendTokenKind.END) {
        if (tokens[idx].value == "{") {
            let closeIdx = findMatchingToken(tokens, idx, "{", "}")
            captureFunctionBodySummary(tokens, idx, closeIdx, decl)
            if (isMemberContainer(keyword)) {
                parseMemberDecls(decl, tokens, idx + 1, closeIdx)
            }
            if (closeIdx < tokens.size) {
                return (tokens[closeIdx].End(), closeIdx + 1)
            }
            return (tokens[idx].End(), idx + 1)
        }
        if (tokens[idx].kind == FrontendTokenKind.NL) {
            return (tokens[idx].End(), idx + 1)
        }
        if (tokens[idx].value == "}") {
            return (fallbackEnd, idx)
        }
        idx++
    }
    return (fallbackEnd, idx)
}

private func captureFunctionBodySummary(tokens: ArrayList<FrontendToken>, openIdx: Int64, closeIdx: Int64,
    decl: Decl): Unit {
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        let literalInfo = parseLiteralReturn(tokens, openIdx + 1, closeIdx)
        funcDecl.funcBody.hasLiteralReturn = literalInfo[0]
        funcDecl.funcBody.literalReturnKind = literalInfo[1]
        funcDecl.funcBody.literalReturnValue = literalInfo[2]
        funcDecl.funcBody.literalReturnBegin = literalInfo[3]
        funcDecl.funcBody.literalReturnEnd = literalInfo[4]
        captureFunctionBodyPrints(tokens, openIdx + 1, closeIdx, funcDecl.funcBody)
    }
}

// Recognize top-level `println("literal")` statements in a function body and record the
// (quote-stripped) string so CodeGen can emit a real runtime print. Scans only at brace
// depth 0 so calls nested inside other constructs are ignored.
private func captureFunctionBodyPrints(tokens: ArrayList<FrontendToken>, start: Int64, end: Int64,
    body: FuncBody): Unit {
    var idx = start
    var depth: Int64 = 0
    while (idx < end && idx < tokens.size) {
        let value = tokens[idx].value
        if (value == "{" || value == "[") {
            depth++
            idx++
            continue
        }
        if (value == "}" || value == "]") {
            if (depth > 0) { depth-- }
            idx++
            continue
        }
        if (depth == 0 && tokens[idx].kind == FrontendTokenKind.IDENTIFIER &&
            (value == "println" || value == "print")) {
            let newline = value == "println"
            let openParen = skipTrivia(tokens, idx + 1)
            if (openParen < end && openParen < tokens.size && tokens[openParen].value == "(") {
                let argIdx = skipTrivia(tokens, openParen + 1)
                if (argIdx < end && argIdx < tokens.size &&
                    tokens[argIdx].kind == FrontendTokenKind.STRING_LITERAL) {
                    let closeParen = skipTrivia(tokens, argIdx + 1)
                    if (closeParen < end && closeParen < tokens.size && tokens[closeParen].value == ")") {
                        body.printStrings.add(StripLiteralQuotes(tokens[argIdx].value))
                        body.printNewlines.add(newline)
                        body.printIsInt.add(false)
                        idx = closeParen + 1
                        continue
                    }
                }
                // `println(<int>)` / `print(<int>)` where the arg is an integer literal (optionally
                // signed) or a let-bound integer literal. Capture the decimal text as an int entry.
                let intArg = resolvePrintIntArg(tokens, argIdx, end, start, idx)
                if (intArg[0]) {
                    let closeParen = skipTrivia(tokens, intArg[2])
                    if (closeParen < end && closeParen < tokens.size && tokens[closeParen].value == ")") {
                        body.printStrings.add(intArg[1])
                        body.printNewlines.add(newline)
                        body.printIsInt.add(true)
                        idx = closeParen + 1
                        continue
                    }
                }
            }
        }
        idx++
    }
}

// Resolve the integer argument of a `println`/`print` call beginning at `argIdx`. Accepts an
// integer literal (optionally a leading `-`) or a bare identifier bound earlier in the same body
// by `let <name> = <int literal>` (reusing the let-int folding rules). Returns (ok, decimalText,
// indexAfterArg) where indexAfterArg is the token index immediately after the consumed argument
// (caller must still verify a `)` follows). On failure returns (false, "", argIdx).
private func resolvePrintIntArg(tokens: ArrayList<FrontendToken>, argIdx: Int64, end: Int64,
    bodyStart: Int64, callIdx: Int64): (Bool, String, Int64) {
    if (argIdx >= end || argIdx >= tokens.size) {
        return (false, "", argIdx)
    }
    let tok = tokens[argIdx]
    if (tok.kind == FrontendTokenKind.INTEGER_LITERAL) {
        return (true, tok.value, argIdx + 1)
    }
    if (tok.value == "-" && argIdx + 1 < end && argIdx + 1 < tokens.size &&
        tokens[argIdx + 1].kind == FrontendTokenKind.INTEGER_LITERAL) {
        return (true, "-" + tokens[argIdx + 1].value, argIdx + 2)
    }
    if (tok.kind == FrontendTokenKind.IDENTIFIER) {
        let resolved = resolveLetLiteral(tokens, bodyStart, callIdx, tok.value)
        if (resolved[0] && resolved[1] == FRONTEND_LITERAL_INT) {
            return (true, resolved[2], argIdx + 1)
        }
    }
    return (false, "", argIdx)
}

private func parseLiteralReturn(tokens: ArrayList<FrontendToken>, start: Int64, end: Int64):
    (Bool, Int64, String, Position, Position) {
    var idx = start
    var depth: Int64 = 0
    while (idx < end && idx < tokens.size) {
        if (tokens[idx].value == "{" || tokens[idx].value == "(" || tokens[idx].value == "[") {
            depth++
            idx++
            continue
        }
        if (tokens[idx].value == "}" || tokens[idx].value == ")" || tokens[idx].value == "]") {
            if (depth > 0) {
                depth--
            }
            idx++
            continue
        }
        if (depth == 0 && tokens[idx].value == "return") {
            let valueIdx = skipTrivia(tokens, idx + 1)
            return parseLiteralReturnValue(tokens, valueIdx, end, start, idx)
        }
        idx++
    }
    return (false, FRONTEND_LITERAL_UNKNOWN, "", INVALID_POSITION, INVALID_POSITION)
}

private func parseLiteralReturnValue(tokens: ArrayList<FrontendToken>, idx: Int64,
    end: Int64, bodyStart: Int64, returnIdx: Int64): (Bool, Int64, String, Position, Position) {
    if (idx >= end || idx >= tokens.size) {
        return (false, FRONTEND_LITERAL_UNKNOWN, "", INVALID_POSITION, INVALID_POSITION)
    }
    // `return <intexpr>`: compile-time fold an integer-arithmetic expression built from integer
    // literals, let-bound integer literals (via the existing let-folding), and the operators
    // + - * / % with parentheses. The Int64 result is fed through the existing literal-return
    // path. This runs before the single-literal cases so e.g. `return 2 + 3 * 4` is not cut
    // short at the leading `2`. Conservative: any unsupported token, non-integer operand, or
    // division by zero falls back to the single-literal/let-fold handling below.
    let exprEnd = findReturnExprEnd(tokens, idx, end)
    let folded = foldIntArithReturn(tokens, idx, exprEnd, bodyStart, returnIdx)
    if (folded[0]) {
        return (true, FRONTEND_LITERAL_INT, folded[1].toString(), tokens[idx].Begin(), tokens[exprEnd - 1].End())
    }
    let tok = tokens[idx]
    if (tok.kind == FrontendTokenKind.BOOL_LITERAL) {
        return (true, FRONTEND_LITERAL_BOOL, tok.value, tok.Begin(), tok.End())
    }
    if (tok.kind == FrontendTokenKind.INTEGER_LITERAL) {
        return (true, FRONTEND_LITERAL_INT, tok.value, tok.Begin(), tok.End())
    }
    if (tok.kind == FrontendTokenKind.FLOAT_LITERAL) {
        return (true, FRONTEND_LITERAL_FLOAT, tok.value, tok.Begin(), tok.End())
    }
    if (tok.value == "-" && idx + 1 < end && idx + 1 < tokens.size) {
        let signedTok = tokens[idx + 1]
        if (signedTok.kind == FrontendTokenKind.INTEGER_LITERAL) {
            return (true, FRONTEND_LITERAL_INT, "-" + signedTok.value, tok.Begin(), signedTok.End())
        }
        if (signedTok.kind == FrontendTokenKind.FLOAT_LITERAL) {
            return (true, FRONTEND_LITERAL_FLOAT, "-" + signedTok.value, tok.Begin(), signedTok.End())
        }
    }
    if (tok.kind == FrontendTokenKind.STRING_LITERAL) {
        return (true, FRONTEND_LITERAL_STRING, StripLiteralQuotes(tok.value), tok.Begin(), tok.End())
    }
    if (tok.value == "(" && idx + 1 < end && idx + 1 < tokens.size && tokens[idx + 1].value == ")") {
        return (true, FRONTEND_LITERAL_UNIT, "", tok.Begin(), tokens[idx + 1].End())
    }
    // `return <identifier>`: fold a single-assignment, literal-initialized immutable `let`
    // declared earlier at brace depth 0 in the same body. Conservative: bare identifier only
    // (nothing but trivia / `}` after it), and the binding must resolve to a plain literal.
    if (tok.kind == FrontendTokenKind.IDENTIFIER && isBareReturnIdentifier(tokens, idx + 1, end)) {
        return resolveLetLiteral(tokens, bodyStart, returnIdx, tok.value)
    }
    return (false, FRONTEND_LITERAL_UNKNOWN, "", INVALID_POSITION, INVALID_POSITION)
}

// Find the exclusive end index of the return expression: the first brace-depth-0 statement
// terminator (NL / `;` / `}`) at or after `start`, clamped to `end`.
private func findReturnExprEnd(tokens: ArrayList<FrontendToken>, start: Int64, end: Int64): Int64 {
    var idx = start
    var depth: Int64 = 0
    while (idx < end && idx < tokens.size) {
        let tok = tokens[idx]
        if (tok.value == "(" || tok.value == "[" || tok.value == "{") {
            depth++
        } else if (tok.value == ")" || tok.value == "]" || tok.value == "}") {
            if (depth == 0) {
                return idx
            }
            depth--
        } else if (depth == 0 && (tok.kind == FrontendTokenKind.NL ||
            tok.kind == FrontendTokenKind.COMMENT || tok.value == ";")) {
            return idx
        }
        idx++
    }
    return idx
}

// Attempt to evaluate tokens[start..exprEnd) as an Int64 arithmetic expression. Returns
// (true, value) on success, (false, 0) on any unsupported construct.
private func foldIntArithReturn(tokens: ArrayList<FrontendToken>, start: Int64, exprEnd: Int64,
    bodyStart: Int64, returnIdx: Int64): (Bool, Int64) {
    // Reject an expression that is itself a single bare literal/identifier: those are already
    // handled by the dedicated literal/let-fold paths above. Only fold when an operator appears.
    if (!containsArithOperator(tokens, start, exprEnd)) {
        return (false, 0)
    }
    let parser = IntArithEvaluator(tokens, exprEnd, bodyStart, returnIdx)
    let result = parser.evalAddSub(skipArithTrivia(tokens, start, exprEnd))
    if (!result.ok) {
        return (false, 0)
    }
    let finalIdx = skipArithTrivia(tokens, result.next, exprEnd)
    if (finalIdx != exprEnd) {
        return (false, 0)
    }
    return (true, result.value)
}

private func containsArithOperator(tokens: ArrayList<FrontendToken>, start: Int64, exprEnd: Int64): Bool {
    var idx = start
    while (idx < exprEnd && idx < tokens.size) {
        let v = tokens[idx].value
        if (v == "+" || v == "-" || v == "*" || v == "/" || v == "%") {
            return true
        }
        idx++
    }
    return false
}

private func skipArithTrivia(tokens: ArrayList<FrontendToken>, start: Int64, exprEnd: Int64): Int64 {
    var idx = start
    while (idx < exprEnd && idx < tokens.size && (tokens[idx].kind == FrontendTokenKind.NL ||
        tokens[idx].kind == FrontendTokenKind.COMMENT)) {
        idx++
    }
    return idx
}

private struct ArithResult {
    let ok: Bool
    let value: Int64
    let next: Int64
    init(ok: Bool, value: Int64, next: Int64) {
        this.ok = ok
        this.value = value
        this.next = next
    }
}

private let ARITH_FAIL = ArithResult(false, 0, 0)

// Recursive-descent evaluator over a frontend token slice for integer arithmetic.
// Grammar (standard precedence):
//   addSub  := mulDiv (("+" | "-") mulDiv)*
//   mulDiv  := unary (("*" | "/" | "%") unary)*
//   unary   := ("-" | "+")* primary
//   primary := INT_LITERAL | IDENTIFIER(let-folded int) | "(" addSub ")"
private class IntArithEvaluator {
    private let tokens: ArrayList<FrontendToken>
    private let exprEnd: Int64
    private let bodyStart: Int64
    private let returnIdx: Int64

    init(tokens: ArrayList<FrontendToken>, exprEnd: Int64, bodyStart: Int64, returnIdx: Int64) {
        this.tokens = tokens
        this.exprEnd = exprEnd
        this.bodyStart = bodyStart
        this.returnIdx = returnIdx
    }

    func evalAddSub(start: Int64): ArithResult {
        var left = evalMulDiv(start)
        if (!left.ok) {
            return ARITH_FAIL
        }
        var idx = skipArithTrivia(tokens, left.next, exprEnd)
        while (idx < exprEnd && idx < tokens.size && (tokens[idx].value == "+" || tokens[idx].value == "-")) {
            let op = tokens[idx].value
            let rhs = evalMulDiv(skipArithTrivia(tokens, idx + 1, exprEnd))
            if (!rhs.ok) {
                return ARITH_FAIL
            }
            let combined = if (op == "+") { left.value + rhs.value } else { left.value - rhs.value }
            left = ArithResult(true, combined, rhs.next)
            idx = skipArithTrivia(tokens, rhs.next, exprEnd)
        }
        return left
    }

    func evalMulDiv(start: Int64): ArithResult {
        var left = evalUnary(start)
        if (!left.ok) {
            return ARITH_FAIL
        }
        var idx = skipArithTrivia(tokens, left.next, exprEnd)
        while (idx < exprEnd && idx < tokens.size &&
            (tokens[idx].value == "*" || tokens[idx].value == "/" || tokens[idx].value == "%")) {
            let op = tokens[idx].value
            let rhs = evalUnary(skipArithTrivia(tokens, idx + 1, exprEnd))
            if (!rhs.ok) {
                return ARITH_FAIL
            }
            if ((op == "/" || op == "%") && rhs.value == 0) {
                return ARITH_FAIL
            }
            let combined = if (op == "*") {
                left.value * rhs.value
            } else if (op == "/") {
                left.value / rhs.value
            } else {
                left.value % rhs.value
            }
            left = ArithResult(true, combined, rhs.next)
            idx = skipArithTrivia(tokens, rhs.next, exprEnd)
        }
        return left
    }

    func evalUnary(start: Int64): ArithResult {
        let idx = skipArithTrivia(tokens, start, exprEnd)
        if (idx >= exprEnd || idx >= tokens.size) {
            return ARITH_FAIL
        }
        let v = tokens[idx].value
        if (v == "-") {
            let inner = evalUnary(idx + 1)
            if (!inner.ok) {
                return ARITH_FAIL
            }
            return ArithResult(true, -inner.value, inner.next)
        }
        if (v == "+") {
            return evalUnary(idx + 1)
        }
        return evalPrimary(idx)
    }

    func evalPrimary(start: Int64): ArithResult {
        let idx = skipArithTrivia(tokens, start, exprEnd)
        if (idx >= exprEnd || idx >= tokens.size) {
            return ARITH_FAIL
        }
        let tok = tokens[idx]
        if (tok.value == "(") {
            let inner = evalAddSub(idx + 1)
            if (!inner.ok) {
                return ARITH_FAIL
            }
            let closeIdx = skipArithTrivia(tokens, inner.next, exprEnd)
            if (closeIdx >= exprEnd || closeIdx >= tokens.size || tokens[closeIdx].value != ")") {
                return ARITH_FAIL
            }
            return ArithResult(true, inner.value, closeIdx + 1)
        }
        if (tok.kind == FrontendTokenKind.INTEGER_LITERAL) {
            if (let Some(parsed) <- parseArithIntLiteral(tok.value)) {
                return ArithResult(true, parsed, idx + 1)
            }
            return ARITH_FAIL
        }
        if (tok.kind == FrontendTokenKind.IDENTIFIER) {
            // Reuse the existing let-folding to resolve a let-bound integer literal.
            let resolved = resolveLetLiteral(tokens, bodyStart, returnIdx, tok.value)
            if (resolved[0] && resolved[1] == FRONTEND_LITERAL_INT) {
                if (let Some(parsed) <- parseArithIntLiteral(resolved[2])) {
                    return ArithResult(true, parsed, idx + 1)
                }
            }
            return ARITH_FAIL
        }
        return ARITH_FAIL
    }
}

private func parseArithIntLiteral(value: String): Option<Int64> {
    let normalized = value.replace("_", "")
    try {
        return Some(Int64.parse(normalized))
    } catch (e: Exception) {
        return None
    }
}

// True if the only thing following the returned identifier (within the body) is trivia or the
// closing brace, so `return x` qualifies but `return x + 1` / `return f(x)` do not.
private func isBareReturnIdentifier(tokens: ArrayList<FrontendToken>, after: Int64, end: Int64): Bool {
    let nextIdx = skipTrivia(tokens, after)
    if (nextIdx >= end || nextIdx >= tokens.size) {
        return true
    }
    return tokens[nextIdx].value == "}"
}

// Scan brace-depth-0 statements before `returnIdx` for `let <name> = <literal>` and fold it into
// the literal return value. Requires exactly one matching immutable binding (no `var`, no
// reassignment, no expression initializer).
private func resolveLetLiteral(tokens: ArrayList<FrontendToken>, bodyStart: Int64, returnIdx: Int64,
    name: String): (Bool, Int64, String, Position, Position) {
    var idx = bodyStart
    var depth: Int64 = 0
    var found = false
    var result = (false, FRONTEND_LITERAL_UNKNOWN, "", INVALID_POSITION, INVALID_POSITION)
    while (idx < returnIdx && idx < tokens.size) {
        let value = tokens[idx].value
        if (value == "{" || value == "(" || value == "[") {
            depth++
            idx++
            continue
        }
        if (value == "}" || value == ")" || value == "]") {
            if (depth > 0) {
                depth--
            }
            idx++
            continue
        }
        if (depth == 0 && (value == "let" || value == "var")) {
            let nameIdx = skipTrivia(tokens, idx + 1)
            if (nameIdx < returnIdx && nameIdx < tokens.size &&
                tokens[nameIdx].kind == FrontendTokenKind.IDENTIFIER && tokens[nameIdx].value == name) {
                // Any rebinding (a second decl or `var`) of this name is not foldable.
                if (value == "var" || found) {
                    return (false, FRONTEND_LITERAL_UNKNOWN, "", INVALID_POSITION, INVALID_POSITION)
                }
                let eqIdx = skipTrivia(tokens, nameIdx + 1)
                if (eqIdx < returnIdx && eqIdx < tokens.size && tokens[eqIdx].value == "=") {
                    let initIdx = skipTrivia(tokens, eqIdx + 1)
                    let literal = parseBareLetLiteral(tokens, initIdx, returnIdx)
                    if (literal[0]) {
                        found = true
                        result = literal
                    } else {
                        return (false, FRONTEND_LITERAL_UNKNOWN, "", INVALID_POSITION, INVALID_POSITION)
                    }
                } else {
                    return (false, FRONTEND_LITERAL_UNKNOWN, "", INVALID_POSITION, INVALID_POSITION)
                }
            }
            // Skip past the declared name so it is not re-scanned as a reassignment below.
            idx = nameIdx + 1
            continue
        }
        // Detect a top-level reassignment `<name> = ...` which would make folding unsound.
        if (depth == 0 && tokens[idx].kind == FrontendTokenKind.IDENTIFIER && value == name) {
            let nextIdx = skipTrivia(tokens, idx + 1)
            if (nextIdx < returnIdx && nextIdx < tokens.size && tokens[nextIdx].value == "=") {
                return (false, FRONTEND_LITERAL_UNKNOWN, "", INVALID_POSITION, INVALID_POSITION)
            }
        }
        idx++
    }
    return result
}

// Parse a `let` initializer that must be a single bare literal: a bool/int/float/string/unit
// literal (optionally a leading `-`) with nothing but a statement terminator following it.
// Rejects expression initializers like `3 + 4` so folding stays sound.
private func parseBareLetLiteral(tokens: ArrayList<FrontendToken>, idx: Int64,
    end: Int64): (Bool, Int64, String, Position, Position) {
    if (idx >= end || idx >= tokens.size) {
        return (false, FRONTEND_LITERAL_UNKNOWN, "", INVALID_POSITION, INVALID_POSITION)
    }
    let tok = tokens[idx]
    var kind = FRONTEND_LITERAL_UNKNOWN
    var value = ""
    var litEnd = INVALID_POSITION
    var nextIdx = idx + 1
    if (tok.kind == FrontendTokenKind.BOOL_LITERAL) {
        kind = FRONTEND_LITERAL_BOOL; value = tok.value; litEnd = tok.End()
    } else if (tok.kind == FrontendTokenKind.INTEGER_LITERAL) {
        kind = FRONTEND_LITERAL_INT; value = tok.value; litEnd = tok.End()
    } else if (tok.kind == FrontendTokenKind.FLOAT_LITERAL) {
        kind = FRONTEND_LITERAL_FLOAT; value = tok.value; litEnd = tok.End()
    } else if (tok.kind == FrontendTokenKind.STRING_LITERAL) {
        kind = FRONTEND_LITERAL_STRING; value = StripLiteralQuotes(tok.value); litEnd = tok.End()
    } else if (tok.value == "-" && idx + 1 < end && idx + 1 < tokens.size) {
        let signedTok = tokens[idx + 1]
        if (signedTok.kind == FrontendTokenKind.INTEGER_LITERAL) {
            kind = FRONTEND_LITERAL_INT; value = "-" + signedTok.value; litEnd = signedTok.End(); nextIdx = idx + 2
        } else if (signedTok.kind == FrontendTokenKind.FLOAT_LITERAL) {
            kind = FRONTEND_LITERAL_FLOAT; value = "-" + signedTok.value; litEnd = signedTok.End(); nextIdx = idx + 2
        }
    } else if (tok.value == "(" && idx + 1 < end && idx + 1 < tokens.size && tokens[idx + 1].value == ")") {
        kind = FRONTEND_LITERAL_UNIT; value = ""; litEnd = tokens[idx + 1].End(); nextIdx = idx + 2
    }
    if (kind == FRONTEND_LITERAL_UNKNOWN) {
        return (false, FRONTEND_LITERAL_UNKNOWN, "", INVALID_POSITION, INVALID_POSITION)
    }
    // The literal must end the statement: the very next token (no trivia skipped) must be a
    // newline, comment, `;`, `}`, or the body end. Anything else (e.g. `+`) means an expression.
    if (nextIdx < end && nextIdx < tokens.size) {
        let nextTok = tokens[nextIdx]
        let isTerminator = nextTok.kind == FrontendTokenKind.NL ||
            nextTok.kind == FrontendTokenKind.COMMENT ||
            nextTok.value == ";" || nextTok.value == "}"
        if (!isTerminator) {
            return (false, FRONTEND_LITERAL_UNKNOWN, "", INVALID_POSITION, INVALID_POSITION)
        }
    }
    return (true, kind, value, tok.Begin(), litEnd)
}

private func StripLiteralQuotes(value: String): String {
    if (value.size >= 2 && ((value.startsWith("\"") && value.endsWith("\"")) ||
        (value.startsWith("'") && value.endsWith("'")))) {
        return value[1..value.size - 1]
    }
    return value
}

private func parseMemberDecls(parent: Decl, tokens: ArrayList<FrontendToken>, start: Int64, end: Int64): Unit {
    var idx = start
    var depth: Int64 = 0
    while (idx < end) {
        if (tokens[idx].value == "{") {
            depth++
            idx++
            continue
        }
        if (tokens[idx].value == "}") {
            if (depth > 0) {
                depth--
            }
            idx++
            continue
        }
        if (depth != 0) {
            idx++
            continue
        }
        idx = skipTrivia(tokens, idx)
        if (idx >= end) {
            break
        }
        let annoInfo = parseLeadingAnnotations(tokens, idx)
        let declStart = annoInfo[2]
        if (declStart >= end || !isDeclKeyword(tokens[declStart].value)) {
            idx++
            continue
        }
        let declInfo = createDeclFromKeyword(tokens, declStart)
        if (let Some(memberDecl) <- declInfo[0]) {
            for (anno in annoInfo[0]) {
                memberDecl.annotations.add(anno)
            }
            if (!annoInfo[3].IsZero()) {
                memberDecl.begin = annoInfo[3]
            }
            memberDecl.end = declInfo[1]
            if (let Some(invocation) <- annoInfo[1]) {
                invocation.decl = Some(memberDecl)
                let macroDecl = MacroExpandDecl()
                macroDecl.invocation = invocation
                macroDecl.identifier = memberDecl.identifier
                macroDecl.begin = invocationBegin(invocation, memberDecl.begin)
                macroDecl.end = memberDecl.end
                parent.members.add(macroDecl)
            } else {
                parent.members.add(memberDecl)
            }
        }
        idx = declInfo[2]
    }
}

private func findMatchingToken(tokens: ArrayList<FrontendToken>, start: Int64, openValue: String, closeValue: String): Int64 {
    var depth: Int64 = 0
    var idx = start
    while (idx < tokens.size) {
        if (tokens[idx].value == openValue) {
            depth++
        } else if (tokens[idx].value == closeValue) {
            depth--
            if (depth == 0) {
                return idx
            }
        }
        idx++
    }
    return tokens.size
}

private func collectUntilTopLevel(tokens: ArrayList<FrontendToken>, start: Int64, stopValue: String): (String, Int64) {
    let builder = StringBuilder()
    var idx = start
    while (idx < tokens.size && tokens[idx].value != stopValue && tokens[idx].kind != FrontendTokenKind.NL) {
        if (builder.size > 0) {
            builder.append(" ")
        }
        builder.append(tokens[idx].value)
        idx++
    }
    return (builder.toString(), idx)
}

private func isMemberContainer(keyword: String): Bool {
    return keyword == "class" || keyword == "interface" || keyword == "struct" ||
        keyword == "enum" || keyword == "extend"
}

private func isNameToken(tok: FrontendToken): Bool {
    return tok.kind == FrontendTokenKind.IDENTIFIER || tok.kind == FrontendTokenKind.KEYWORD ||
        tok.kind == FrontendTokenKind.OPERATOR
}

private func isPrimitiveTypeName(name: String): Bool {
    return name == "Unit" || name == "Bool" || name == "Rune" || name == "Int8" ||
        name == "Int16" || name == "Int32" || name == "Int64" || name == "IntNative" ||
        name == "UInt8" || name == "UInt16" || name == "UInt32" || name == "UInt64" ||
        name == "UIntNative" || name == "Float16" || name == "Float32" || name == "Float64"
}

private func lastQualifiedNamePart(name: String): String {
    if (let Some(pos) <- name.lastIndexOf(".")) {
        return name[pos + 1..]
    }
    return name
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
    if (nextIdx < tokens.size && tokens[nextIdx].value == "*") {
        if (!content.identifier.Empty()) {
            content.prefixPaths.add(content.identifier.Val())
        }
        content.identifier = SrcIdentifier("*", begin: tokens[nextIdx].Begin(), end: tokens[nextIdx].End())
        content.isImportAll = true
        endPos = tokens[nextIdx].End()
        nextIdx++
    }
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

private func compareString(left: String, right: String): Ordering {
    if (left < right) {
        return Ordering.LT
    }
    if (left > right) {
        return Ordering.GT
    }
    return Ordering.EQ
}
