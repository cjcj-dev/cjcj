package cjcj::mangle

import std.collection.*
import cjcj::ast.{ASTKind, Attribute, Linkage, TypeKind, TypeKindName}
import std.sync.AtomicInt64

private let nextMangleDeclIdentity = AtomicInt64(1)

private func AllocateMangleDeclIdentity(): Int64 {
    return nextMangleDeclIdentity.fetchAdd(1)
}

public class MangleFile {
    public var fileName: String = ""
    public var fileHash: UInt64 = 0u64

    public init() {}

    public init(fileName: String, fileHash!: UInt64 = 0u64) {
        this.fileName = fileName
        this.fileHash = fileHash
    }
}

public class MangleType {
    public var kind: TypeKind
    public var name: String = ""
    public let typeArgs: ArrayList<MangleType> = ArrayList<MangleType>()
    public var dims: UInt64 = 0u64
    public var size: Int64 = 0
    public var retTy: Option<MangleType> = None
    public let paramTys: ArrayList<MangleType> = ArrayList<MangleType>()
    public var isCFunc: Bool = false
    public var decl: Option<MangleDecl> = None

    public init(kind: TypeKind) {
        this.kind = kind
    }

    public init(kind: TypeKind, name: String) {
        this.kind = kind
        this.name = name
    }

    public func IsFunc(): Bool {
        return kind == TypeKind.TYPE_FUNC
    }

    public func String(): String {
        if (!name.isEmpty()) {
            return name
        }
        return TypeKindName(kind)
    }
}

public class MangleTypeAnnotation {
    public var astKind: ASTKind
    public var name: String = ""
    public let typeArguments: ArrayList<MangleTypeAnnotation> = ArrayList<MangleTypeAnnotation>()
    public var innerType: Option<MangleTypeAnnotation> = None
    public var componentType: Option<MangleTypeAnnotation> = None
    public var baseType: Option<MangleTypeAnnotation> = None
    public var field: String = ""
    public var questNum: UInt64 = 0u64
    public var constantValue: String = ""
    public var typeArgument: Option<MangleTypeAnnotation> = None
    public var constantType: Option<MangleTypeAnnotation> = None
    public let paramTypes: ArrayList<MangleTypeAnnotation> = ArrayList<MangleTypeAnnotation>()
    public var retType: Option<MangleTypeAnnotation> = None
    public let fieldTypes: ArrayList<MangleTypeAnnotation> = ArrayList<MangleTypeAnnotation>()
    public var isC: Bool = false
    public var ty: Option<MangleType> = None

    public init(astKind: ASTKind) {
        this.astKind = astKind
    }

    public init(astKind: ASTKind, name: String) {
        this.astKind = astKind
        this.name = name
    }
}

public class MangleGenericConstraint {
    public var typeAnnotation: Option<MangleTypeAnnotation> = None
    public let upperBounds: ArrayList<MangleTypeAnnotation> = ArrayList<MangleTypeAnnotation>()

    public init() {}
}

public class MangleGeneric {
    public let typeParameters: ArrayList<MangleDecl> = ArrayList<MangleDecl>()
    public let genericConstraints: ArrayList<MangleGenericConstraint> = ArrayList<MangleGenericConstraint>()

    public init() {}
}

public class MangleFuncParam {
    public var identifier: String = ""
    public var typeAnnotation: Option<MangleTypeAnnotation> = None
    public var semaTy: Option<MangleType> = None
    public var assignment: Bool = false
    public var isMemberParam: Bool = false
    public var isNamedParam: Bool = false
    public var hasLetOrVar: Bool = false
    public var isVar: Bool = false
    public var hasAccessibilityModifiers: Bool = false
    public var accessibilityModifiers: String = ""
    public let attrs: ArrayList<Attribute> = ArrayList<Attribute>()

    public init() {}

    public init(identifier: String) {
        this.identifier = identifier
    }

    public func TestAttr(attr: Attribute): Bool {
        for (item in attrs) {
            if (item == attr) {
                return true
            }
        }
        return false
    }
}

public class MangleFuncBody {
    public let params: ArrayList<MangleFuncParam> = ArrayList<MangleFuncParam>()
    public var retType: Option<MangleTypeAnnotation> = None
    public var generic: Option<MangleGeneric> = None
    public var parentClassLike: Option<MangleDecl> = None
    public var parentStruct: Option<MangleDecl> = None
    public var parentEnum: Option<MangleDecl> = None

