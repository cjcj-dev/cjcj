package cangjie_compiler::mangle

import std.collection.*
import cangjie_compiler::ast.Linkage

private var nextMangleDeclIdentity: Int64 = 1

private func AllocateMangleDeclIdentity(): Int64 {
    let value = nextMangleDeclIdentity
    nextMangleDeclIdentity++
    return value
}

public enum MangleAstKind {
    | DECL
    | MAIN_DECL
    | FUNC_DECL
    | MACRO_DECL
    | CLASS_DECL
    | INTERFACE_DECL
    | EXTEND_DECL
    | ENUM_DECL
    | STRUCT_DECL
    | TYPE_ALIAS_DECL
    | PRIMARY_CTOR_DECL
    | BUILTIN_DECL
    | VAR_DECL
    | PROP_DECL
    | FUNC_PARAM
    | VAR_WITH_PATTERN_DECL
    | GENERIC_PARAM_DECL
    | PACKAGE
    | FILE
    | LAMBDA_EXPR
    | REF_TYPE
    | QUALIFIED_TYPE
    | OPTION_TYPE
    | CONSTANT_TYPE
    | VARRAY_TYPE
    | PRIMITIVE_TYPE
    | PAREN_TYPE
    | FUNC_TYPE
    | TUPLE_TYPE
    | THIS_TYPE
    | WILDCARD_PATTERN
    | VAR_PATTERN
    | TUPLE_PATTERN
    | ENUM_PATTERN
    | INVALID
}

public enum MangleAttribute {
    | GLOBAL
    | STATIC
    | PUBLIC
    | PRIVATE
    | PROTECTED
    | INTERNAL
    | NO_MANGLE
    | GENERIC
    | GENERIC_INSTANTIATED
    | HAS_INITIAL
    | CONSTRUCTOR
    | MAIN_ENTRY
    | OPERATOR
    | DEFAULT
    | ABSTRACT
    | COMMON
    | SPECIFIC
    | FOR_TEST
}

public enum MangleTypeKind {
    | TYPE_INVALID
    | TYPE_UNIT
    | TYPE_INT8
    | TYPE_INT16
    | TYPE_INT32
    | TYPE_INT64
    | TYPE_INT_NATIVE
    | TYPE_IDEAL_INT
    | TYPE_UINT8
    | TYPE_UINT16
    | TYPE_UINT32
    | TYPE_UINT64
    | TYPE_UINT_NATIVE
    | TYPE_FLOAT16
    | TYPE_FLOAT32
    | TYPE_FLOAT64
    | TYPE_IDEAL_FLOAT
    | TYPE_RUNE
    | TYPE_NOTHING
    | TYPE_BOOLEAN
    | TYPE_TUPLE
    | TYPE_ENUM
    | TYPE_FUNC
    | TYPE_STRUCT
    | TYPE_ARRAY
    | TYPE_VARRAY
    | TYPE_POINTER
    | TYPE_CSTRING
    | TYPE_CLASS
    | TYPE_INTERFACE
    | TYPE_GENERICS
    | TYPE_ANY
    | TYPE_INTERSECTION
    | TYPE_UNION
    | TYPE_QUEST
    | TYPE_INITIAL
}

