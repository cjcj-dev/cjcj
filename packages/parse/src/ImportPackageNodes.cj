package cangjie_compiler::parse

import std.collection.*

public class ImportContent <: Node {
    public let prefixPaths: ArrayList<SrcIdentifier> = ArrayList<SrcIdentifier>()
    public let items: ArrayList<SrcIdentifier> = ArrayList<SrcIdentifier>()
    public var aliasName: SrcIdentifier = SrcIdentifier()
    public var importAll: Bool = false

    public init() { super(ASTKind.IMPORT_CONTENT) }

    public func FullName(): String {
        let parts = ArrayList<String>()
        for (item in prefixPaths) { parts.add(item.GetRawText()) }
        for (item in items) { parts.add(item.GetRawText()) }
        return JoinStrings(parts, ".")
    }
}

public class ImportSpec <: Node {
    public let annotations: ArrayList<Annotation> = ArrayList<Annotation>()
    public var content: ImportContent = ImportContent()
    public var importPos: Position = INVALID_POSITION
    public var modifier: Option<Modifier> = None

    public init() { super(ASTKind.IMPORT_SPEC) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (anno in annotations) { out.add(anno) }
        out.add(content)
        return out
    }
}

public class PackageSpec <: Node {
    public var packagePos: Position = INVALID_POSITION
    public let identifiers: ArrayList<SrcIdentifier> = ArrayList<SrcIdentifier>()
    public let modifiers: ArrayList<Modifier> = ArrayList<Modifier>()

    public init() { super(ASTKind.PACKAGE_SPEC) }

    public func FullName(): String {
        let parts = ArrayList<String>()
        for (id in identifiers) { parts.add(id.GetRawText()) }
        return JoinStrings(parts, ".")
    }
}

public class FeatureId <: Node {
    public var identifier: SrcIdentifier = SrcIdentifier()
    public init(identifier: SrcIdentifier) {
        super(ASTKind.FEATURE_ID)
        this.identifier = identifier
        begin = identifier.Begin()
        end = identifier.End()
    }
}

public class FeaturesSet <: Node {
    public let features: ArrayList<FeatureId> = ArrayList<FeatureId>()
    public init() { super(ASTKind.FEATURES_SET) }
}

public class FeaturesDirective <: Node {
    public var featuresPos: Position = INVALID_POSITION
    public let featureSets: ArrayList<FeaturesSet> = ArrayList<FeaturesSet>()
    public init() { super(ASTKind.FEATURES_DIRECTIVE) }
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
