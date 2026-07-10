package cjcj::ast

public import cjcj::basic.{
    BEGIN_POSITION, ClassMapping, DEFAULT_POSITION, GenericTypeArguments, INVALID_POSITION, InteropCJGenericStrategyType,
    InteropCJStrategy, LambdaPattern, Linkage, MacroCallDiagInfo, MakeRange, Position, PositionStatus, Range
}
public import cjcj::lex.{
    GetContextualKeyword, GetEscapeTokenKinds, IsContextualKeyword, IsExperimental, Len, StringPart, StringPartKind,
    StringPartKindIndex, Token, TokenKind, TokenKindIndex, TokenKindLiteral, TokenKindValue, TokenPrecedence, TokenVecMap
}
public import cjcj::utils.{OverflowStrategy, OverflowStrategyIndex, OverflowStrategyName}
import std.collection.*

// C++ AST consumes these support types from Basic/Lex/Utils. The public imports
// above re-export them through cjcj::ast without owning local copies.
public func TokenKindText(kind: TokenKind): String {
    return TokenKindLiteral(kind)
}

public enum ScopeKind {
    | TOPLEVEL
    | CLASS_BODY
    | INTERFACE_BODY
    | STRUCT_BODY
    | EXTEND_BODY
    | FUNC_BODY
    | MACRO_BODY
    | PRIMARY_CONSTRUCTOR_BODY_FOR_CLASS
    | PRIMARY_CONSTRUCTOR_BODY_FOR_STRUCT
    | PROP_MEMBER_SETTER_BODY
    | PROP_MEMBER_GETTER_BODY
    | ENUM_BODY
    | ENUM_CONSTRUCTOR
    | PRIMARY_CONSTRUCTOR_FUNC_PARAM
    | MAIN_BODY
    | UNKNOWN_SCOPE
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

    public operator func !=(right: ScopeKind): Bool {
        return !(this == right)
    }
}

public enum ExprKind {
    | ALL
    | VAR_INIT
    | INDEX_EXPR
    | IF_COND_EXPR
    | WHILE_COND_EXPR
    | LET_PATTERN
    | LEFT_EXPR
    | EXPR_IN_TUPLE
    | EXPR_IN_IF_COND_TUPLE
    | EXPR_IN_WHILE_COND_TUPLE
    | EXPR_IN_ARRAY
    | EXPR_IN_CALLSUFFIX
    | EXPR_IN_ANNOTATION
    | UNKNOWN_EXPR
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
    public operator func ==(right: ExprKind): Bool {
        return ExprKindIndex(this) == ExprKindIndex(right)
    }

    public operator func !=(right: ExprKind): Bool {
        return !(this == right)
    }
}

public func EscapeToJsonString(input: String): String {
    let builder = StringBuilder()
    for (byte in input.toArray()) {
        match (byte) {
            case b'\\' => builder.append("\\\\")
            case b'"' => builder.append("\\\"")
            case b'\n' => builder.append("\\n")
            case b'\r' => builder.append("\\r")
            case b'\t' => builder.append("\\t")
            case b'\b' => builder.append("\\b")
            case b'\f' => builder.append("\\f")
            case _ => builder.append(String.fromUtf8([byte]))
        }
    }
    return builder.toString()
}

public func JoinStrings(values: ArrayList<String>, delimiter: String): String {
    let builder = StringBuilder()
    for (idx in 0..values.size) {
        if (idx > 0) {
            builder.append(delimiter)
        }
        builder.append(values[idx])
    }
    return builder.toString()
}
