package cjcj::ast

import std.collection.*

public enum Attribute {
    | IN_REFERENCE_CYCLE
    | UNREACHABLE
    | IMPLICIT_USED
    | IMPORTED
    | GLOBAL
    | INITIALIZED
    | COMPILER_ADD
    | GENERIC
    | DEFAULT
    | STATIC
    | PUBLIC
    | PRIVATE
    | PROTECTED
    | EXTERNAL
    | INTERNAL
    | OVERRIDE
    | REDEF
    | ABSTRACT
    | SEALED
    | OPEN
    | OPERATOR
    | FOREIGN
    | UNSAFE
    | MUT
    | HAS_BROKEN
    | IN_STRUCT
    | IN_EXTEND
    | IN_ENUM
    | IN_CLASSLIKE
    | IN_MACRO
    | PRIMARY_CONSTRUCTOR
    | CONSTRUCTOR
    | ENUM_CONSTRUCTOR
    | FINALIZER
    | IS_CLONED_SOURCE_CODE
    | IS_CAPTURE
    | IN_CORE
    | NEED_AUTO_BOX
    | MACRO_EXPANDED_NODE
    | MACRO_FUNC
    | MACRO_INVOKE_FUNC
    | MACRO_INVOKE_BODY
    | LEFT_VALUE
    | C
    | SRC_IMPORTED
    | JAVA_APP
    | JAVA_EXT
    | STD_CALL
    | NO_MANGLE
    | INITIALIZATION_CHECKED
    | IS_BROKEN
    | GENERIC_INSTANTIATED
    | HAS_INITIAL
    | IS_VOLATILE
    | NUMERIC_OVERFLOW
    | INTRINSIC
    | TOOL_ADD
    | IS_CHECK_VISITED
    | INCRE_COMPILE
    | SIDE_EFFECT
    | IMPLICIT_ADD
    | MAIN_ENTRY
    | GENERATED_TO_MOCK
    | IS_OUTERMOST
    | IS_ANNOTATION
    | NO_REFLECT_INFO
    | MOCK_SUPPORTED
    | OPEN_TO_MOCK
    | INTERFACE_IMPL
    | FOR_TEST
    | CONTAINS_MOCK_CREATION_CALL
    | COMMON
    | FROM_COMMON_PART
    | COMMON_NON_EXHAUSTIVE
    | SPECIFIC
    | COMMON_WITH_DEFAULT
    | JAVA_FOREIGN
    | JAVA_EXPORT
    | JAVA_HAS_DEFAULT
    | JAVA_FOREIGN_SYNTHETIC_WRAPPER
    | OBJ_C_FOREIGN
    | OBJ_C_EXPORT
    | OBJ_C_INIT
    | OBJ_C_OPTIONAL
    | JAVA_CJ_MAPPING
    | OBJ_C_CJ_MAPPING
    | CJ_MIRROR_JAVA_INTERFACE_FWD
    | DESUGARED_FOREIGN_FIELD
    | HAS_INITED_FIELD
    | OBJ_C_FOREIGN_INTERFACE_HANDLE_WRAPPER
    | CJ_MIRROR_JAVA_INTERFACE_DEFAULT
    | CJ_MIRROR_OBJC_INTERFACE_FWD
    | ALREADY_LOADED
    | JAVA_EXPORT_REGISTRY_COMPANION
    | DOES_NOT_THROW
    | OBJ_C_EXPORT_REGISTRY_COMPANION
    | OBJ_C_EXPORT_MOVED_MEMBER_PROXY
    | AST_ATTR_END
}

