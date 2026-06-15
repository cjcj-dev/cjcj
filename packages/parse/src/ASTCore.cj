package cangjie_compiler::parse

import std.collection.*

public enum ASTKind {
    | NODE | FILE | PACKAGE_SPEC | IMPORT_CONTENT | IMPORT_SPEC | FEATURES_DIRECTIVE | FEATURES_SET | FEATURE_ID
    | ANNOTATION | MODIFIER | DECL | FUNC_DECL | MAIN_DECL | MACRO_DECL | VAR_DECL | VAR_WITH_PATTERN_DECL
    | CLASS_DECL | INTERFACE_DECL | STRUCT_DECL | ENUM_DECL | EXTEND_DECL | TYPE_ALIAS_DECL | PROP_DECL
    | PRIMARY_CTOR_DECL | GENERIC_PARAM_DECL | MACRO_EXPAND_DECL | INVALID_DECL
    | TYPE | REF_TYPE | QUALIFIED_TYPE | OPTION_TYPE | CONSTANT_TYPE | VARRAY_TYPE | PRIMITIVE_TYPE | PAREN_TYPE
    | FUNC_TYPE | TUPLE_TYPE | THIS_TYPE | INVALID_TYPE
    | PATTERN | VAR_PATTERN | CONST_PATTERN | TUPLE_PATTERN | ENUM_PATTERN | VAR_OR_ENUM_PATTERN | TYPE_PATTERN
    | WILDCARD_PATTERN | INVALID_PATTERN
    | EXPR | WILDCARD_EXPR | REF_EXPR | LIT_CONST_EXPR | PAREN_EXPR | TUPLE_LIT | ARRAY_LIT | CALL_EXPR
    | MEMBER_ACCESS | SUBSCRIPT_EXPR | UNARY_EXPR | BINARY_EXPR | ASSIGN_EXPR | RANGE_EXPR | IS_EXPR | AS_EXPR
    | BLOCK | IF_EXPR | MATCH_EXPR | TRY_EXPR | WHILE_EXPR | DO_WHILE_EXPR | FOR_IN_EXPR | LAMBDA_EXPR
    | RETURN_EXPR | JUMP_EXPR | THROW_EXPR | PERFORM_EXPR | RESUME_EXPR | SPAWN_EXPR | SYNCHRONIZED_EXPR
    | QUOTE_EXPR | MACRO_EXPAND_EXPR | IF_AVAILABLE_EXPR | TRAIL_CLOSURE_EXPR | INVALID_EXPR
    | GENERIC | GENERIC_CONSTRAINT | FUNC_ARG | FUNC_PARAM | FUNC_PARAM_LIST | FUNC_BODY
    | CLASS_BODY | INTERFACE_BODY | STRUCT_BODY | MATCH_CASE | LET_PATTERN_DESTRUCTOR
}

