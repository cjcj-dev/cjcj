package cangjie_compiler::modules

import std.collection.*
import std.convert.*
import cangjie_compiler::option.GlobalOptions
import cangjie_compiler::option.OptimizationLevel

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
    private let savedTypeMap: HashMap<String, FormattedIndex> = HashMap<String, FormattedIndex>()
    private let savedTypes: ArrayList<String> = ArrayList<String>()

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
        if (pType.isEmpty()) {
            return INVALID_FORMAT_INDEX
        }
        if (let Some(existing) <- savedTypeMap.get(pType)) {
            return existing
        }
        let nextIndex = UInt64(savedTypes.size + 1)
        savedTypes.add(pType)
        savedTypeMap[pType] = nextIndex
        return nextIndex
    }

    public func SetIsChirNow(isChirNow!: Bool = false): Unit {
        this.isChirNow = isChirNow
    }

    public func SerializePackage(pkg: Package): String {
        let lines = ArrayList<String>()
        lines.add("CANGJIE-MODULES-AST|1")
        lines.add("dep|" + EncodeField(packageDepInfo))
        var typeIdx: Int64 = 0
        while (typeIdx < savedTypes.size) {
            let typeFields = ArrayList<String>()
            typeFields.add("type")
            typeFields.add((typeIdx + 1).toString())
            typeFields.add(savedTypes[typeIdx])
            lines.add(JoinFields(typeFields))
            typeIdx++
        }
        let packageFields = ArrayList<String>()
        packageFields.add("package")
        packageFields.add(pkg.fullPackageName)
        packageFields.add(BoolToWire(pkg.isMacroPackage))
        packageFields.add(AccessLevelToWire(pkg.accessible))
        packageFields.add(BoolToWire(serializingCommon))
        packageFields.add(BoolToWire(debugOption))
        packageFields.add(OptimizationLevelToString(optimizationLevel))
        AppendNodeFields(packageFields, pkg)
        lines.add(JoinFields(packageFields))
        for (file in pkg.files) {
            let fileFields = ArrayList<String>()
            fileFields.add("file")
            fileFields.add(file.fileName)
            fileFields.add(file.filePath)
            fileFields.add(file.fileHash.toString())
            fileFields.add(JoinStringList(file.features))
            fileFields.add(BoolToWire(file.isProduct))
            AppendNodeFields(fileFields, file)
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
                AppendNodeFields(importFields, importSpec)
                AppendNodeFields(importFields, importSpec.content)
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
                declFields.add(decl.rawMangleName)
                declFields.add(decl.mangledName)
                declFields.add(decl.begin.fileID.toString())
                declFields.add(decl.begin.line.toString())
                declFields.add(decl.begin.column.toString())
                declFields.add(decl.end.fileID.toString())
                declFields.add(decl.end.line.toString())
                declFields.add(decl.end.column.toString())
                declFields.add(JoinAttributes(decl.GetAttrs()))
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
    private var loadedHasOptions: Bool = false
    private var loadedSerializingCommon: Bool = false
    private var loadedDebugOption: Bool = false
    private var loadedOptimizationLevel: OptimizationLevel = OptimizationLevel.O0
    private let loadedTypes: HashMap<FormattedIndex, String> = HashMap<FormattedIndex, String>()

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
        let removedMangles = HashSet<String>()
        let cachedPkgOpt = LoadPackageDependencies()
        if (let None <- cachedPkgOpt) {
            return removedMangles
        }
        let cachedPkg = cachedPkgOpt.getOrThrow()
        if (cachedPkg.fullPackageName != sourcePackage.fullPackageName) {
            return removedMangles
        }
        for (file in cachedPkg.files) {
            for (decl in file.decls) {
                let mangleName = GetDeclMangleKey(decl)
                if (!mangleName.isEmpty() && !mangledName2DeclMap.contains(mangleName)) {
                    removedMangles.add(mangleName)
                }
            }
        }
        return removedMangles
    }

    public func LoadPackageDepInfo(): String {
        let _ = LoadPackageDependencies()
        return packageDepInfo
    }

    public func LoadRefs(): Unit {
        if (let Some(pkg) <- LoadPackageDependencies()) {
            for (file in pkg.files) {
                for (importSpec in file.imports) {
                    let pair = cjoManager.GetPackageCjo(importSpec)
                    let fullDepName = pair[0]
                    let cjoPath = pair[1]
                    if (!fullDepName.isEmpty() && cjoManager.GetPackage(fullDepName).isNone()) {
                        let _ = cjoManager.LoadPackageHeader(fullDepName, cjoPath)
                    }
                }
            }
            cjoManager.AddPackageDeclMap(pkg.fullPackageName)
        }
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
                    var depName = cjoManager.GetPackageNameByImport(importSpec)
                    if (depName.isEmpty()) {
                        let pair = cjoManager.GetPackageCjo(importSpec)
                        depName = pair[0]
                    }
                    if (!depName.isEmpty() && !out.contains(depName)) {
                        out.add(depName)
                    }
                }
            }
        }
        return out
    }

    public func PreloadCommonPartOfPackage(pkg: Package): Bool {
        if (let Some(commonPkg) <- LoadPackageDependencies()) {
            if (commonPkg.fullPackageName != pkg.fullPackageName) {
                cjoManager.GetDiag().ReportError(
                    "module_common_cjo_wrong_package",
                    "common cjo package '${commonPkg.fullPackageName}' does not match expected '${pkg.fullPackageName}'"
                )
                return false
            }
            ValidateCommonSpecificFeatureSetsRelations(commonPkg, pkg)
            for (file in commonPkg.files) {
                file.EnableAttr(Attribute.FROM_COMMON_PART)
                pkg.AddFile(file)
            }
            if (!ValidateCommonPartOptions()) {
                return false
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
        if (typeIndex == INVALID_FORMAT_INDEX) {
            return ""
        }
        if (let Some(typeText) <- loadedTypes.get(typeIndex)) {
            return typeText
        }
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
                case "type" =>
                    if (fields.size > 2) {
                        loadedTypes[ParseFormattedIndex(fields[1])] = fields[2]
                    }
                case "package" =>
                    if (fields.size > 3) {
                        pkg = Package(fields[1])
                        pkg.isMacroPackage = WireToBool(fields[2])
                        pkg.accessible = WireToAccessLevel(fields[3])
                        if (fields.size > 6) {
                            loadedHasOptions = true
                            loadedSerializingCommon = WireToBool(fields[4])
                            loadedDebugOption = WireToBool(fields[5])
                            loadedOptimizationLevel = WireToOptimizationLevel(fields[6])
                        }
                        if (fields.size > 13) {
                            LoadNodeFields(fields, 7, pkg)
                        }
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
                    if (fields.size > 12) {
                        LoadNodeFields(fields, 6, file)
                    }
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
                        ApplyAccessAttr(importSpec, importSpec.accessLevel)
                        if (fields.size > 16) {
                            LoadNodeFields(fields, 10, importSpec)
                        }
                        if (fields.size > 23) {
                            LoadNodeFields(fields, 17, importSpec.content)
                        }
                        if (!HasAccessAttr(importSpec)) {
                            ApplyAccessAttr(importSpec, importSpec.accessLevel)
                        }
                        importSpec.curFile = Some(file)
                        importSpec.content.curFile = Some(file)
                        file.imports.add(importSpec)
                    }
                case "decl" =>
                    if (let Some(file) <- currentFile) {
                        let decl = Decl()
                        if (fields.size > 1) { decl.identifier = fields[1] }
                        if (fields.size > 2) { decl.fullPackageName = fields[2] }
                        var declAccessLevel = AccessLevel.INTERNAL
                        if (fields.size > 3) {
                            declAccessLevel = WireToAccessLevel(fields[3])
                            ApplyAccessAttr(decl, declAccessLevel)
                        }
                        if (fields.size > 4) { decl.doNotExport = WireToBool(fields[4]) }
                        if (fields.size > 5) { decl.isFunction = WireToBool(fields[5]) }
                        if (fields.size > 6) { decl.rawMangleName = fields[6] }
                        if (fields.size > 7) { decl.mangledName = fields[7] }
                        if (fields.size > 13) {
                            decl.begin = Position(
                                ParseUInt64Field(fields[8]),
                                ParseInt64Field(fields[9]),
                                ParseInt64Field(fields[10])
                            )
                            decl.end = Position(
                                ParseUInt64Field(fields[11]),
                                ParseInt64Field(fields[12]),
                                ParseInt64Field(fields[13])
                            )
                        }
                        if (fields.size > 14) {
                            decl.ReplaceAttrs(SplitAttributes(fields[14]))
                        }
                        if (!HasAccessAttr(decl)) {
                            ApplyAccessAttr(decl, declAccessLevel)
                        }
                        decl.curFile = Some(file)
                        file.decls.add(decl)
                    }
                case _ => ()
            }
        }
        return Some(pkg)
    }

    private func ValidateCommonSpecificFeatureSetsRelations(commonPkg: Package, specificPkg: Package): Unit {
        let specificFeatures = CollectFeaturesFromPackage(specificPkg)
        for (commonFile in commonPkg.files) {
            let extraFeatures = ArrayList<String>()
            for (feature in CollectUniqueStrings(commonFile.features)) {
                if (!specificFeatures.contains(feature)) {
                    extraFeatures.add("'${feature}'")
                }
            }
            if (!extraFeatures.isEmpty()) {
                cjoManager.GetDiag().ReportError(
                    "feature_is_not_subset_of_child_set",
                    "extra feature from common part file '${commonFile.filePath}': " +
                        JoinStrings(extraFeatures, " "),
                    range: MakeRange(commonFile.begin, commonFile.end)
                )
            }
        }
    }

    private func ValidateCommonPartOptions(): Bool {
        if (!loadedHasOptions) {
            cjoManager.GetDiag().ReportWarning(
                "module_common_cjo_no_options",
                "common cjo does not contain compilation options"
            )
            return true
        }
        var ok = true
        if (loadedDebugOption != opts.enableCompileDebug) {
            let before = if (loadedDebugOption) { "enabled" } else { "disabled" }
            let after = if (opts.enableCompileDebug) { "enabled" } else { "disabled" }
            cjoManager.GetDiag().ReportError(
                "module_common_cjo_debug_mismatch",
                "common cjo compile debug was ${before}, current compile debug is ${after}"
            )
            ok = false
        }
        if (loadedOptimizationLevel != opts.optimizationLevel) {
            cjoManager.GetDiag().ReportError(
                "module_common_cjo_opt_mismatch",
                "common cjo optimization level was ${OptimizationLevelToString(loadedOptimizationLevel)}, " +
                    "current optimization level is ${OptimizationLevelToString(opts.optimizationLevel)}"
            )
            ok = false
        }
        return ok
    }

    private func CollectFeaturesFromPackage(pkg: Package): TreeSet<String> {
        let features = TreeSet<String>()
        if (!pkg.files.isEmpty()) {
            for (feature in pkg.files[0].features) {
                features.add(feature)
            }
        }
        return features
    }

    private func CollectUniqueStrings(values: ArrayList<String>): TreeSet<String> {
        let out = TreeSet<String>()
        for (value in values) {
            out.add(value)
        }
        return out
    }
}