public func AttributeIndex(attr: Attribute): Int64 {
    return match (attr) {
        case Attribute.IN_REFERENCE_CYCLE => 0
        case Attribute.UNREACHABLE => 1
        case Attribute.IMPLICIT_USED => 2
        case Attribute.IMPORTED => 3
        case Attribute.GLOBAL => 4
        case Attribute.INITIALIZED => 5
        case Attribute.COMPILER_ADD => 6
        case Attribute.GENERIC => 7
        case Attribute.DEFAULT => 8
        case Attribute.STATIC => 9
        case Attribute.PUBLIC => 10
        case Attribute.PRIVATE => 11
        case Attribute.PROTECTED => 12
        case Attribute.EXTERNAL => 13
        case Attribute.INTERNAL => 14
        case Attribute.OVERRIDE => 15
        case Attribute.REDEF => 16
        case Attribute.ABSTRACT => 17
        case Attribute.SEALED => 18
        case Attribute.OPEN => 19
        case Attribute.OPERATOR => 20
        case Attribute.FOREIGN => 21
        case Attribute.UNSAFE => 22
        case Attribute.MUT => 23
        case Attribute.HAS_BROKEN => 24
        case Attribute.IN_STRUCT => 25
        case Attribute.IN_EXTEND => 26
        case Attribute.IN_ENUM => 27
        case Attribute.IN_CLASSLIKE => 28
        case Attribute.IN_MACRO => 29
        case Attribute.PRIMARY_CONSTRUCTOR => 30
        case Attribute.CONSTRUCTOR => 31
        case Attribute.ENUM_CONSTRUCTOR => 32
        case Attribute.FINALIZER => 33
        case Attribute.IS_CLONED_SOURCE_CODE => 34
        case Attribute.IS_CAPTURE => 35
        case Attribute.IN_CORE => 36
        case Attribute.NEED_AUTO_BOX => 37
        case Attribute.MACRO_EXPANDED_NODE => 38
        case Attribute.MACRO_FUNC => 39
        case Attribute.MACRO_INVOKE_FUNC => 40
        case Attribute.MACRO_INVOKE_BODY => 41
        case Attribute.LEFT_VALUE => 42
        case Attribute.C => 43
        case Attribute.SRC_IMPORTED => 44
        case Attribute.JAVA_APP => 45
        case Attribute.JAVA_EXT => 46
        case Attribute.STD_CALL => 47
        case Attribute.NO_MANGLE => 48
        case Attribute.INITIALIZATION_CHECKED => 49
        case Attribute.IS_BROKEN => 50
        case Attribute.GENERIC_INSTANTIATED => 51
        case Attribute.HAS_INITIAL => 52
        case Attribute.IS_VOLATILE => 53
        case Attribute.NUMERIC_OVERFLOW => 54
        case Attribute.INTRINSIC => 55
        case Attribute.TOOL_ADD => 56
        case Attribute.IS_CHECK_VISITED => 57
        case Attribute.INCRE_COMPILE => 58
        case Attribute.SIDE_EFFECT => 59
        case Attribute.IMPLICIT_ADD => 60
        case Attribute.MAIN_ENTRY => 61
        case Attribute.GENERATED_TO_MOCK => 62
        case Attribute.IS_OUTERMOST => 63
        case Attribute.IS_ANNOTATION => 64
        case Attribute.NO_REFLECT_INFO => 65
        case Attribute.MOCK_SUPPORTED => 66
        case Attribute.OPEN_TO_MOCK => 67
        case Attribute.INTERFACE_IMPL => 68
        case Attribute.FOR_TEST => 69
        case Attribute.CONTAINS_MOCK_CREATION_CALL => 70
        case Attribute.COMMON => 71
        case Attribute.FROM_COMMON_PART => 72
        case Attribute.COMMON_NON_EXHAUSTIVE => 73
        case Attribute.SPECIFIC => 74
        case Attribute.COMMON_WITH_DEFAULT => 75
        case Attribute.JAVA_FOREIGN => 76
        case Attribute.JAVA_EXPORT => 77
        case Attribute.JAVA_HAS_DEFAULT => 78
        case Attribute.JAVA_FOREIGN_SYNTHETIC_WRAPPER => 79
        case Attribute.OBJ_C_FOREIGN => 80
        case Attribute.OBJ_C_EXPORT => 81
        case Attribute.OBJ_C_INIT => 82
        case Attribute.OBJ_C_OPTIONAL => 83
        case Attribute.JAVA_CJ_MAPPING => 84
        case Attribute.OBJ_C_CJ_MAPPING => 85
        case Attribute.CJ_MIRROR_JAVA_INTERFACE_FWD => 86
        case Attribute.DESUGARED_FOREIGN_FIELD => 87
        case Attribute.HAS_INITED_FIELD => 88
        case Attribute.OBJ_C_FOREIGN_INTERFACE_HANDLE_WRAPPER => 89
        case Attribute.CJ_MIRROR_JAVA_INTERFACE_DEFAULT => 90
        case Attribute.CJ_MIRROR_OBJC_INTERFACE_FWD => 91
        case Attribute.ALREADY_LOADED => 92
        case Attribute.JAVA_EXPORT_REGISTRY_COMPANION => 93
        case Attribute.DOES_NOT_THROW => 94
        case Attribute.OBJ_C_EXPORT_REGISTRY_COMPANION => 95
        case Attribute.OBJ_C_EXPORT_MOVED_MEMBER_PROXY => 96
        case Attribute.AST_ATTR_END => 97
    }
}

