package cangjie_compiler::frontend

public import cangjie_compiler::basic.{
    BEGIN_POSITION, DEFAULT_POSITION, INVALID_POSITION, DiagCategory, DiagColor, DiagKindRefactor, DiagSeverity,
    IntegratedString, MakeRange, Position, PositionStatus, Range, Source, SourceManager
}
public import cangjie_compiler::ast.*
import cangjie_compiler::basic.Diagnostic as BasicDiagnostic
import cangjie_compiler::basic.DiagFormat as BasicDiagFormat
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.Range as BasicRange
import cangjie_compiler::chir.CHIRContext as RealCHIRContext
import cangjie_compiler::chir.Package as RealCHIRPackage
import cangjie_compiler::utils.FileUtil
import std.collection.*
import std.sort.*

public class DiagnosticEngine {
    private let impl: BasicDiagnosticEngine = BasicDiagnosticEngine()

    public init() {}

    public func SetSourceManager(sourceManager: SourceManager): Unit {
        impl.SetSourceManager(sourceManager)
    }

    public func GetSourceManager(): SourceManager {
        return impl.GetSourceManager()
    }

    public func RegisterHandler(format: BasicDiagFormat): Unit {
        impl.RegisterHandler(format)
    }

    public func SetErrorCountLimit(errorCountLimit: Option<UInt64>): Unit {
        impl.SetErrorCountLimit(errorCountLimit)
    }

    func AsBasicDiagnosticEngine(): BasicDiagnosticEngine {
        return impl
    }

    public func Diagnose(category: DiagCategory, position: Position, message: String): Unit {
        emitFrontendDiagnostic(this, category, position, message, DiagSeverity.DS_ERROR)
    }

    public func DiagnoseRefactor(kind: DiagKindRefactor, position: Position,
        arguments!: Array<String> = Array<String>()): Unit {
        impl.DiagnoseRefactor(kind, position, arguments: arguments).Emit()
    }

    public func Warn(category: DiagCategory, position: Position, message: String): Unit {
        emitFrontendDiagnostic(this, category, position, message, DiagSeverity.DS_WARNING)
    }

    public func Note(category: DiagCategory, position: Position, message: String): Unit {
        emitFrontendDiagnostic(this, category, position, message, DiagSeverity.DS_NOTE)
    }

    public func GetErrorCount(): UInt64 {
        return impl.GetErrorCount()
    }

    public func GetWarningCount(): UInt64 {
        return impl.GetWarningCount()
    }

    public func EmitCategoryDiagnostics(category: DiagCategory): Unit {
        impl.EmitCategoryDiagnostics(category)
    }

    public func EmitCategoryGroup(): Unit {
        impl.EmitCategoryGroup()
    }

    public func ReportErrorAndWarningCount(): Unit {
        impl.ReportErrorAndWarningCount()
    }

    public func HandleDiagnostic(diagnostic: BasicDiagnostic): Unit {
        impl.HandleDiagnostic(diagnostic)
    }
}

private func emitFrontendDiagnostic(
    diag: DiagnosticEngine,
    category: DiagCategory,
    position: Position,
    message: String,
    severity: DiagSeverity
): Unit {
    let diagnostic = BasicDiagnostic()
    diagnostic.isRefactor = true
    diagnostic.diagCategory = category
    diagnostic.diagSeverity = severity
    diagnostic.errorMessage = message
    diagnostic.start = INVALID_POSITION
    diagnostic.end = INVALID_POSITION
    diagnostic.mainHint = IntegratedString(frontendDiagnosticRange(position), "", frontendDiagnosticColor(severity))
    diag.HandleDiagnostic(diagnostic)
}

private func frontendDiagnosticRange(position: Position): BasicRange {
    if (position == DEFAULT_POSITION || position.IsZero()) {
        return MakeRange(DEFAULT_POSITION, DEFAULT_POSITION)
    }
    return MakeRange(position, position + 1)
}

