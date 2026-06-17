package cangjie_compiler::ast

import std.collection.*

public class FeatureId <: Node {
    public let identifiers: ArrayList<Identifier> = ArrayList<Identifier>()
    public let dotPoses: ArrayList<Position> = ArrayList<Position>()

    public init() {
        super(ASTKind.FEATURE_ID)
    }

    public override func ToString(): String {
        let builder = StringBuilder()
        var idx: Int64 = 0
        for (id in identifiers) {
            builder.append(id.Val())
            if (idx < dotPoses.size) {
                builder.append(".")
            }
            idx++
        }
        return builder.toString()
    }
}

public class FeaturesSet <: Node {
    public var lCurlPos: Position = INVALID_POSITION
    public let content: ArrayList<FeatureId> = ArrayList<FeatureId>()
    public let commaPoses: ArrayList<Position> = ArrayList<Position>()
    public var rCurlPos: Position = INVALID_POSITION

    public init() {
        super(ASTKind.FEATURES_SET)
    }
}

public class FeaturesDirective <: Node {
    public let annotations: ArrayList<Annotation> = ArrayList<Annotation>()
    public var featuresSet: Option<FeaturesSet> = None
    public var featuresPos: Position = INVALID_POSITION

    public init() {
        super(ASTKind.FEATURES_DIRECTIVE)
    }
}

public enum ImportKind {
    | IMPORT_SINGLE
    | IMPORT_ALIAS
    | IMPORT_ALL
    | IMPORT_MULTI
}

private func ImportKindIndex(kind: ImportKind): Int64 {
    return match (kind) {
        case ImportKind.IMPORT_SINGLE => 0
        case ImportKind.IMPORT_ALIAS => 1
        case ImportKind.IMPORT_ALL => 2
        case ImportKind.IMPORT_MULTI => 3
    }
}

extend ImportKind <: Equatable<ImportKind> {
    public operator func ==(right: ImportKind): Bool {
        return ImportKindIndex(this) == ImportKindIndex(right)
    }

    public operator func !=(right: ImportKind): Bool {
        return !(this == right)
    }
}

public class ImportContent <: Node {
    public var kind: ImportKind = ImportKind.IMPORT_SINGLE
    public var hasDoubleColon: Bool = false
    public let prefixPaths: ArrayList<String> = ArrayList<String>()
    public let prefixPoses: ArrayList<Position> = ArrayList<Position>()
    public let prefixDotPoses: ArrayList<Position> = ArrayList<Position>()
    public var identifier: Identifier = Identifier()
    public var asPos: Position = INVALID_POSITION
    public var aliasName: Identifier = Identifier()
    public var leftCurlPos: Position = INVALID_POSITION
    public let items: ArrayList<ImportContent> = ArrayList<ImportContent>()
    public let commaPoses: ArrayList<Position> = ArrayList<Position>()
    public var rightCurlPos: Position = INVALID_POSITION
    public var isDecl: Bool = false

    public init() {
        super(ASTKind.IMPORT_CONTENT)
    }

    public func GetPrefixPath(): String {
        let builder = StringBuilder()
        var idx: Int64 = 0
        while (idx < prefixPaths.size) {
            builder.append(prefixPaths[idx])
            if (idx == prefixPaths.size - 1) {
                break
            }
            if (idx == 0 && hasDoubleColon) {
                builder.append("::")
            } else {
                builder.append(".")
            }
            idx++
        }
        return builder.toString()
    }

    public func GetImportedPackageName(): String {
        let builder = StringBuilder()
        var idx: Int64 = 0
        while (idx < prefixPaths.size) {
            builder.append(prefixPaths[idx])
            if (kind == ImportKind.IMPORT_ALL && idx + 1 == prefixPaths.size) {
                idx++
                continue
            }
            if (idx == 0 && hasDoubleColon) {
                builder.append("::")
            } else {
                builder.append(".")
            }
            idx++
        }
        if (kind != ImportKind.IMPORT_ALL) {
            builder.append(identifier.Val())
        }
        return builder.toString()
    }

    public func GetImportedPackageNameWithIsDecl(): String {
        let builder = StringBuilder()
        var idx: Int64 = 0
        while (idx < prefixPaths.size) {
            builder.append(prefixPaths[idx])
            if (kind == ImportKind.IMPORT_ALL && idx + 1 == prefixPaths.size) {
                idx++
                continue
            }
            if (idx == 0 && hasDoubleColon) {
                builder.append("::")
            } else if (idx + 1 != prefixPaths.size) {
                builder.append(".")
            }
            idx++
        }
        if (kind != ImportKind.IMPORT_ALL && !isDecl) {
            if (!builder.toString().isEmpty()) {
                builder.append(".")
            }
            builder.append(identifier.Val())
        }
        return builder.toString()
    }