extend Attribute <: Equatable<Attribute> {
    public operator func ==(right: Attribute): Bool {
        return AttributeIndex(this) == AttributeIndex(right)
    }

    public operator func !=(right: Attribute): Bool {
        return !(this == right)
    }
}

private let ATTRIBUTE_NAMES: Array<String> = [
    "IN_REFERENCE_CYCLE",
    "UNREACHABLE",
    "IMPLICIT_USED",
    "IMPORTED",
    "GLOBAL",
    "INITIALIZED",
    "COMPILER_ADD",
    "GENERIC",
    "DEFAULT",
    "STATIC",
    "PUBLIC",
    "PRIVATE",
    "PROTECTED",
    "EXTERNAL",
    "INTERNAL",
    "OVERRIDE",
    "REDEF",
    "ABSTRACT",
    "SEALED",
    "OPEN",
    "OPERATOR",
    "FOREIGN",
    "UNSAFE",
    "MUT",
    "HAS_BROKEN",
    "IN_STRUCT",
    "IN_EXTEND",
    "IN_ENUM",
    "IN_CLASSLIKE",
    "IN_MACRO",
    "PRIMARY_CONSTRUCTOR",
    "CONSTRUCTOR",
    "ENUM_CONSTRUCTOR",
    "FINALIZER",
    "IS_CLONED_SOURCE_CODE",
    "IS_CAPTURE",
    "IN_CORE",
    "NEED_AUTO_BOX",
    "MACRO_EXPANDED_NODE(deprecated)",
    "MACRO_FUNC",
    "MACRO_INVOKE_FUNC",
    "MACRO_INVOKE_BODY",
    "LEFT_VALUE",
    "C",
    "SRC_IMPORTED",
    "JAVA_APP",
    "JAVA_EXT",
    "STD_CALL",
    "NO_MANGLE",
    "INITIALIZATION_CHECKED",
    "IS_BROKEN",
    "GENERIC_INSTANTIATED",
    "HAS_INITIAL",
    "IS_VOLATILE",
    "NUMERIC_OVERFLOW",
    "INTRINSIC",
    "TOOL_ADD",
    "IS_CHECK_VISITED",
    "INCRE_COMPILE",
    "SIDE_EFFECT",
    "IMPLICIT_ADD",
    "MAIN_ENTRY",
    "GENERATED_TO_MOCK",
    "IS_OUTERMOST",
    "IS_ANNOTATION",
    "NO_REFLECT_INFO",
    "MOCK_SUPPORTED",
    "OPEN_TO_MOCK",
    "INTERFACE_IMPL",
    "FOR_TEST",
    "CONTAINS_MOCK_CREATION_CALL",
    "COMMON",
    "FROM_COMMON_PART",
    "COMMON_NON_EXHAUSTIVE",
    "SPECIFIC",
    "COMMON_WITH_DEFAULT",
    "JAVA_FOREIGN",
    "JAVA_EXPORT",
    "JAVA_HAS_DEFAULT",
    "JAVA_FOREIGN_SYNTHETIC_WRAPPER",
    "OBJ_C_FOREIGN",
    "OBJ_C_EXPORT",
    "OBJ_C_INIT",
    "OBJ_C_OPTIONAL",
    "JAVA_CJ_MAPPING(deprecated)",
    "OBJ_C_CJ_MAPPING(deprecated)",
    "CJ_MIRROR_JAVA_INTERFACE_FWD(deprecated)",
    "DESUGARED_FOREIGN_FIELD",
    "HAS_INITED_FIELD",
    "OBJ_C_FOREIGN_INTERFACE_HANDLE_WRAPPER",
    "CJ_MIRROR_JAVA_INTERFACE_DEFAULT(deprecated)",
    "CJ_MIRROR_OBJC_INTERFACE_FWD(deprecated)",
    "ALREADY_LOADED",
    "JAVA_EXPORT_REGISTRY_COMPANION",
    "DOES_NOT_THROW",
    "OBJ_C_EXPORT_REGISTRY_COMPANION",
    "OBJ_C_EXPORT_MOVED_MEMBER_PROXY",
    "AST_ATTR_END"
]