private func frontendDiagnosticColor(severity: DiagSeverity): DiagColor {
    return match (severity) {
        case DiagSeverity.DS_ERROR => DiagColor.RED
        case DiagSeverity.DS_WARNING => DiagColor.YELLOW
        case DiagSeverity.DS_NOTE => DiagColor.BLUE
        case DiagSeverity.DS_HINT => DiagColor.GREEN
    }
}

public enum FrontendTokenKind {
    | IDENTIFIER
    | KEYWORD
    | INTEGER_LITERAL
    | FLOAT_LITERAL
    | STRING_LITERAL
    | BOOL_LITERAL
    | COMMENT
    | NL
    | OPERATOR
    | END
}

private func FrontendTokenKindIndex(kind: FrontendTokenKind): Int64 {
    return match (kind) {
        case FrontendTokenKind.IDENTIFIER => 0
        case FrontendTokenKind.KEYWORD => 1
        case FrontendTokenKind.INTEGER_LITERAL => 2
        case FrontendTokenKind.FLOAT_LITERAL => 3
        case FrontendTokenKind.STRING_LITERAL => 4
        case FrontendTokenKind.BOOL_LITERAL => 5
        case FrontendTokenKind.COMMENT => 6
        case FrontendTokenKind.NL => 7
        case FrontendTokenKind.OPERATOR => 8
        case FrontendTokenKind.END => 9
    }
}

extend FrontendTokenKind <: Equatable<FrontendTokenKind> {
    public operator func ==(rhs: FrontendTokenKind): Bool {
        return FrontendTokenKindIndex(this) == FrontendTokenKindIndex(rhs)
    }

    public operator func !=(rhs: FrontendTokenKind): Bool {
        return !(this == rhs)
    }
}

public func FrontendTokenKindName(kind: FrontendTokenKind): String {
    return match (kind) {
        case FrontendTokenKind.IDENTIFIER => "IDENTIFIER"
        case FrontendTokenKind.KEYWORD => "KEYWORD"
        case FrontendTokenKind.INTEGER_LITERAL => "INTEGER_LITERAL"
        case FrontendTokenKind.FLOAT_LITERAL => "FLOAT_LITERAL"
        case FrontendTokenKind.STRING_LITERAL => "STRING_LITERAL"
        case FrontendTokenKind.BOOL_LITERAL => "BOOL_LITERAL"
        case FrontendTokenKind.COMMENT => "COMMENT"
        case FrontendTokenKind.NL => "NL"
        case FrontendTokenKind.OPERATOR => "OPERATOR"
        case FrontendTokenKind.END => "END"
    }
}

public class FrontendToken {
    private var beginPos: Position
    private var endPos: Position
    public var kind: FrontendTokenKind
    public var value: String
    private var rawKindName: String = ""

    public init(kind: FrontendTokenKind, value: String, begin: Position, end: Position,
        rawKindName!: String = "") {
        this.kind = kind
        this.value = value
        this.rawKindName = rawKindName
        beginPos = begin
        endPos = end
    }

    public func Begin(): Position {
        return beginPos
    }

    public func End(): Position {
        return endPos
    }

    public func KindName(): String {
        return if (rawKindName.isEmpty()) { FrontendTokenKindName(kind) } else { rawKindName }
    }
}

public class CompilationCache {
    public var compileArgs: String = ""
    public var lambdaCounter: Int64 = 0
    public let bitcodeFilesName: ArrayList<String> = ArrayList<String>()
    public let fileSummaries: ArrayList<String> = ArrayList<String>()
    public let declSummaries: ArrayList<String> = ArrayList<String>()
    public init() {}
}

public class CHIRPackage {
    public var name: String
    public var fileCount: Int64 = 0
    public var declCount: Int64 = 0
    public let mangleNames: ArrayList<String> = ArrayList<String>()
    public let implicitFuncs: HashMap<String, String> = HashMap<String, String>()
    public let constVarInitFuncs: ArrayList<String> = ArrayList<String>()

    public init(name: String) {
        this.name = name
    }
}

public class CHIRContext {
    public let packages: ArrayList<CHIRPackage> = ArrayList<CHIRPackage>()
    public var threadNum: Int64 = 1
    public init() {}
}

