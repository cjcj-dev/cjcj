package cangjie_compiler::modules

import std.collection.*
import std.convert.*

public class ASTWriter {
    private let diag: DiagnosticEngine
    private var packageDepInfo: String
    private let exportCfg: ExportConfig
    private let cjoManager: CjoManager
    private var serializingCommon: Bool = false
    private var debugOption: Bool = false
    private var optimizationLevel: OptimizationLevel = OptimizationLevel.O0
    private var isChirNow: Bool = false
    private var savedPackage: Option<PackageDecl> = None

    public init(diag: DiagnosticEngine, packageDepInfo: String, exportCfg: ExportConfig, cjoManager: CjoManager) {
        this.diag = diag
        this.packageDepInfo = packageDepInfo
        this.exportCfg = exportCfg
        this.cjoManager = cjoManager
    }

    public func SetSerializingCommon(): Unit {
        serializingCommon = true
    }

    public func SaveOptions(debug: Bool, level: OptimizationLevel): Unit {
        debugOption = debug
        optimizationLevel = level
    }

    public func ExportAST(pkgDecl: PackageDecl): Unit {
        savedPackage = Some(pkgDecl)
    }

    public func PreSaveFullExportDecls(pkg: Package): Unit {
        for (file in pkg.files) {
            for (decl in file.decls) {
                if (decl.fullPackageName.isEmpty()) {
                    decl.fullPackageName = pkg.fullPackageName
                }
            }
        }
    }

    public func AST2FB(data: ArrayList<UInt8>, pkgDecl: PackageDecl): Unit {
        let serialized = SerializePackage(pkgDecl.srcPackage)
        data.clear()
        for (byte in serialized.toArray()) {
            data.add(byte)
        }
    }

    public func SaveType(pType: String): FormattedIndex {
        // TODO(selfhost:Modules): bind to the real AST Ty graph once the modules package can depend on AST/Sema.
        return UInt64(pType.hashCode())
    }

    public func SetIsChirNow(isChirNow!: Bool = false): Unit {
        this.isChirNow = isChirNow
    }

    public func SerializePackage(pkg: Package): String {
        let lines = ArrayList<String>()
        lines.add("CANGJIE-MODULES-AST|1")
        lines.add("dep|" + EncodeField(packageDepInfo))
        let packageFields = ArrayList<String>()
        packageFields.add("package")
        packageFields.add(pkg.fullPackageName)
        packageFields.add(BoolToWire(pkg.isMacroPackage))
        packageFields.add(AccessLevelToWire(pkg.accessible))
        packageFields.add(BoolToWire(serializingCommon))
        packageFields.add(BoolToWire(debugOption))
        packageFields.add(OptimizationLevelToString(optimizationLevel))
        lines.add(JoinFields(packageFields))
        for (file in pkg.files) {
            let fileFields = ArrayList<String>()
            fileFields.add("file")
            fileFields.add(file.fileName)
            fileFields.add(file.filePath)
            fileFields.add(file.fileHash.toString())
            fileFields.add(JoinStringList(file.features))
            fileFields.add(BoolToWire(file.isProduct))
            lines.add(JoinFields(fileFields))
            for (importSpec in file.imports) {
                let importFields = ArrayList<String>()
                importFields.add("import")
                importFields.add(ImportKindToWire(importSpec.content.kind))
                importFields.add(JoinStringList(importSpec.content.prefixPaths))
                importFields.add(importSpec.content.identifier)
                importFields.add(importSpec.content.aliasName)
                importFields.add(BoolToWire(importSpec.content.hasDoubleColon))
                importFields.add(BoolToWire(importSpec.content.isDecl))
                importFields.add(AccessLevelToWire(importSpec.accessLevel))
                importFields.add(BoolToWire(importSpec.hasAccessModifier))
                importFields.add(BoolToWire(importSpec.withImplicitExport))
                lines.add(JoinFields(importFields))
            }
            for (decl in file.decls) {
                let declFields = ArrayList<String>()
                declFields.add("decl")
                declFields.add(decl.identifier)
                declFields.add(decl.fullPackageName)
                declFields.add(AccessLevelToWire(GetAccessLevel(decl)))
                declFields.add(BoolToWire(decl.doNotExport))
                declFields.add(BoolToWire(decl.isFunction))
                lines.add(JoinFields(declFields))
            }
        }
        return JoinStrings(lines, "\n") + "\n"
    }
}