public func ASTKindIndex(kind: ASTKind): Int64 {
    return match (kind) {
        case ASTKind.NODE => 0
        case ASTKind.FILE => 1
        case ASTKind.PACKAGE_SPEC => 2
        case ASTKind.IMPORT_CONTENT => 3
        case ASTKind.IMPORT_SPEC => 4
        case ASTKind.FEATURES_DIRECTIVE => 5
        case ASTKind.FEATURES_SET => 6
        case ASTKind.FEATURE_ID => 7
        case ASTKind.ANNOTATION => 8
        case ASTKind.MODIFIER => 9
        case ASTKind.DECL => 10
        case ASTKind.FUNC_DECL => 11
        case ASTKind.MAIN_DECL => 12
        case ASTKind.MACRO_DECL => 13
        case ASTKind.VAR_DECL => 14
        case ASTKind.VAR_WITH_PATTERN_DECL => 15
        case ASTKind.CLASS_DECL => 16
        case ASTKind.INTERFACE_DECL => 17
        case ASTKind.STRUCT_DECL => 18
        case ASTKind.ENUM_DECL => 19
        case ASTKind.EXTEND_DECL => 20
        case ASTKind.TYPE_ALIAS_DECL => 21
        case ASTKind.PROP_DECL => 22
        case ASTKind.PRIMARY_CTOR_DECL => 23
        case ASTKind.GENERIC_PARAM_DECL => 24
        case ASTKind.MACRO_EXPAND_DECL => 25
        case ASTKind.INVALID_DECL => 26
        case ASTKind.TYPE => 27
        case ASTKind.REF_TYPE => 28
        case ASTKind.QUALIFIED_TYPE => 29
        case ASTKind.OPTION_TYPE => 30
        case ASTKind.CONSTANT_TYPE => 31
        case ASTKind.VARRAY_TYPE => 32
        case ASTKind.PRIMITIVE_TYPE => 33
        case ASTKind.PAREN_TYPE => 34
        case ASTKind.FUNC_TYPE => 35
        case ASTKind.TUPLE_TYPE => 36
        case ASTKind.THIS_TYPE => 37
        case ASTKind.INVALID_TYPE => 38
        case ASTKind.PATTERN => 39
        case ASTKind.VAR_PATTERN => 40
        case ASTKind.CONST_PATTERN => 41
        case ASTKind.TUPLE_PATTERN => 42
        case ASTKind.ENUM_PATTERN => 43
        case ASTKind.VAR_OR_ENUM_PATTERN => 44
        case ASTKind.TYPE_PATTERN => 45
        case ASTKind.WILDCARD_PATTERN => 46
        case ASTKind.INVALID_PATTERN => 47
        case ASTKind.EXPR => 48
        case ASTKind.WILDCARD_EXPR => 49
        case ASTKind.REF_EXPR => 50
        case ASTKind.LIT_CONST_EXPR => 51
        case ASTKind.PAREN_EXPR => 52
        case ASTKind.TUPLE_LIT => 53
        case ASTKind.ARRAY_LIT => 54
        case ASTKind.CALL_EXPR => 55
        case ASTKind.MEMBER_ACCESS => 56
        case ASTKind.SUBSCRIPT_EXPR => 57
        case ASTKind.UNARY_EXPR => 58
        case ASTKind.BINARY_EXPR => 59
        case ASTKind.ASSIGN_EXPR => 60
        case ASTKind.RANGE_EXPR => 61
        case ASTKind.IS_EXPR => 62
        case ASTKind.AS_EXPR => 63
        case ASTKind.BLOCK => 64
        case ASTKind.IF_EXPR => 65
        case ASTKind.MATCH_EXPR => 66
        case ASTKind.TRY_EXPR => 67
        case ASTKind.WHILE_EXPR => 68
        case ASTKind.DO_WHILE_EXPR => 69
        case ASTKind.FOR_IN_EXPR => 70
        case ASTKind.LAMBDA_EXPR => 71
        case ASTKind.RETURN_EXPR => 72
        case ASTKind.JUMP_EXPR => 73
        case ASTKind.THROW_EXPR => 74
        case ASTKind.PERFORM_EXPR => 75
        case ASTKind.RESUME_EXPR => 76
        case ASTKind.SPAWN_EXPR => 77
        case ASTKind.SYNCHRONIZED_EXPR => 78
        case ASTKind.QUOTE_EXPR => 79
        case ASTKind.MACRO_EXPAND_EXPR => 80
        case ASTKind.IF_AVAILABLE_EXPR => 81
        case ASTKind.TRAIL_CLOSURE_EXPR => 82
        case ASTKind.INVALID_EXPR => 83
        case ASTKind.GENERIC => 84
        case ASTKind.GENERIC_CONSTRAINT => 85
        case ASTKind.FUNC_ARG => 86
        case ASTKind.FUNC_PARAM => 87
        case ASTKind.FUNC_PARAM_LIST => 88
        case ASTKind.FUNC_BODY => 89
        case ASTKind.CLASS_BODY => 90
        case ASTKind.INTERFACE_BODY => 91
        case ASTKind.STRUCT_BODY => 92
        case ASTKind.MATCH_CASE => 93
        case ASTKind.LET_PATTERN_DESTRUCTOR => 94
    }
}

extend ASTKind <: Equatable<ASTKind> {
    public operator func ==(right: ASTKind): Bool { return ASTKindIndex(this) == ASTKindIndex(right) }
    public operator func !=(right: ASTKind): Bool { return !(this == right) }
}

public open class Node {
    public var begin: Position = INVALID_POSITION
    public var end: Position = INVALID_POSITION
    public var curMacroCall: Option<Node> = None
    public var curFile: Option<File> = None
    public let astKind: ASTKind
    public var isBroken: Bool = false

    public init() {
        astKind = ASTKind.NODE
    }