public class CHIRData {
    private let context: CHIRContext = CHIRContext()
    private let chirPkgs: ArrayList<CHIRPackage> = ArrayList<CHIRPackage>()
    private var curCodegenPkg: Option<CHIRPackage> = None
    private let realContext: RealCHIRContext = RealCHIRContext()
    private let realChirPkgs: ArrayList<RealCHIRPackage> = ArrayList<RealCHIRPackage>()
    private var curRealCodegenPkg: Option<RealCHIRPackage> = None
    private let implicitFuncs: HashMap<String, String> = HashMap<String, String>()
    private let constVarInitFuncs: ArrayList<String> = ArrayList<String>()
    private let implicitFuncsPerPkg: HashMap<String, HashMap<String, String>> =
        HashMap<String, HashMap<String, String>>()
    private let constVarInitFuncsPerPkg: HashMap<String, ArrayList<String>> =
        HashMap<String, ArrayList<String>>()

    public init() {}

    public func InitData(fileNameMap: HashMap<UInt64, String>, threadNum: Int64): Unit {
        let _ = fileNameMap
        context.threadNum = threadNum
    }

    public func GetCHIRContext(): CHIRContext {
        return context
    }

    public func GetRealCHIRContext(): RealCHIRContext {
        return realContext
    }

    public func AppendNewPackage(pkg: CHIRPackage): Unit {
        chirPkgs.add(pkg)
        context.packages.add(pkg)
    }

    public func GetAllCHIRPackages(): ArrayList<CHIRPackage> {
        return chirPkgs
    }

    public func AppendNewRealPackage(pkg: RealCHIRPackage): Unit {
        realChirPkgs.add(pkg)
        if (let None <- curRealCodegenPkg) {
            curRealCodegenPkg = Some(pkg)
        }
    }

    public func ClearRealPackages(): Unit {
        realChirPkgs.clear()
        curRealCodegenPkg = None
    }

    public func GetAllRealCHIRPackages(): ArrayList<RealCHIRPackage> {
        return realChirPkgs
    }

    public func GetCurrentRealCHIRPackage(): Option<RealCHIRPackage> {
        if (let Some(pkg) <- curRealCodegenPkg) {
            return Some(pkg)
        }
        if (realChirPkgs.isEmpty()) {
            return None
        }
        return Some(realChirPkgs[0])
    }

    public func SetCurrentRealCHIRPackage(pkg: Option<RealCHIRPackage>): Unit {
        curRealCodegenPkg = pkg
    }

    public func GetCurrentCHIRPackage(): Option<CHIRPackage> {
        if (let Some(pkg) <- curCodegenPkg) {
            return Some(pkg)
        }
        if (chirPkgs.isEmpty()) {
            return None
        }
        return Some(chirPkgs[0])
    }

    public func SetCurrentCHIRPackage(pkg: Option<CHIRPackage>): Unit {
        curCodegenPkg = pkg
    }

    public func SetImplicitFuncs(pkg: CHIRPackage, funcs: HashMap<String, String>): Unit {
        implicitFuncs.clear()
        for ((key, value) in funcs) {
            implicitFuncs.add(key, value)
        }
        let copy = HashMap<String, String>()
        for ((key, value) in funcs) {
            copy.add(key, value)
        }
        if (implicitFuncsPerPkg.contains(pkg.name)) {
            implicitFuncsPerPkg.remove(pkg.name)
        }
        implicitFuncsPerPkg.add(pkg.name, copy)
    }

    public func GetImplicitFuncs(): HashMap<String, String> {
        return implicitFuncs
    }

    public func SetConstVarInitFuncs(pkg: CHIRPackage, funcs: ArrayList<String>): Unit {
        constVarInitFuncs.clear()
        for (funcName in funcs) {
            constVarInitFuncs.add(funcName)
        }
        let copy = ArrayList<String>()
        for (funcName in funcs) {
            copy.add(funcName)
        }
        if (constVarInitFuncsPerPkg.contains(pkg.name)) {
            constVarInitFuncsPerPkg.remove(pkg.name)
        }
        constVarInitFuncsPerPkg.add(pkg.name, copy)
    }