    public func GetPossiblePackageNames(): ArrayList<String> {
        let out = ArrayList<String>()
        if (prefixPaths.isEmpty()) {
            out.add(identifier.Val())
            return out
        }
        let builder = StringBuilder()
        var idx: Int64 = 0
        while (idx < prefixPaths.size) {
            builder.append(prefixPaths[idx])
            if (idx + 1 == prefixPaths.size) {
                break
            }
            if (idx == 0 && hasDoubleColon) {
                builder.append("::")
            } else {
                builder.append(".")
            }
            idx++
        }
        let prefix = builder.toString()
        if (kind == ImportKind.IMPORT_ALL) {
            out.add(prefix)
            return out
        }
        if (hasDoubleColon && prefixPaths.size == 1) {
            out.add(prefix + "::" + identifier.Val())
            return out
        }
        out.add(prefix + "." + identifier.Val())
        out.add(prefix)
        return out
    }

    public override func ToString(): String {
        let builder = StringBuilder()
        appendImportContentString(builder, this)
        if (kind != ImportKind.IMPORT_MULTI) {
            return builder.toString()
        }
        builder.append("{\n")
        for (item in items) {
            builder.append("    ")
            appendImportContentString(builder, item)
            builder.append("\n")
        }
        builder.append("}")
        return builder.toString()
    }
}

private func appendImportContentString(builder: StringBuilder, content: ImportContent): Unit {
    var idx: Int64 = 0
    while (idx < content.prefixPaths.size) {
        builder.append(content.prefixPaths[idx])
        if (idx == 0 && content.hasDoubleColon) {
            builder.append("::")
        } else {
            builder.append(".")
        }
        idx++
    }
    if (content.kind != ImportKind.IMPORT_MULTI) {
        builder.append(content.identifier.Val())
        if (content.kind == ImportKind.IMPORT_ALIAS) {
            builder.append(" as ")
            builder.append(content.aliasName.Val())
        }
    }
}

public class ImportSpec <: Node {
    public var modifier: Option<Modifier> = None
    public var importPos: Position = INVALID_POSITION
    public var content: ImportContent = ImportContent()
    public let annotations: ArrayList<Annotation> = ArrayList<Annotation>()
    public var withImplicitExport: Bool = true

    public init() {
        super(ASTKind.IMPORT_SPEC)
    }

    public func IsReExport(noSubPkg!: Bool = false): Bool {
        if (let Some(mod) <- modifier) {
            if (mod.modifier == TokenKind.PRIVATE) {
                return false
            }
            return if (noSubPkg) { mod.modifier != TokenKind.INTERNAL } else { true }
        }
        return false
    }

    public func IsImportAll(): Bool { return content.kind == ImportKind.IMPORT_ALL }
    public func IsImportSingle(): Bool { return content.kind == ImportKind.IMPORT_SINGLE }
    public func IsImportAlias(): Bool { return content.kind == ImportKind.IMPORT_ALIAS }
    public func IsImportMulti(): Bool { return content.kind == ImportKind.IMPORT_MULTI }

    public func IsPrivateImport(): Bool {
        if (let Some(mod) <- modifier) {
            return mod.modifier == TokenKind.PRIVATE
        }
        return true
    }

    public override func ToString(): String {
        let builder = StringBuilder()
        builder.append("import ")
        if (let Some(mod) <- modifier) {
            let modStr = mod.ToString()
            if (!modStr.isEmpty()) {
                builder.append(modStr)
                builder.append(" ")
            }
        }
        builder.append(content.ToString())
        return builder.toString()
    }
}

public class PackageSpec <: Node {
    public var modifier: Option<Modifier> = None
    public var macroPos: Position = INVALID_POSITION
    public var packagePos: Position = INVALID_POSITION
    public var hasDoubleColon: Bool = false
    public let prefixPaths: ArrayList<String> = ArrayList<String>()
    public let prefixPoses: ArrayList<Position> = ArrayList<Position>()
    public let prefixDotPoses: ArrayList<Position> = ArrayList<Position>()
    public var packageName: Identifier = Identifier()
    public var hasMacro: Bool = false
    public var hasSpecific: Bool = false
    public var hasCommon: Bool = false

    public init() {
        super(ASTKind.PACKAGE_SPEC)
    }

    public func GetPackageName(): String {
        let builder = StringBuilder()
        for (idx in 0..prefixPaths.size) {
            builder.append(prefixPaths[idx])
            builder.append(if (idx == 0 && hasDoubleColon) { "::" } else { "." })
        }
        builder.append(packageName.Val())
        return builder.toString()
    }

    public override func ToString(): String {
        return "package " + GetPackageName()
    }
}