public class ASTLoader {
    private let data: Array<UInt8>
    private let requestedPackageName: String
    private let cjoManager: CjoManager
    private let opts: GlobalOptions
    private var parsedPackage: Option<Package> = None
    private var packageDepInfo: String = ""
    private var importSourceCode: Bool = true
    private var isChirNow: Bool = false

    public init(data: Array<UInt8>, fullPackageName: String, cjoManager: CjoManager, opts: GlobalOptions) {
        this.data = data
        requestedPackageName = fullPackageName
        this.cjoManager = cjoManager
        this.opts = opts
    }

    public func LoadPackageDependencies(): Option<Package> {
        if (let Some(pkg) <- parsedPackage) {
            return Some(pkg)
        }
        let text = String.fromUtf8(data)
        let pkgOpt = ParseSerializedPackage(text)
        if (let Some(pkg) <- pkgOpt) {
            parsedPackage = Some(pkg)
            return Some(pkg)
        }
        return None
    }

    public func LoadPackageDecls(): Unit {
        let _ = LoadPackageDependencies()
    }

    public func LoadCachedTypeForPackage(
        sourcePackage: Package,
        mangledName2DeclMap: HashMap<String, Decl>
    ): HashSet<String> {
        let _ = sourcePackage
        let _ = mangledName2DeclMap
        // TODO(selfhost:Modules): deserialize cached type and mangle removal records from the real flatbuffer format.
        return HashSet<String>()
    }

    public func LoadPackageDepInfo(): String {
        let _ = LoadPackageDependencies()
        return packageDepInfo
    }

    public func LoadRefs(): Unit {
        // TODO(selfhost:Modules): resolve serialized declaration/type references after AST/Sema package integration.
    }

    public func GetImportedPackageName(): String {
        if (let Some(pkg) <- LoadPackageDependencies()) {
            return pkg.fullPackageName
        }
        return requestedPackageName
    }

    public func SetImportSourceCode(enable: Bool): Unit {
        importSourceCode = enable
    }

    public func GetDependentPackageNames(): ArrayList<String> {
        let out = ArrayList<String>()
        if (let Some(pkg) <- LoadPackageDependencies()) {
            for (file in pkg.files) {
                for (importSpec in file.imports) {
                    let name = importSpec.content.GetImportedPackageName()
                    if (!name.isEmpty() && !out.contains(name)) {
                        out.add(name)
                    }
                }
            }
        }
        return out
    }

    public func PreloadCommonPartOfPackage(pkg: Package): Bool {
        if (let Some(commonPkg) <- LoadPackageDependencies()) {
            if (commonPkg.fullPackageName != pkg.fullPackageName) {
                return false
            }
            for (file in commonPkg.files) {
                file.EnableAttr(Attribute.FROM_COMMON_PART)
                pkg.AddFile(file)
            }
        }
        return true
    }

    public func ReadFileNames(): ArrayList<String> {
        let out = ArrayList<String>()
        if (let Some(pkg) <- LoadPackageDependencies()) {
            for (file in pkg.files) {
                out.add(file.fileName)
            }
        }
        return out
    }

    public func LoadType(typeIndex: FormattedIndex): String {
        // TODO(selfhost:Modules): return real AST Ty once type serialization is wired.
        return typeIndex.toString()
    }

    public func SetIsChirNow(isChirNow!: Bool = false): Unit {
        this.isChirNow = isChirNow
    }