    public init(kind: ASTKind) {
        astKind = kind
    }

    public open func Children(): ArrayList<Node> {
        return ArrayList<Node>()
    }

    public open func ToString(): String {
        return ""
    }
}

public class SrcIdentifier {
    public var value: String = ""
    public var rawValue: String = ""
    public var begin: Position = INVALID_POSITION
    public var end: Position = INVALID_POSITION
    public var isRaw: Bool = false

    public init() {}

    public init(value: String, rawValue: String, begin: Position, end: Position, isRaw: Bool) {
        this.value = value
        this.rawValue = rawValue
        this.begin = begin
        this.end = end
        this.isRaw = isRaw
    }

    public func Empty(): Bool {
        return value.isEmpty()
    }

    public func Begin(): Position {
        return begin
    }

    public func End(): Position {
        return end
    }

    public func Val(): String {
        return value
    }

    public func GetRawText(): String {
        return if (rawValue.isEmpty()) { value } else { rawValue }
    }
}

public enum ModifierKind {
    | PUBLIC | PROTECTED | INTERNAL | PRIVATE | STATIC | ABSTRACT | OPEN | SEALED | OVERRIDE
    | REDEF | FOREIGN | INOUT | MUT | UNSAFE | OPERATOR | CONST | COMMON | SPECIFIC
}

private func ModifierKindIndex(kind: ModifierKind): Int64 {
    return match (kind) {
        case ModifierKind.PUBLIC => 0
        case ModifierKind.PROTECTED => 1
        case ModifierKind.INTERNAL => 2
        case ModifierKind.PRIVATE => 3
        case ModifierKind.STATIC => 4
        case ModifierKind.ABSTRACT => 5
        case ModifierKind.OPEN => 6
        case ModifierKind.SEALED => 7
        case ModifierKind.OVERRIDE => 8
        case ModifierKind.REDEF => 9
        case ModifierKind.FOREIGN => 10
        case ModifierKind.INOUT => 11
        case ModifierKind.MUT => 12
        case ModifierKind.UNSAFE => 13
        case ModifierKind.OPERATOR => 14
        case ModifierKind.CONST => 15
        case ModifierKind.COMMON => 16
        case ModifierKind.SPECIFIC => 17
    }
}

extend ModifierKind <: Equatable<ModifierKind> {
    public operator func ==(right: ModifierKind): Bool { return ModifierKindIndex(this) == ModifierKindIndex(right) }
    public operator func !=(right: ModifierKind): Bool { return !(this == right) }
}

public class Modifier <: Node {
    public var kind: ModifierKind
    public var tokenKind: TokenKind

    public init(kind: ModifierKind, tokenKind: TokenKind, begin: Position, end: Position) {
        super(ASTKind.MODIFIER)
        this.kind = kind
        this.tokenKind = tokenKind
        this.begin = begin
        this.end = end
    }
}

public enum Attribute {
    | PUBLIC | PROTECTED | INTERNAL | PRIVATE | STATIC | ABSTRACT | OPEN | SEALED | OVERRIDE
    | REDEF | FOREIGN | INOUT | MUT | UNSAFE | OPERATOR | CONST | COMMON | SPECIFIC | COMMON_WITH_DEFAULT
    | CONSTRUCTOR | PRIMARY_CONSTRUCTOR | ENUM_CONSTRUCTOR | GENERIC
    | JAVA_MIRROR | JAVA_MIRROR_SUBTYPE | JAVA_CJ_MAPPING
    | OBJ_C_MIRROR | OBJ_C_MIRROR_SUBTYPE | OBJ_C_INIT | OBJ_C_OPTIONAL
    | IS_BROKEN | BROKEN
}

