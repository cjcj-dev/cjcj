package cangjie_compiler::parse

import std.collection.*

public enum ImportKind {
    | IMPORT_SINGLE | IMPORT_ALIAS | IMPORT_ALL | IMPORT_MULTI
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
    public operator func ==(right: ImportKind): Bool { return ImportKindIndex(this) == ImportKindIndex(right) }
    public operator func !=(right: ImportKind): Bool { return !(this == right) }
}

public class ImportContent <: Node {
    public var kind: ImportKind = ImportKind.IMPORT_SINGLE
    public var hasDoubleColon: Bool = false
    public let prefixPaths: ArrayList<SrcIdentifier> = ArrayList<SrcIdentifier>()
    public let prefixDotPoses: ArrayList<Position> = ArrayList<Position>()
    public var identifier: SrcIdentifier = SrcIdentifier()
    public var asPos: Position = INVALID_POSITION
    public var aliasName: SrcIdentifier = SrcIdentifier()
    public var leftCurlPos: Position = INVALID_POSITION
    public let items: ArrayList<ImportContent> = ArrayList<ImportContent>()
    public let commaPoses: ArrayList<Position> = ArrayList<Position>()
    public var rightCurlPos: Position = INVALID_POSITION
    public var isDecl: Bool = false
    public var hasBroken: Bool = false

    public init() { super(ASTKind.IMPORT_CONTENT) }

    public func MarkBroken(): Unit {
        isBroken = true
    }

    public func MarkHasBroken(): Unit {
        hasBroken = true
        isBroken = true
    }

    public func IsImportMulti(): Bool {
        return kind == ImportKind.IMPORT_MULTI
    }

    public func IsImportAll(): Bool {
        return kind == ImportKind.IMPORT_ALL
    }

    public func IsImportAlias(): Bool {
        return kind == ImportKind.IMPORT_ALIAS
    }

    public func GetPrefixPath(): String {
        let builder = StringBuilder()
        var index: Int64 = 0
        while (index < prefixPaths.size) {
            builder.append(prefixPaths[index].Val())
            if (index == prefixPaths.size - 1) {
                break
            }
            if (index == 0 && hasDoubleColon) {
                builder.append("::")
            } else {
                builder.append(".")
            }
            index++
        }
        return builder.toString()
    }

    public func GetImportedPackageName(): String {
        let builder = StringBuilder()
        var index: Int64 = 0
        while (index < prefixPaths.size) {
            builder.append(prefixPaths[index].Val())
            if (kind == ImportKind.IMPORT_ALL && index + 1 == prefixPaths.size) {
                index++
                continue
            }
            if (index == 0 && hasDoubleColon) {
                builder.append("::")
            } else {
                builder.append(".")
            }
            index++
        }
        if (kind != ImportKind.IMPORT_ALL) {
            builder.append(identifier.Val())
        }
        return builder.toString()
    }

    public func GetImportedPackageNameWithIsDecl(): String {
        let builder = StringBuilder()
        var index: Int64 = 0
        while (index < prefixPaths.size) {
            builder.append(prefixPaths[index].Val())
            if (kind == ImportKind.IMPORT_ALL && index + 1 == prefixPaths.size) {
                index++
                continue
            }
            if (index == 0 && hasDoubleColon) {
                builder.append("::")
            } else if (index + 1 != prefixPaths.size) {
                builder.append(".")
            }
            index++
        }
        if (kind != ImportKind.IMPORT_ALL && !isDecl) {
            if (!builder.toString().isEmpty()) {
                builder.append(".")
            }
            builder.append(identifier.Val())
        }
        return builder.toString()
    }

    public func FullName(): String {
        if (kind != ImportKind.IMPORT_MULTI) {
            return GetImportedPackageName()
        }
        let builder = StringBuilder()
        builder.append(GetPrefixPath())
        if (!prefixPaths.isEmpty()) {
            if (hasDoubleColon && prefixPaths.size == 1) {
                builder.append("::")
            } else {
                builder.append(".")
            }
        }
        builder.append("{")
        var index: Int64 = 0
        while (index < items.size) {
            if (index > 0) {
                builder.append(", ")
            }
            builder.append(items[index].FullName())
            index++
        }
        builder.append("}")
        return builder.toString()
    }

    public override func ToString(): String {
        if (kind == ImportKind.IMPORT_MULTI) {
            return FullName()
        }
        let builder = StringBuilder()
        var index: Int64 = 0
        while (index < prefixPaths.size) {
            builder.append(prefixPaths[index].Val())
            if (index == 0 && hasDoubleColon) {
                builder.append("::")
            } else {
                builder.append(".")
            }
            index++
        }
        builder.append(identifier.Val())
        if (kind == ImportKind.IMPORT_ALIAS) {
            builder.append(" as ")
            builder.append(aliasName.Val())
        }
        return builder.toString()
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (item in items) { out.add(item) }
        return out
    }
}