public class File <: Node {
    public var fileName: String = ""
    public var filePath: String = ""
    public var fileHash: UInt64 = 0
    public var feature: Option<FeaturesDirective> = None
    public var packageSpec: Option<PackageSpec> = None
    public let imports: ArrayList<ImportSpec> = ArrayList<ImportSpec>()
    public let decls: ArrayList<Decl> = ArrayList<Decl>()
    public let trashBin: ArrayList<Node> = ArrayList<Node>()
    public var curPackage: Option<Package> = None
    public var indexOfPackage: UInt64 = 0
    public var hasMacro: Bool = false
    public var macroCallFilePath: String = ""
    public var macroCallPosBase: Position = Position(0, 1, 1)
    public let originalMacroCallNodes: ArrayList<Node> = ArrayList<Node>()
    public let exportedInternalDecls: ArrayList<Decl> = ArrayList<Decl>()
    public var isCommon: Bool = false
    public var isSpecific: Bool = false

    public init() {
        super(ASTKind.FILE)
    }

    public func GetFeatures(): ArrayList<String> {
        let out = ArrayList<String>()
        if (let Some(featureDirective) <- feature) {
            if (let Some(set) <- featureDirective.featuresSet) {
                for (featureId in set.content) {
                    out.add(featureId.ToString())
                }
            }
        }
        return out
    }

    public override func ToString(): String {
        let builder = StringBuilder()
        if (let Some(spec) <- packageSpec) {
            builder.append(spec.ToString())
            builder.append("\n")
        }
        for (importSpec in imports) {
            builder.append(importSpec.ToString())
            builder.append("\n")
        }
        for (decl in decls) {
            builder.append(decl.ToString())
            builder.append("\n")
        }
        return builder.toString()
    }
}

public enum AccessLevel {
    | PRIVATE
    | INTERNAL
    | PROTECTED
    | PUBLIC
}

public class Package <: Node {
    public var fullPackageName: String = "default"
    public let files: ArrayList<File> = ArrayList<File>()
    public let genericInstantiatedDecls: ArrayList<Decl> = ArrayList<Decl>()
    public let srcImportedNonGenericDecls: ArrayList<Decl> = ArrayList<Decl>()
    public let inlineFuncDecls: ArrayList<FuncDecl> = ArrayList<FuncDecl>()
    public var accessible: AccessLevel = AccessLevel.PUBLIC
    public var hasSourceImportedDecl: Bool = false
    public var isMacroPackage: Bool = false
    public var noSubPkg: Bool = false
    public var needExported: Bool = true
    public var interopCJApiStrategy: InteropCJStrategy = InteropCJStrategy.NONE
    public var interopCJGenericTypeStrategy: InteropCJGenericStrategyType = InteropCJGenericStrategyType.NONE
    public let interopCJIncludedApis: ArrayList<String> = ArrayList<String>()
    public let interopCJExcludedApis: ArrayList<String> = ArrayList<String>()
    public let interopTuples: ArrayList<String> = ArrayList<String>()
    public var isInteropCJPackageConfig: Bool = false
    public let lambdaPatterns: ArrayList<LambdaPattern> = ArrayList<LambdaPattern>()
    private let allDependentStdPkgs: ArrayList<String> = ArrayList<String>()

    public init() {
        super(ASTKind.PACKAGE)
    }

    public init(pkgName: String) {
        super(ASTKind.PACKAGE)
        fullPackageName = pkgName
    }

    public func IsEmpty(): Bool {
        for (file in files) {
            if (let Some(_) <- file.packageSpec) {
                return false
            }
            if (!file.decls.isEmpty()) {
                return false
            }
            for (importSpec in file.imports) {
                if (!importSpec.TestAttr(Attribute.COMPILER_ADD)) {
                    return false
                }
            }
        }
        return true
    }

    public func HasFtrDirective(): Bool {
        for (file in files) {
            if (let Some(_) <- file.feature) {
                return true
            }
        }
        return false
    }

    public func AddDependentStdPkg(pkgName: String): Unit {
        allDependentStdPkgs.add(pkgName)
    }

    public func ClearAllDependentStdPkgs(): Unit {
        allDependentStdPkgs.clear()
    }

    public func GetAllDependentStdPkgs(): ArrayList<String> {
        return allDependentStdPkgs
    }

    public func GetLambdaPatterns(): ArrayList<LambdaPattern> {
        return lambdaPatterns
    }

    public override func ToString(): String {
        let builder = StringBuilder()
        for (file in files) {
            builder.append(file.ToString())
        }
        return builder.toString()
    }
}

public class PackageDecl <: Decl {
    public var srcPackage: Package = Package()

    public init(pkg: Package) {
        super(ASTKind.PACKAGE_DECL)
        srcPackage = pkg
        identifier = SrcIdentifier(pkg.fullPackageName, INVALID_POSITION, INVALID_POSITION, false)
        fullPackageName = pkg.fullPackageName
        if (pkg.TestAttr(Attribute.IMPORTED)) {
            EnableAttr(Attribute.IMPORTED)
        }
    }

    public override func ToString(): String {
        return fullPackageName
    }
}