public func AttributeName(attr: Attribute): String {
    let idx = AttributeIndex(attr)
    if (idx >= ATTRIBUTE_NAMES.size) {
        return "UnknownAttr(${idx})"
    }
    return ATTRIBUTE_NAMES[idx]
}

// Embedded in every Node. The public mutable pack is only needed for snapshots
// and callers that build a pack before installing it on a node.
struct ASTAttributeBits {
    private var lo: UInt64 = 0u64
    private var hi: UInt64 = 0u64

    init() {}

    mut func SetAttr(attr: Attribute, enable: Bool): Unit {
        let index = AttributeIndex(attr)
        let mask = 1u64 << UInt64(index % 64)
        if (index < 64) {
            lo = if (enable) { lo | mask } else { lo & (UInt64.Max ^ mask) }
        } else {
            hi = if (enable) { hi | mask } else { hi & (UInt64.Max ^ mask) }
        }
    }

    func TestAttr(attr: Attribute): Bool {
        let index = AttributeIndex(attr)
        let word = if (index < 64) { lo } else { hi }
        return (word & (1u64 << UInt64(index % 64))) != 0u64
    }

    func GetRawAttrs(): ArrayList<UInt64> {
        let out = ArrayList<UInt64>(2)
        out.add(lo)
        out.add(hi)
        return out
    }

    func GetAllIdxOfAttr(): ArrayList<UInt64> {
        let out = ArrayList<UInt64>(0)
        for (wordIndex in 0..2) {
            let word = if (wordIndex == 0) { lo } else { hi }
            if (word == 0u64) { continue }
            for (bitIndex in 0..64) {
                if ((word & (1u64 << UInt64(bitIndex))) != 0u64) {
                    out.add(UInt64(wordIndex * 64 + bitIndex))
                }
            }
        }
        return out
    }
}

public class AttributePack {
    private var bits: ASTAttributeBits = ASTAttributeBits()

    public init() {}

    public init(other: AttributePack) {
        bits = other.bits
    }

    init(bits: ASTAttributeBits) {
        this.bits = bits
    }

    func GetBits(): ASTAttributeBits {
        return bits
    }

    public func SetAttr(attr: Attribute, enable: Bool): Unit {
        bits.SetAttr(attr, enable)
    }

    public func TestAttr(attr: Attribute): Bool {
        return bits.TestAttr(attr)
    }

    public func GetRawAttrs(): ArrayList<UInt64> {
        return bits.GetRawAttrs()
    }

    public func GetAllIdxOfAttr(): ArrayList<UInt64> {
        return bits.GetAllIdxOfAttr()
    }

    public func Clone(): AttributePack {
        return AttributePack(bits)
    }

    public func ToString(): String {
        let expected = AttributeIndex(Attribute.AST_ATTR_END) + 1
        if (ATTRIBUTE_NAMES.size != expected) {
            return "ATTR2STR has invalid mapping(${ATTRIBUTE_NAMES.size}!=${expected})"
        }
        if (GetAllIdxOfAttr().isEmpty()) {
            return "[]"
        }
        let names = ArrayList<String>()
        for (idx in GetAllIdxOfAttr()) {
            if (idx >= UInt64(ATTRIBUTE_NAMES.size)) {
                names.add("UnknownAttr(${idx})")
            } else {
                names.add(ATTRIBUTE_NAMES[Int64(idx)])
            }
        }
        return "[" + JoinStrings(names, ", ") + "]"
    }
}