    public func GetConstVarInitFuncs(): ArrayList<String> {
        return constVarInitFuncs
    }

    public func ActivateCodegenFuncsForPackage(pkg: CHIRPackage): Unit {
        if (let Some(funcs) <- implicitFuncsPerPkg.get(pkg.name)) {
            implicitFuncs.clear()
            for ((key, value) in funcs) {
                implicitFuncs.add(key, value)
            }
        }
        if (let Some(funcs) <- constVarInitFuncsPerPkg.get(pkg.name)) {
            constVarInitFuncs.clear()
            for (funcName in funcs) {
                constVarInitFuncs.add(funcName)
            }
        }
    }

    public func FreeConstAnalysisWrapper(): Unit {
        ()
    }
}

public enum SrcCodeChangeState {
    | UNCHANGED
    | CHANGED
    | ADDED
    | DELETED
}

private func SrcCodeChangeStateIndex(state: SrcCodeChangeState): Int64 {
    return match (state) {
        case SrcCodeChangeState.UNCHANGED => 0
        case SrcCodeChangeState.CHANGED => 1
        case SrcCodeChangeState.ADDED => 2
        case SrcCodeChangeState.DELETED => 3
    }
}

extend SrcCodeChangeState <: Equatable<SrcCodeChangeState> {
    public operator func ==(rhs: SrcCodeChangeState): Bool {
        return SrcCodeChangeStateIndex(this) == SrcCodeChangeStateIndex(rhs)
    }

    public operator func !=(rhs: SrcCodeChangeState): Bool {
        return !(this == rhs)
    }
}

public class SrcCodeCacheInfo {
    public var state: SrcCodeChangeState = SrcCodeChangeState.ADDED
    public var code: String = ""

    public init() {}

    public init(code: String) {
        this.code = code
    }

    public init(state: SrcCodeChangeState, code: String) {
        this.state = state
        this.code = code
    }
}

public class TypeManager {
    public init() {}
    public func ReleasePostSemaCaches(): Unit {}
}

public class ImportedDeclGroup {
    public var name: String = ""
    public let decls: ArrayList<Decl> = ArrayList<Decl>()

    public init() {}

    public init(name: String, decls: ArrayList<Decl>) {
        this.name = name
        for (decl in decls) {
            this.decls.add(decl)
        }
    }
}

public class ImportManager {
    private let diag: DiagnosticEngine
    private let searchPath: ArrayList<String> = ArrayList<String>()
    private let importedPackages: ArrayList<Package> = ArrayList<Package>()
    private let depPkgCjdPaths: HashMap<String, String> = HashMap<String, String>()
    private let directDependencies: HashMap<String, HashSet<String>> = HashMap<String, HashSet<String>>()

    public init(diag: DiagnosticEngine) {
        this.diag = diag
    }

    public func UpdateSearchPath(cangjieModules: String): Unit {
        searchPath.clear()
        if (!cangjieModules.isEmpty()) {
            searchPath.add(cangjieModules)
        }
    }

    private func AppendSearchPath(path: String): Unit {
        let normalized = NormalizePath(path)
        if (normalized.isEmpty()) {
            return
        }
        for (entry in searchPath) {
            if (entry == normalized) {
                return
            }
        }
        searchPath.add(normalized)
    }

    public func GetSearchPath(): ArrayList<String> {
        return searchPath
    }

    public func GeneratePkgDepInfo(pkgs: ArrayList<Package>): ArrayList<String> {
        let out = ArrayList<String>()
        for (pkg in pkgs) {
            let deps = CollectDirectDependencyNames(pkg)
            out.add("{\"package\":\"" + EscapeJson(pkg.fullPackageName) + "\",\"deps\":" +
                StringSetToJsonArray(deps) + "}")
        }
        return out
    }

    public func GeneratePkgDepInfoByCjo(path: String): ArrayList<String> {
        let out = ArrayList<String>()
        out.add("{\"inputCjo\":\"" + EscapeJson(path) + "\",\"deps\":[]}")
        return out
    }

