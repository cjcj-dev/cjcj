package cangjie_compiler::parse

import std.collection.*

public enum ScopeKind {
    | TOPLEVEL | CLASS_BODY | INTERFACE_BODY | STRUCT_BODY | EXTEND_BODY | FUNC_BODY | MACRO_BODY
    | PRIMARY_CONSTRUCTOR_BODY_FOR_CLASS | PRIMARY_CONSTRUCTOR_BODY_FOR_STRUCT
    | PROP_MEMBER_SETTER_BODY | PROP_MEMBER_GETTER_BODY | ENUM_BODY | ENUM_CONSTRUCTOR
    | PRIMARY_CONSTRUCTOR_FUNC_PARAM | MAIN_BODY | UNKNOWN_SCOPE
}

private func ScopeKindIndex(kind: ScopeKind): Int64 {
    return match (kind) {
        case ScopeKind.TOPLEVEL => 0
        case ScopeKind.CLASS_BODY => 1
        case ScopeKind.INTERFACE_BODY => 2
        case ScopeKind.STRUCT_BODY => 3
        case ScopeKind.EXTEND_BODY => 4
        case ScopeKind.FUNC_BODY => 5
        case ScopeKind.MACRO_BODY => 6
        case ScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_CLASS => 7
        case ScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_STRUCT => 8
        case ScopeKind.PROP_MEMBER_SETTER_BODY => 9
        case ScopeKind.PROP_MEMBER_GETTER_BODY => 10
        case ScopeKind.ENUM_BODY => 11
        case ScopeKind.ENUM_CONSTRUCTOR => 12
        case ScopeKind.PRIMARY_CONSTRUCTOR_FUNC_PARAM => 13
        case ScopeKind.MAIN_BODY => 14
        case ScopeKind.UNKNOWN_SCOPE => 15
    }
}

extend ScopeKind <: Equatable<ScopeKind> {
    public operator func ==(right: ScopeKind): Bool {
        return ScopeKindIndex(this) == ScopeKindIndex(right)
    }
    public operator func !=(right: ScopeKind): Bool { return !(this == right) }
}

public enum DefKind {
    | FUNC | MAIN | MACRO | CLASS | INTERFACE | VARIABLE | ENUM | STRUCT | EXTEND | TYPE
    | CONSTRUCTOR | PRIMARY_CONSTRUCTOR | PROPERTY | FINALIZER | PACKAGE
}

private func DefKindIndex(kind: DefKind): Int64 {
    return match (kind) {
        case DefKind.FUNC => 0
        case DefKind.MAIN => 1
        case DefKind.MACRO => 2
        case DefKind.CLASS => 3
        case DefKind.INTERFACE => 4
        case DefKind.VARIABLE => 5
        case DefKind.ENUM => 6
        case DefKind.STRUCT => 7
        case DefKind.EXTEND => 8
        case DefKind.TYPE => 9
        case DefKind.CONSTRUCTOR => 10
        case DefKind.PRIMARY_CONSTRUCTOR => 11
        case DefKind.PROPERTY => 12
        case DefKind.FINALIZER => 13
        case DefKind.PACKAGE => 14
    }
}

extend DefKind <: Equatable<DefKind> {
    public operator func ==(right: DefKind): Bool { return DefKindIndex(this) == DefKindIndex(right) }
    public operator func !=(right: DefKind): Bool { return !(this == right) }
}

public enum ExprKind {
    | ALL | VAR_INIT | INDEX_EXPR | IF_COND_EXPR | WHILE_COND_EXPR | LET_PATTERN | LEFT_EXPR
    | EXPR_IN_TUPLE | EXPR_IN_IF_COND_TUPLE | EXPR_IN_WHILE_COND_TUPLE | EXPR_IN_ARRAY
    | EXPR_IN_CALLSUFFIX | EXPR_IN_ANNOTATION | UNKNOWN_EXPR
}

private func ExprKindIndex(kind: ExprKind): Int64 {
    return match (kind) {
        case ExprKind.ALL => 0
        case ExprKind.VAR_INIT => 1
        case ExprKind.INDEX_EXPR => 2
        case ExprKind.IF_COND_EXPR => 3
        case ExprKind.WHILE_COND_EXPR => 4
        case ExprKind.LET_PATTERN => 5
        case ExprKind.LEFT_EXPR => 6
        case ExprKind.EXPR_IN_TUPLE => 7
        case ExprKind.EXPR_IN_IF_COND_TUPLE => 8
        case ExprKind.EXPR_IN_WHILE_COND_TUPLE => 9
        case ExprKind.EXPR_IN_ARRAY => 10
        case ExprKind.EXPR_IN_CALLSUFFIX => 11
        case ExprKind.EXPR_IN_ANNOTATION => 12
        case ExprKind.UNKNOWN_EXPR => 13
    }
}

extend ExprKind <: Equatable<ExprKind> {
    public operator func ==(right: ExprKind): Bool { return ExprKindIndex(this) == ExprKindIndex(right) }
    public operator func !=(right: ExprKind): Bool { return !(this == right) }
}

public enum InteropLanguage {
    | NA | C | JAVA | OBJC
}

public enum OutputMode {
    | UNKNOWN | CHIR | OBJECT | EXECUTABLE
}

private func OutputModeIndex(kind: OutputMode): Int64 {
    return match (kind) {
        case OutputMode.UNKNOWN => 0
        case OutputMode.CHIR => 1
        case OutputMode.OBJECT => 2
        case OutputMode.EXECUTABLE => 3
    }
}

extend OutputMode <: Equatable<OutputMode> {
    public operator func ==(right: OutputMode): Bool { return OutputModeIndex(this) == OutputModeIndex(right) }
    public operator func !=(right: OutputMode): Bool { return !(this == right) }
}

public class GlobalOptions {
    public var enableEH: Bool = false
    public var interopLanguage: InteropLanguage = InteropLanguage.NA
    public var outputMode: OutputMode = OutputMode.UNKNOWN
    public let commonPartCjos: ArrayList<String> = ArrayList<String>()
    public init() {}
}

public enum BackendType {
    | CJNATIVE | JVM | JS
}

public class Triple {
    public init() {}
}