private func MangleAstKindIndex(kind: MangleAstKind): Int64 {
    return match (kind) {
        case MangleAstKind.DECL => 0
        case MangleAstKind.MAIN_DECL => 1
        case MangleAstKind.FUNC_DECL => 2
        case MangleAstKind.MACRO_DECL => 3
        case MangleAstKind.CLASS_DECL => 4
        case MangleAstKind.INTERFACE_DECL => 5
        case MangleAstKind.EXTEND_DECL => 6
        case MangleAstKind.ENUM_DECL => 7
        case MangleAstKind.STRUCT_DECL => 8
        case MangleAstKind.TYPE_ALIAS_DECL => 9
        case MangleAstKind.PRIMARY_CTOR_DECL => 10
        case MangleAstKind.BUILTIN_DECL => 11
        case MangleAstKind.VAR_DECL => 12
        case MangleAstKind.PROP_DECL => 13
        case MangleAstKind.FUNC_PARAM => 14
        case MangleAstKind.VAR_WITH_PATTERN_DECL => 15
        case MangleAstKind.GENERIC_PARAM_DECL => 16
        case MangleAstKind.PACKAGE => 17
        case MangleAstKind.FILE => 18
        case MangleAstKind.LAMBDA_EXPR => 19
        case MangleAstKind.REF_TYPE => 20
        case MangleAstKind.QUALIFIED_TYPE => 21
        case MangleAstKind.OPTION_TYPE => 22
        case MangleAstKind.CONSTANT_TYPE => 23
        case MangleAstKind.VARRAY_TYPE => 24
        case MangleAstKind.PRIMITIVE_TYPE => 25
        case MangleAstKind.PAREN_TYPE => 26
        case MangleAstKind.FUNC_TYPE => 27
        case MangleAstKind.TUPLE_TYPE => 28
        case MangleAstKind.THIS_TYPE => 29
        case MangleAstKind.WILDCARD_PATTERN => 30
        case MangleAstKind.VAR_PATTERN => 31
        case MangleAstKind.TUPLE_PATTERN => 32
        case MangleAstKind.ENUM_PATTERN => 33
        case MangleAstKind.INVALID => 34
    }
}

private func MangleAttributeIndex(attr: MangleAttribute): Int64 {
    return match (attr) {
        case MangleAttribute.GLOBAL => 0
        case MangleAttribute.STATIC => 1
        case MangleAttribute.PUBLIC => 2
        case MangleAttribute.PRIVATE => 3
        case MangleAttribute.PROTECTED => 4
        case MangleAttribute.INTERNAL => 5
        case MangleAttribute.NO_MANGLE => 6
        case MangleAttribute.GENERIC => 7
        case MangleAttribute.GENERIC_INSTANTIATED => 8
        case MangleAttribute.HAS_INITIAL => 9
        case MangleAttribute.CONSTRUCTOR => 10
        case MangleAttribute.MAIN_ENTRY => 11
        case MangleAttribute.OPERATOR => 12
        case MangleAttribute.DEFAULT => 13
        case MangleAttribute.ABSTRACT => 14
        case MangleAttribute.COMMON => 15
        case MangleAttribute.SPECIFIC => 16
        case MangleAttribute.FOR_TEST => 17
    }
}

private func MangleTypeKindIndex(kind: MangleTypeKind): Int64 {
    return match (kind) {
        case MangleTypeKind.TYPE_INVALID => 0
        case MangleTypeKind.TYPE_UNIT => 1
        case MangleTypeKind.TYPE_INT8 => 2
        case MangleTypeKind.TYPE_INT16 => 3
        case MangleTypeKind.TYPE_INT32 => 4
        case MangleTypeKind.TYPE_INT64 => 5
        case MangleTypeKind.TYPE_INT_NATIVE => 6
        case MangleTypeKind.TYPE_IDEAL_INT => 7
        case MangleTypeKind.TYPE_UINT8 => 8
        case MangleTypeKind.TYPE_UINT16 => 9
        case MangleTypeKind.TYPE_UINT32 => 10
        case MangleTypeKind.TYPE_UINT64 => 11
        case MangleTypeKind.TYPE_UINT_NATIVE => 12
        case MangleTypeKind.TYPE_FLOAT16 => 13
        case MangleTypeKind.TYPE_FLOAT32 => 14
        case MangleTypeKind.TYPE_FLOAT64 => 15
        case MangleTypeKind.TYPE_IDEAL_FLOAT => 16
        case MangleTypeKind.TYPE_RUNE => 17
        case MangleTypeKind.TYPE_NOTHING => 18
        case MangleTypeKind.TYPE_BOOLEAN => 19
        case MangleTypeKind.TYPE_TUPLE => 20
        case MangleTypeKind.TYPE_ENUM => 21
        case MangleTypeKind.TYPE_FUNC => 22
        case MangleTypeKind.TYPE_STRUCT => 23
        case MangleTypeKind.TYPE_ARRAY => 24
        case MangleTypeKind.TYPE_VARRAY => 25
        case MangleTypeKind.TYPE_POINTER => 26
        case MangleTypeKind.TYPE_CSTRING => 27
        case MangleTypeKind.TYPE_CLASS => 28
        case MangleTypeKind.TYPE_INTERFACE => 29
        case MangleTypeKind.TYPE_GENERICS => 30
        case MangleTypeKind.TYPE_ANY => 31
        case MangleTypeKind.TYPE_INTERSECTION => 32
        case MangleTypeKind.TYPE_UNION => 33
        case MangleTypeKind.TYPE_QUEST => 34
        case MangleTypeKind.TYPE_INITIAL => 35
    }
}