    public func BuildIndex(cangjieModules: String, opts: GlobalOptions, pkgs: ArrayList<Package>): Bool {
        UpdateSearchPath(cangjieModules)
        for (path in opts.importPaths) {
            AppendSearchPath(path)
        }
        depPkgCjdPaths.clear()
        directDependencies.clear()
        let sourcePackages = HashSet<String>()
        for (pkg in pkgs) {
            if (pkg.fullPackageName.isEmpty()) {
                diag.Diagnose(DiagCategory.IMPORT_PACKAGE, DEFAULT_POSITION, "empty package name")
                return false
            }
            AddImplicitImports(pkg, opts)
            sourcePackages.add(pkg.fullPackageName)
        }
        for (pkg in pkgs) {
            let deps = CollectDirectDependencyNames(pkg)
            let filteredDeps = HashSet<String>()
            for (dep in deps) {
                if (dep.isEmpty() || dep == pkg.fullPackageName) {
                    continue
                }
                filteredDeps.add(dep)
                if (!sourcePackages.contains(dep) && !depPkgCjdPaths.contains(dep)) {
                    let cjdPath = FileUtil.FindSerializationFile(dep, ".cjo", searchPath.toArray())
                    if (!cjdPath.isEmpty()) {
                        depPkgCjdPaths.add(dep, cjdPath)
                    }
                }
            }
            directDependencies.add(pkg.fullPackageName, filteredDeps)
        }
        return true
    }

    public func ReindexSourcePackagesAfterMacroExpand(pkgs: ArrayList<Package>): Unit {
        let _ = pkgs
    }

    public func DeleteASTLoaders(): Unit {}
    public func ClearPackageBCHIRCache(): Unit {}
    public func IsSourceCodeImported(): Bool { return true }

    public func GetAllImportedPackages(): ArrayList<Package> {
        return importedPackages
    }

    public func AddImportedPackage(pkg: Package): Unit {
        AddImportedPackageIfMissing(pkg)
    }

    public func GetDepPkgCjdPaths(): HashMap<String, String> {
        return depPkgCjdPaths
    }

    public func GetImportedDecls(file: File): ArrayList<ImportedDeclGroup> {
        let out = ArrayList<ImportedDeclGroup>()
        if (let Some(pkg) <- file.curPackage) {
            for (importSpec in file.imports) {
                CollectDeclsFromImport(pkg.fullPackageName, importSpec, out)
            }
        }
        return out
    }

    public func GetPackageMembers(srcFullPackageName: String, targetFullPackageName: String): HashMap<String, ArrayList<Decl>> {
        let out = HashMap<String, ArrayList<Decl>>()
        if (let Some(pkg) <- GetPackage(targetFullPackageName)) {
            for (file in pkg.files) {
                for (decl in file.decls) {
                    if (IsDeclVisibleFrom(srcFullPackageName, decl)) {
                        PutImportedDecl(out, decl.identifier.Val(), decl)
                    }
                }
            }
        }
        return out
    }

    public func GetCoreDecl(name: String): Option<Decl> {
        return GetImportedDecl("std.core", name)
    }

    public func GetAstDecl(name: String): Option<Decl> {
        return GetImportedDecl("std.ast", name)
    }

    private func GetImportedDecl(packageName: String, name: String): Option<Decl> {
        if (let Some(pkg) <- GetPackage(packageName)) {
            for (file in pkg.files) {
                for (decl in file.decls) {
                    if (decl.identifier.Val() == name) {
                        return Some(decl)
                    }
                }
            }
        }
        return None
    }