    private func ParseSerializedPackage(text: String): Option<Package> {
        let rawLines = SplitRawLines(text)
        if (rawLines.isEmpty() || rawLines[0] != "CANGJIE-MODULES-AST|1") {
            return None
        }
        var pkg = Package(requestedPackageName)
        var currentFile: Option<File> = None
        for (line in rawLines) {
            if (line.isEmpty() || line == "CANGJIE-MODULES-AST|1") {
                continue
            }
            let fields = SplitFields(line)
            if (fields.isEmpty()) {
                continue
            }
            match (fields[0]) {
                case "dep" =>
                    if (fields.size > 1) {
                        packageDepInfo = fields[1]
                    }
                case "package" =>
                    if (fields.size > 3) {
                        pkg = Package(fields[1])
                        pkg.isMacroPackage = WireToBool(fields[2])
                        pkg.accessible = WireToAccessLevel(fields[3])
                    }
                case "file" =>
                    let file = File()
                    if (fields.size > 1) { file.fileName = fields[1] }
                    if (fields.size > 2) { file.filePath = fields[2] }
                    if (fields.size > 3) {
                        try {
                            file.fileHash = UInt64.parse(fields[3])
                        } catch (e: Exception) {
                            file.fileHash = UInt64(file.filePath.hashCode())
                        }
                    }
                    if (fields.size > 4) {
                        for (feature in SplitStringList(fields[4])) {
                            file.features.add(feature)
                        }
                    }
                    if (fields.size > 5) { file.isProduct = WireToBool(fields[5]) }
                    pkg.AddFile(file)
                    currentFile = Some(file)
                case "import" =>
                    if (let Some(file) <- currentFile) {
                        let importSpec = ImportSpec()
                        if (fields.size > 1) { importSpec.content.kind = WireToImportKind(fields[1]) }
                        if (fields.size > 2) {
                            for (part in SplitStringList(fields[2])) {
                                importSpec.content.prefixPaths.add(part)
                            }
                        }
                        if (fields.size > 3) { importSpec.content.identifier = fields[3] }
                        if (fields.size > 4) { importSpec.content.aliasName = fields[4] }
                        if (fields.size > 5) { importSpec.content.hasDoubleColon = WireToBool(fields[5]) }
                        if (fields.size > 6) { importSpec.content.isDecl = WireToBool(fields[6]) }
                        if (fields.size > 7) { importSpec.accessLevel = WireToAccessLevel(fields[7]) }
                        if (fields.size > 8) { importSpec.hasAccessModifier = WireToBool(fields[8]) }
                        if (fields.size > 9) { importSpec.withImplicitExport = WireToBool(fields[9]) }
                        importSpec.curFile = Some(file)
                        importSpec.content.curFile = Some(file)
                        file.imports.add(importSpec)
                    }
                case "decl" =>
                    if (let Some(file) <- currentFile) {
                        let decl = Decl()
                        if (fields.size > 1) { decl.identifier = fields[1] }
                        if (fields.size > 2) { decl.fullPackageName = fields[2] }
                        if (fields.size > 3) {
                            match (WireToAccessLevel(fields[3])) {
                                case AccessLevel.PUBLIC => decl.EnableAttr(Attribute.PUBLIC)
                                case AccessLevel.PRIVATE => decl.EnableAttr(Attribute.PRIVATE)
                                case AccessLevel.PROTECTED => decl.EnableAttr(Attribute.PROTECTED)
                                case AccessLevel.INTERNAL => decl.EnableAttr(Attribute.INTERNAL)
                            }
                        }
                        if (fields.size > 4) { decl.doNotExport = WireToBool(fields[4]) }
                        if (fields.size > 5) { decl.isFunction = WireToBool(fields[5]) }
                        decl.curFile = Some(file)
                        file.decls.add(decl)
                    }
                case _ => ()
            }
        }
        return Some(pkg)
    }
}

public func SplitRawLines(text: String): ArrayList<String> {
    let out = ArrayList<String>()
    let bytes = text.toArray()
    var start: Int64 = 0
    var idx: Int64 = 0
    while (idx < bytes.size) {
        if (bytes[idx] == b'\n') {
            let end = if (idx > start && bytes[idx - 1] == b'\r') { idx - 1 } else { idx }
            out.add(String.fromUtf8(bytes[start..end]))
            start = idx + 1
        }
        idx++
    }
    if (start < bytes.size) {
        out.add(String.fromUtf8(bytes[start..]))
    }
    return out
}