private func MangleTypeKindName(kind: MangleTypeKind): String {
    return match (kind) {
        case MangleTypeKind.TYPE_INVALID => "Invalid"
        case MangleTypeKind.TYPE_UNIT => "Unit"
        case MangleTypeKind.TYPE_INT8 => "Int8"
        case MangleTypeKind.TYPE_INT16 => "Int16"
        case MangleTypeKind.TYPE_INT32 => "Int32"
        case MangleTypeKind.TYPE_INT64 => "Int64"
        case MangleTypeKind.TYPE_INT_NATIVE => "IntNative"
        case MangleTypeKind.TYPE_IDEAL_INT => "Int"
        case MangleTypeKind.TYPE_UINT8 => "UInt8"
        case MangleTypeKind.TYPE_UINT16 => "UInt16"
        case MangleTypeKind.TYPE_UINT32 => "UInt32"
        case MangleTypeKind.TYPE_UINT64 => "UInt64"
        case MangleTypeKind.TYPE_UINT_NATIVE => "UIntNative"
        case MangleTypeKind.TYPE_FLOAT16 => "Float16"
        case MangleTypeKind.TYPE_FLOAT32 => "Float32"
        case MangleTypeKind.TYPE_FLOAT64 => "Float64"
        case MangleTypeKind.TYPE_IDEAL_FLOAT => "Float"
        case MangleTypeKind.TYPE_RUNE => "Rune"
        case MangleTypeKind.TYPE_NOTHING => "Nothing"
        case MangleTypeKind.TYPE_BOOLEAN => "Bool"
        case MangleTypeKind.TYPE_TUPLE => "Tuple"
        case MangleTypeKind.TYPE_ENUM => "Enum"
        case MangleTypeKind.TYPE_FUNC => "Function"
        case MangleTypeKind.TYPE_STRUCT => "Struct"
        case MangleTypeKind.TYPE_ARRAY => "RawArray"
        case MangleTypeKind.TYPE_VARRAY => "VArray"
        case MangleTypeKind.TYPE_POINTER => "CPointer"
        case MangleTypeKind.TYPE_CSTRING => "CString"
        case MangleTypeKind.TYPE_CLASS => "Class"
        case MangleTypeKind.TYPE_INTERFACE => "Interface"
        case MangleTypeKind.TYPE_GENERICS => "Generic"
        case MangleTypeKind.TYPE_ANY => "Any"
        case MangleTypeKind.TYPE_INTERSECTION => "Intersection"
        case MangleTypeKind.TYPE_UNION => "Union"
        case MangleTypeKind.TYPE_QUEST => "Quest"
        case MangleTypeKind.TYPE_INITIAL => "Initial"
    }
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
    public var kind: MangleTypeKind
    public var name: String = ""
    public let typeArgs: ArrayList<MangleType> = ArrayList<MangleType>()
    public var dims: UInt64 = 0u64
    public var size: Int64 = 0
    public var retTy: Option<MangleType> = None
    public let paramTys: ArrayList<MangleType> = ArrayList<MangleType>()
    public var isCFunc: Bool = false
    public var decl: Option<MangleDecl> = None

    public init(kind: MangleTypeKind) {
        this.kind = kind
    }

    public init(kind: MangleTypeKind, name: String) {
        this.kind = kind
        this.name = name
    }

    public func IsFunc(): Bool {
        return kind == MangleTypeKind.TYPE_FUNC
    }

    public func String(): String {
        if (!name.isEmpty()) {
            return name
        }
        return MangleTypeKindName(kind)
    }
}