    private func CollectDeclsFromImport(srcFullPackageName: String, importSpec: ImportSpec,
        out: ArrayList<ImportedDeclGroup>): Unit {
        if (importSpec.IsImportMulti()) {
            return
        }
        let targetPackageName = if (importSpec.IsImportAll()) {
            importSpec.content.GetPrefixPath()
        } else {
            importSpec.content.GetImportedPackageName()
        }
        if (targetPackageName.isEmpty()) {
            return
        }
        if (let Some(pkg) <- GetPackage(targetPackageName)) {
            if (importSpec.IsImportAll()) {
                for (file in pkg.files) {
                    for (decl in file.decls) {
                        if (IsDeclVisibleFrom(srcFullPackageName, decl)) {
                            AddImportedDeclGroupValue(out, decl.identifier.Val(), decl)
                        }
                    }
                }
            } else if (IsPackageImport(importSpec, targetPackageName)) {
                let importedName = if (importSpec.IsImportAlias()) {
                    importSpec.content.aliasName.Val()
                } else {
                    LastPackageName(targetPackageName)
                }
                AddImportedDeclGroupValue(out, importedName, PackageDecl(pkg))
            } else {
                let importedName = if (importSpec.IsImportAlias()) {
                    importSpec.content.aliasName.Val()
                } else {
                    importSpec.content.identifier.Val()
                }
                for (file in pkg.files) {
                    for (decl in file.decls) {
                        if (decl.identifier.Val() == importSpec.content.identifier.Val() &&
                            IsDeclVisibleFrom(srcFullPackageName, decl)) {
                            AddImportedDeclGroupValue(out, importedName, decl)
                        }
                    }
                }
            }
        }
    }

    private func IsPackageImport(importSpec: ImportSpec, targetPackageName: String): Bool {
        if (importSpec.IsImportAll()) {
            return false
        }
        for (pkg in importedPackages) {
            if (pkg.fullPackageName == targetPackageName) {
                return true
            }
        }
        return false
    }

    private func IsDeclVisibleFrom(srcFullPackageName: String, decl: Decl): Bool {
        if (decl.TestAttr(Attribute.PUBLIC)) {
            return true
        }
        if (decl.fullPackageName == srcFullPackageName) {
            return true
        }
        if (decl.TestAttr(Attribute.INTERNAL)) {
            return RootPackageName(decl.fullPackageName) == RootPackageName(srcFullPackageName)
        }
        if (decl.TestAttr(Attribute.PROTECTED)) {
            return RootPackageName(decl.fullPackageName) == RootPackageName(srcFullPackageName)
        }
        return false
    }

    private func PutImportedDecl(map: HashMap<String, ArrayList<Decl>>, name: String, decl: Decl): Unit {
        if (!map.contains(name)) {
            map[name] = ArrayList<Decl>()
        }
        if (let Some(values) <- map.get(name)) {
            AddDeclIfMissing(values, decl)
        }
    }

    private func AddImportedDeclGroupValue(groups: ArrayList<ImportedDeclGroup>, name: String, decl: Decl): Unit {
        for (group in groups) {
            if (group.name == name) {
                AddDeclIfMissing(group.decls, decl)
                return
            }
        }
        let decls = ArrayList<Decl>()
        decls.add(decl)
        groups.add(ImportedDeclGroup(name, decls))
    }

    private func AddDeclIfMissing(values: ArrayList<Decl>, decl: Decl): Unit {
        for (value in values) {
            if (SameDecl(value, decl)) {
                return
            }
        }
        values.add(decl)
    }

    private func LastPackageName(fullPackageName: String): String {
        let parts = SplitQualifiedName(fullPackageName)
        if (parts.isEmpty()) {
            return fullPackageName
        }
        return parts[parts.size - 1]
    }

    private func RootPackageName(fullPackageName: String): String {
        let parts = SplitQualifiedName(fullPackageName)
        if (parts.isEmpty()) {
            return fullPackageName
        }
        return parts[0]
    }

    private func SplitQualifiedName(fullPackageName: String): ArrayList<String> {
        let out = ArrayList<String>()
        var start: Int64 = 0
        var idx: Int64 = 0
        while (idx <= fullPackageName.size) {
            if (idx == fullPackageName.size || fullPackageName[idx] == UInt8(46)) {
                if (idx > start) {
                    out.add(fullPackageName[start..idx])
                }
                start = idx + 1
            }
            idx++
        }
        return out
    }

    public func GetPackage(name: String): Option<Package> {
        for (pkg in importedPackages) {
            if (pkg.fullPackageName == name) {
                return Some(pkg)
            }
        }
        return None
    }