public class ImportSpec <: Node {
    public let annotations: ArrayList<Annotation> = ArrayList<Annotation>()
    public var content: ImportContent = ImportContent()
    public var importPos: Position = INVALID_POSITION
    public var modifier: Option<Modifier> = None
    public var withImplicitExport: Bool = true

    public init() { super(ASTKind.IMPORT_SPEC) }

    public func IsImportAll(): Bool {
        return content.kind == ImportKind.IMPORT_ALL
    }

    public func IsImportSingle(): Bool {
        return content.kind == ImportKind.IMPORT_SINGLE
    }

    public func IsImportAlias(): Bool {
        return content.kind == ImportKind.IMPORT_ALIAS
    }

    public func IsImportMulti(): Bool {
        return content.kind == ImportKind.IMPORT_MULTI
    }

    public func IsPrivateImport(): Bool {
        if (let Some(value) <- modifier) {
            return value.kind == ModifierKind.PRIVATE
        }
        return true
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (anno in annotations) { out.add(anno) }
        out.add(content)
        return out
    }
}

public class PackageSpec <: Node {
    public var modifier: Option<Modifier> = None
    public var macroPos: Position = INVALID_POSITION
    public var packagePos: Position = INVALID_POSITION
    public var hasDoubleColon: Bool = false
    public let identifiers: ArrayList<SrcIdentifier> = ArrayList<SrcIdentifier>()
    public let prefixDotPoses: ArrayList<Position> = ArrayList<Position>()
    public var packageName: SrcIdentifier = SrcIdentifier()
    public let modifiers: ArrayList<Modifier> = ArrayList<Modifier>()
    public var hasMacro: Bool = false
    public var hasSpecific: Bool = false
    public var hasCommon: Bool = false

    public init() { super(ASTKind.PACKAGE_SPEC) }

    public func FullName(): String {
        let builder = StringBuilder()
        var index: Int64 = 0
        while (index < identifiers.size) {
            if (index > 0) {
                if (index == 1 && hasDoubleColon) {
                    builder.append("::")
                } else {
                    builder.append(".")
                }
            }
            builder.append(identifiers[index].Val())
            index++
        }
        return builder.toString()
    }
}

public class FeatureId <: Node {
    public let identifiers: ArrayList<SrcIdentifier> = ArrayList<SrcIdentifier>()
    public let dotPoses: ArrayList<Position> = ArrayList<Position>()

    public init() {
        super(ASTKind.FEATURE_ID)
    }

    public init(identifier: SrcIdentifier) {
        super(ASTKind.FEATURE_ID)
        identifiers.add(identifier)
        begin = identifier.Begin()
        end = identifier.End()
    }

    public override func ToString(): String {
        let parts = ArrayList<String>()
        for (identifier in identifiers) {
            parts.add(identifier.Val())
        }
        return JoinStrings(parts, ".")
    }
}

public class FeaturesSet <: Node {
    public var lCurlPos: Position = INVALID_POSITION
    public let content: ArrayList<FeatureId> = ArrayList<FeatureId>()
    public let commaPoses: ArrayList<Position> = ArrayList<Position>()
    public var rCurlPos: Position = INVALID_POSITION

    public init() { super(ASTKind.FEATURES_SET) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (feature in content) { out.add(feature) }
        return out
    }
}

public class FeaturesDirective <: Node {
    public let annotations: ArrayList<Annotation> = ArrayList<Annotation>()
    public var featuresSet: Option<FeaturesSet> = None
    public var featuresPos: Position = INVALID_POSITION

    public init() { super(ASTKind.FEATURES_DIRECTIVE) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (anno in annotations) { out.add(anno) }
        if (let Some(set) <- featuresSet) { out.add(set) }
        return out
    }
}

public class File <: Node {
    public var packageSpec: Option<PackageSpec> = None
    public let imports: ArrayList<ImportSpec> = ArrayList<ImportSpec>()
    public let decls: ArrayList<Decl> = ArrayList<Decl>()
    public let features: ArrayList<FeaturesDirective> = ArrayList<FeaturesDirective>()
    public var fileID: UInt64 = 0

    public init() { super(ASTKind.FILE) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(pkg) <- packageSpec) { out.add(pkg) }
        for (feature in features) { out.add(feature) }
        for (item in imports) { out.add(item) }
        for (decl in decls) { out.add(decl) }
        return out
    }
}

public func JoinStrings(items: ArrayList<String>, separator: String): String {
    let builder = StringBuilder()
    var index: Int64 = 0
    while (index < items.size) {
        if (index > 0) {
            builder.append(separator)
        }
        builder.append(items[index])
        index++
    }
    return builder.toString()
}