public class MangleTypeAnnotation {
    public var astKind: MangleAstKind
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

    public init(astKind: MangleAstKind) {
        this.astKind = astKind
    }

    public init(astKind: MangleAstKind, name: String) {
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
    public let attrs: ArrayList<MangleAttribute> = ArrayList<MangleAttribute>()

    public init() {}

    public init(identifier: String) {
        this.identifier = identifier
    }

    public func TestAttr(attr: MangleAttribute): Bool {
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
    public var astKind: MangleAstKind
    public var varDecl: Option<MangleDecl> = None
    public let patterns: ArrayList<ManglePattern> = ArrayList<ManglePattern>()

    public init(astKind: MangleAstKind) {
        this.astKind = astKind
    }
}

public class MangleDecl {
    public let identity: Int64 = AllocateMangleDeclIdentity()
    public var astKind: MangleAstKind
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
    public let attrs: ArrayList<MangleAttribute> = ArrayList<MangleAttribute>()

    public init(astKind: MangleAstKind) {
        this.astKind = astKind
    }

    public init(astKind: MangleAstKind, identifier: String, fullPackageName!: String = "") {
        this.astKind = astKind
        this.identifier = identifier
        this.fullPackageName = fullPackageName
    }

    public func TestAttr(attr: MangleAttribute): Bool {
        for (item in attrs) {
            if (item == attr) {
                return true
            }
        }
        return false
    }

    public func TestAnyAttr(first: MangleAttribute, second: MangleAttribute): Bool {
        return TestAttr(first) || TestAttr(second)
    }

    public func TestAnyAttr(first: MangleAttribute, second: MangleAttribute, third: MangleAttribute): Bool {
        return TestAttr(first) || TestAttr(second) || TestAttr(third)
    }

    public func IsFunc(): Bool {
        return astKind == MangleAstKind.FUNC_DECL
    }

    public func IsNominalDecl(): Bool {
        return astKind == MangleAstKind.CLASS_DECL || astKind == MangleAstKind.INTERFACE_DECL ||
            astKind == MangleAstKind.STRUCT_DECL || astKind == MangleAstKind.EXTEND_DECL ||
            astKind == MangleAstKind.ENUM_DECL
    }

    public func IsClassLikeDecl(): Bool {
        return astKind == MangleAstKind.CLASS_DECL || astKind == MangleAstKind.INTERFACE_DECL
    }

    public func IsStructOrClassDecl(): Bool {
        return astKind == MangleAstKind.CLASS_DECL || astKind == MangleAstKind.STRUCT_DECL
    }

    public func IsStaticOrGlobal(): Bool {
        return TestAttr(MangleAttribute.GLOBAL) || TestAttr(MangleAttribute.STATIC)
    }

    public func GetGeneric(): Option<MangleGeneric> {
        if (let Some(body) <- funcBody) {
            if (let Some(value) <- body.generic) {
                return value
            }
            if (let Some(parentEnum) <- body.parentEnum) {
                if (TestAttr(MangleAttribute.CONSTRUCTOR)) {
                    return parentEnum.generic
                }
            }
        }
        return generic
    }

    public func GetMemberDecls(): ArrayList<MangleDecl> {
        return members
    }
}

extend MangleAttribute <: Equatable<MangleAttribute> {
    public operator func ==(right: MangleAttribute): Bool {
        return MangleAttributeIndex(this) == MangleAttributeIndex(right)
    }

    public operator func !=(right: MangleAttribute): Bool {
        return !(this == right)
    }
}

extend MangleAstKind <: Equatable<MangleAstKind> {
    public operator func ==(right: MangleAstKind): Bool {
        return MangleAstKindIndex(this) == MangleAstKindIndex(right)
    }

    public operator func !=(right: MangleAstKind): Bool {
        return !(this == right)
    }
}

extend MangleTypeKind <: Equatable<MangleTypeKind> {
    public operator func ==(right: MangleTypeKind): Bool {
        return MangleTypeKindIndex(this) == MangleTypeKindIndex(right)
    }

    public operator func !=(right: MangleTypeKind): Bool {
        return !(this == right)
    }
}