public func ParseFormattedIndex(value: String): FormattedIndex {
    return ParseUInt64Field(value)
}

public func ParseUInt64Field(value: String): UInt64 {
    try {
        return UInt64.parse(value)
    } catch (e: Exception) {
        return 0u64
    }
}

public func ParseInt64Field(value: String): Int64 {
    try {
        return Int64.parse(value)
    } catch (e: Exception) {
        return 0
    }
}

public func GetDeclMangleKey(decl: Decl): String {
    if (!decl.mangledName.isEmpty()) {
        return decl.mangledName
    }
    if (!decl.rawMangleName.isEmpty()) {
        return decl.rawMangleName
    }
    if (!decl.fullPackageName.isEmpty() && !decl.identifier.isEmpty()) {
        return decl.fullPackageName + "." + decl.identifier
    }
    return decl.identifier
}

public func AppendNodeFields(fields: ArrayList<String>, node: Node): Unit {
    fields.add(node.begin.fileID.toString())
    fields.add(node.begin.line.toString())
    fields.add(node.begin.column.toString())
    fields.add(node.end.fileID.toString())
    fields.add(node.end.line.toString())
    fields.add(node.end.column.toString())
    fields.add(JoinAttributes(node.GetAttrs()))
}

public func LoadNodeFields(fields: ArrayList<String>, start: Int64, node: Node): Unit {
    if (fields.size > start + 5) {
        node.begin = Position(
            ParseUInt64Field(fields[start]),
            ParseInt64Field(fields[start + 1]),
            ParseInt64Field(fields[start + 2])
        )
        node.end = Position(
            ParseUInt64Field(fields[start + 3]),
            ParseInt64Field(fields[start + 4]),
            ParseInt64Field(fields[start + 5])
        )
    }
    if (fields.size > start + 6) {
        node.ReplaceAttrs(SplitAttributes(fields[start + 6]))
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
