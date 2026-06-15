package cangjie_compiler::ast

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
    | JAVA_MIRROR
    | JAVA_MIRROR_SUBTYPE
    | JAVA_HAS_DEFAULT
    | JAVA_MIRROR_SYNTHETIC_WRAPPER
    | OBJ_C_MIRROR
    | OBJ_C_MIRROR_SUBTYPE
    | OBJ_C_INIT
    | OBJ_C_OPTIONAL
    | JAVA_CJ_MAPPING
    | OBJ_C_CJ_MAPPING
    | CJ_MIRROR_JAVA_INTERFACE_FWD
    | DESUGARED_MIRROR_FIELD
    | HAS_INITED_FIELD
    | OBJ_C_MIRROR_SYNTHETIC_WRAPPER
    | CJ_MIRROR_JAVA_INTERFACE_DEFAULT
    | CJ_MIRROR_OBJC_INTERFACE_FWD
    | ALREADY_LOADED
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
        case Attribute.JAVA_MIRROR => 76
        case Attribute.JAVA_MIRROR_SUBTYPE => 77
        case Attribute.JAVA_HAS_DEFAULT => 78
        case Attribute.JAVA_MIRROR_SYNTHETIC_WRAPPER => 79
        case Attribute.OBJ_C_MIRROR => 80
        case Attribute.OBJ_C_MIRROR_SUBTYPE => 81
        case Attribute.OBJ_C_INIT => 82
        case Attribute.OBJ_C_OPTIONAL => 83
        case Attribute.JAVA_CJ_MAPPING => 84
        case Attribute.OBJ_C_CJ_MAPPING => 85
        case Attribute.CJ_MIRROR_JAVA_INTERFACE_FWD => 86
        case Attribute.DESUGARED_MIRROR_FIELD => 87
        case Attribute.HAS_INITED_FIELD => 88
        case Attribute.OBJ_C_MIRROR_SYNTHETIC_WRAPPER => 89
        case Attribute.CJ_MIRROR_JAVA_INTERFACE_DEFAULT => 90
        case Attribute.CJ_MIRROR_OBJC_INTERFACE_FWD => 91
        case Attribute.ALREADY_LOADED => 92
        case Attribute.AST_ATTR_END => 93
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

public func AttributeName(attr: Attribute): String {
    return "Attribute#${AttributeIndex(attr)}"
}

public class AttributePack {
    private let enabled: ArrayList<Attribute> = ArrayList<Attribute>()

    public init() {}

    public init(other: AttributePack) {
        for (attr in other.enabled) {
            enabled.add(attr)
        }
    }

    public func SetAttr(attr: Attribute, enable: Bool): Unit {
        if (enable) {
            if (!TestAttr(attr)) {
                enabled.add(attr)
            }
            return
        }
        var idx: Int64 = 0
        while (idx < enabled.size) {
            if (enabled[idx] == attr) {
                enabled.remove(at: idx)
                return
            }
            idx++
        }
    }

    public func TestAttr(attr: Attribute): Bool {
        for (item in enabled) {
            if (item == attr) {
                return true
            }
        }
        return false
    }

    public func GetAllIdxOfAttr(): ArrayList<UInt64> {
        let out = ArrayList<UInt64>()
        for (attr in enabled) {
            out.add(UInt64(AttributeIndex(attr)))
        }
        return out
    }

    public func Clone(): AttributePack {
        return AttributePack(this)
    }

    public func ToString(): String {
        if (enabled.isEmpty()) {
            return "[]"
        }
        let names = ArrayList<String>()
        for (attr in enabled) {
            names.add(AttributeName(attr))
        }
        return "[" + JoinStrings(names, ", ") + "]"
    }
}