public func AttributeIndex(kind: Attribute): Int64 {
    return match (kind) {
        case Attribute.PUBLIC => 0
        case Attribute.PROTECTED => 1
        case Attribute.INTERNAL => 2
        case Attribute.PRIVATE => 3
        case Attribute.STATIC => 4
        case Attribute.ABSTRACT => 5
        case Attribute.OPEN => 6
        case Attribute.SEALED => 7
        case Attribute.OVERRIDE => 8
        case Attribute.REDEF => 9
        case Attribute.FOREIGN => 10
        case Attribute.INOUT => 11
        case Attribute.MUT => 12
        case Attribute.UNSAFE => 13
        case Attribute.OPERATOR => 14
        case Attribute.CONST => 15
        case Attribute.COMMON => 16
        case Attribute.SPECIFIC => 17
        case Attribute.COMMON_WITH_DEFAULT => 18
        case Attribute.CONSTRUCTOR => 19
        case Attribute.PRIMARY_CONSTRUCTOR => 20
        case Attribute.ENUM_CONSTRUCTOR => 21
        case Attribute.GENERIC => 22
        case Attribute.JAVA_MIRROR => 23
        case Attribute.JAVA_MIRROR_SUBTYPE => 24
        case Attribute.JAVA_CJ_MAPPING => 25
        case Attribute.OBJ_C_MIRROR => 26
        case Attribute.OBJ_C_MIRROR_SUBTYPE => 27
        case Attribute.OBJ_C_INIT => 28
        case Attribute.OBJ_C_OPTIONAL => 29
        case Attribute.IS_BROKEN => 30
        case Attribute.BROKEN => 31
    }
}

extend Attribute <: Equatable<Attribute> {
    public operator func ==(right: Attribute): Bool { return AttributeIndex(this) == AttributeIndex(right) }
    public operator func !=(right: Attribute): Bool { return !(this == right) }
}

public enum AnnotationKind {
    | JAVA_MIRROR | JAVA_IMPL | JAVA_HAS_DEFAULT | OBJ_C_MIRROR | OBJ_C_IMPL | FOREIGN_GETTER_NAME
    | FOREIGN_SETTER_NAME | OBJ_C_INIT | OBJ_C_OPTIONAL | FOREIGN_NAME | CALLING_CONV | C | ATTRIBUTE
    | INTRINSIC | NUMERIC_OVERFLOW | WHEN | FASTNATIVE | ANNOTATION | CONSTSAFE | DEPRECATED | FROZEN
    | ENSURE_PREPARED_TO_MOCK | NON_PRODUCT | CUSTOM
}

private func AnnotationKindIndex(kind: AnnotationKind): Int64 {
    return match (kind) {
        case AnnotationKind.JAVA_MIRROR => 0
        case AnnotationKind.JAVA_IMPL => 1
        case AnnotationKind.JAVA_HAS_DEFAULT => 2
        case AnnotationKind.OBJ_C_MIRROR => 3
        case AnnotationKind.OBJ_C_IMPL => 4
        case AnnotationKind.FOREIGN_GETTER_NAME => 5
        case AnnotationKind.FOREIGN_SETTER_NAME => 6
        case AnnotationKind.OBJ_C_INIT => 7
        case AnnotationKind.OBJ_C_OPTIONAL => 8
        case AnnotationKind.FOREIGN_NAME => 9
        case AnnotationKind.CALLING_CONV => 10
        case AnnotationKind.C => 11
        case AnnotationKind.ATTRIBUTE => 12
        case AnnotationKind.INTRINSIC => 13
        case AnnotationKind.NUMERIC_OVERFLOW => 14
        case AnnotationKind.WHEN => 15
        case AnnotationKind.FASTNATIVE => 16
        case AnnotationKind.ANNOTATION => 17
        case AnnotationKind.CONSTSAFE => 18
        case AnnotationKind.DEPRECATED => 19
        case AnnotationKind.FROZEN => 20
        case AnnotationKind.ENSURE_PREPARED_TO_MOCK => 21
        case AnnotationKind.NON_PRODUCT => 22
        case AnnotationKind.CUSTOM => 23
    }
}

extend AnnotationKind <: Equatable<AnnotationKind> {
    public operator func ==(right: AnnotationKind): Bool { return AnnotationKindIndex(this) == AnnotationKindIndex(right) }
    public operator func !=(right: AnnotationKind): Bool { return !(this == right) }
}

public class Annotation <: Node {
    public var kind: AnnotationKind = AnnotationKind.CUSTOM
    public var identifier: SrcIdentifier = SrcIdentifier()
    public let args: ArrayList<FuncArg> = ArrayList<FuncArg>()
    public var atPos: Position = INVALID_POSITION
    public var leftParenPos: Position = INVALID_POSITION
    public var rightParenPos: Position = INVALID_POSITION

    public init() {
        super(ASTKind.ANNOTATION)
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (arg in args) { out.add(arg) }
        return out
    }
}