    public init() {}
}

public class ManglePattern {
    public var astKind: ASTKind
    public var varDecl: Option<MangleDecl> = None
    public let patterns: ArrayList<ManglePattern> = ArrayList<ManglePattern>()

    public init(astKind: ASTKind) {
        this.astKind = astKind
    }
}

public class MangleDecl {
    public let identity: Int64 = AllocateMangleDeclIdentity()
    public var astKind: ASTKind
    public var identifier: String = ""
    public var fullPackageName: String = ""
    public var rawMangleName: String = ""
    public var mangledName: String = ""
    public var exportId: String = ""
    public var moduleName: String = ""
    public var curFile: Option<MangleFile> = None
    public var outerDecl: Option<MangleDecl> = None
    public var genericDecl: Option<MangleDecl> = None
    public var linkage: Linkage = Linkage.EXTERNAL
    public var generic: Option<MangleGeneric> = None
    public var semaTy: Option<MangleType> = None
    public var typeAnnotation: Option<MangleTypeAnnotation> = None
    public var funcBody: Option<MangleFuncBody> = None
    public var ownerFunc: Option<MangleDecl> = None
    public var irrefutablePattern: Option<ManglePattern> = None
    public var extendedType: Option<MangleTypeAnnotation> = None
    public var isMemberParam: Bool = false
    public let inheritedTypes: ArrayList<MangleTypeAnnotation> = ArrayList<MangleTypeAnnotation>()
    public let members: ArrayList<MangleDecl> = ArrayList<MangleDecl>()
    public let getters: ArrayList<MangleDecl> = ArrayList<MangleDecl>()
    public let setters: ArrayList<MangleDecl> = ArrayList<MangleDecl>()
    public let attrs: ArrayList<Attribute> = ArrayList<Attribute>()

    public init(astKind: ASTKind) {
        this.astKind = astKind
    }

    public init(astKind: ASTKind, identifier: String, fullPackageName!: String = "") {
        this.astKind = astKind
        this.identifier = identifier
        this.fullPackageName = fullPackageName
    }

    public func TestAttr(attr: Attribute): Bool {
        for (item in attrs) {
            if (item == attr) {
                return true
            }
        }
        return false
    }

    public func TestAnyAttr(first: Attribute, second: Attribute): Bool {
        return TestAttr(first) || TestAttr(second)
    }

    public func TestAnyAttr(first: Attribute, second: Attribute, third: Attribute): Bool {
        return TestAttr(first) || TestAttr(second) || TestAttr(third)
    }

    public func IsFunc(): Bool {
        return astKind == ASTKind.FUNC_DECL
    }

    public func IsNominalDecl(): Bool {
        return astKind == ASTKind.CLASS_DECL || astKind == ASTKind.INTERFACE_DECL ||
            astKind == ASTKind.STRUCT_DECL || astKind == ASTKind.EXTEND_DECL ||
            astKind == ASTKind.ENUM_DECL
    }

    public func IsClassLikeDecl(): Bool {
        return astKind == ASTKind.CLASS_DECL || astKind == ASTKind.INTERFACE_DECL
    }

    public func IsStructOrClassDecl(): Bool {
        return astKind == ASTKind.CLASS_DECL || astKind == ASTKind.STRUCT_DECL
    }

    public func IsStaticOrGlobal(): Bool {
        return TestAttr(Attribute.GLOBAL) || TestAttr(Attribute.STATIC)
    }

    public func GetGeneric(): Option<MangleGeneric> {
        if (let Some(body) <- funcBody) {
            if (let Some(value) <- body.generic) {
                return value
            }
            if (let Some(parentEnum) <- body.parentEnum) {
                if (TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
                    return parentEnum.generic
                }
            }
            return None
        }
        if (astKind == ASTKind.VAR_DECL) {
            if (let Some(outer) <- outerDecl) {
                if (outer.astKind == ASTKind.ENUM_DECL) {
                    return outer.generic
                }
            }
        }
        return generic
    }

    public func GetMemberDecls(): ArrayList<MangleDecl> {
        return members
    }
}