    private func AddImportedPackageIfMissing(pkg: Package): Unit {
        for (existing in importedPackages) {
            if (existing.fullPackageName == pkg.fullPackageName) {
                return
            }
        }
        importedPackages.add(pkg)
    }

    private func CollectDirectDependencyNames(pkg: Package): HashSet<String> {
        let deps = HashSet<String>()
        for (file in pkg.files) {
            for (importSpec in file.imports) {
                let depName = NormalizeImportedPackageName(importSpec.content)
                if (!depName.isEmpty() && depName != pkg.fullPackageName) {
                    deps.add(depName)
                }
            }
        }
        return deps
    }

    private func AddImplicitImports(pkg: Package, opts: GlobalOptions): Unit {
        if (!opts.implicitPrelude) {
            return
        }
        for (file in pkg.files) {
            AddImplicitImportAll(file, "std.core")
        }
    }

    private func AddImplicitImportAll(file: File, fullPackageName: String): Unit {
        for (importSpec in file.imports) {
            if (importSpec.TestAttr(Attribute.IMPLICIT_ADD) && importSpec.IsImportAll() &&
                importSpec.content.GetPrefixPath() == fullPackageName) {
                return
            }
        }
        let importSpec = CreateImportSpec(fullPackageName, "*", "")
        importSpec.curFile = Some(file)
        importSpec.content.curFile = Some(file)
        file.imports.add(importSpec)
    }

    private func NormalizeImportedPackageName(content: ImportContent): String {
        if (content.kind == ImportKind.IMPORT_ALL) {
            return content.GetPrefixPath()
        }
        return content.GetImportedPackageName()
    }
}

private func StringSetToJsonArray(values: HashSet<String>): String {
    let orderedValues = ArrayList<String>()
    for (value in values) {
        orderedValues.add(value)
    }
    sort(orderedValues, by: { left: String, right: String =>
        if (left < right) {
            Ordering.LT
        } else if (left > right) {
            Ordering.GT
        } else {
            Ordering.EQ
        }
    })
    let parts = ArrayList<String>()
    for (value in orderedValues) {
        parts.add("\"" + EscapeJson(value) + "\"")
    }
    return "[" + JoinStringList(parts, ",") + "]"
}

private func JoinStringList(values: ArrayList<String>, delimiter: String): String {
    let builder = StringBuilder()
    var idx: Int64 = 0
    while (idx < values.size) {
        if (idx > 0) {
            builder.append(delimiter)
        }
        builder.append(values[idx])
        idx++
    }
    return builder.toString()
}

public class PackageManager {
    private let importManager: ImportManager
    public init(importManager: ImportManager) {
        this.importManager = importManager
    }

    public func ResolveDependence(pkgs: ArrayList<Package>): Bool {
        let _ = importManager
        sort(pkgs, by: { left: Package, right: Package =>
            if (left.fullPackageName < right.fullPackageName) {
                Ordering.LT
            } else if (left.fullPackageName > right.fullPackageName) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        })
        return true
    }

    public func GetBuildOrders(pkgs: ArrayList<Package>): ArrayList<ArrayList<Package>> {
        let out = ArrayList<ArrayList<Package>>()
        for (pkg in pkgs) {
            let group = ArrayList<Package>()
            group.add(pkg)
            out.add(group)
        }
        return out
    }
}

public class TestManager {
    public init() {}
    public func MarkDeclsForTestIfNeeded(pkgs: ArrayList<Package>): Unit {
        let _ = pkgs
    }
}

public class GenericInstantiationManager {
    public init(instance: CompilerInstance) {
        let _ = instance
    }
}

public class BaseMangler {
    public var lambdaCounter: Int64 = 0
    public init() {}

    public func Mangle(decl: Decl, prefix!: String = ""): String {
        let pkgPrefix = if (decl.fullPackageName.isEmpty()) { "" } else { decl.fullPackageName + "." }
        return "_C" + (pkgPrefix + prefix + decl.identifier.Val()).replace(".", "_").replace("::", "_")
    }
}

public func EscapeJson(text: String): String {
    return text.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r")
}

public let DIR_SEPARATOR: String = "/"
