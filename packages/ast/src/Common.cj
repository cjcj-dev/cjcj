package cangjie_compiler::ast

public import cangjie_compiler::basic.{
    BEGIN_POSITION, DEFAULT_POSITION, INVALID_POSITION, Linkage, MacroCallDiagInfo, MakeRange, Position, PositionStatus,
    Range
}
public import cangjie_compiler::lex.{
    GetContextualKeyword, GetEscapeTokenKinds, IsContextualKeyword, IsExperimental, Len, StringPart, StringPartKind,
    StringPartKindIndex, Token, TokenKind, TokenKindIndex, TokenKindLiteral, TokenKindValue, TokenPrecedence, TokenVecMap
}
public import cangjie_compiler::utils.{OverflowStrategy, OverflowStrategyIndex, OverflowStrategyName}
import std.collection.*

// C++ AST consumes these support types from Basic/Lex/Utils. The public imports
// above re-export them through cangjie_compiler::ast without owning local copies.
public func TokenKindText(kind: TokenKind): String {
    return TokenKindLiteral(kind)
}

public enum ScopeKind {
    | UNKNOWN
}

public enum ExprKind {
    | UNKNOWN
}

public enum InteropCJStrategy {
    | FULL
    | NONE
    | UNKNOWN
}

public enum InteropCJGenericStrategyType {
    | NONE
    | PARTIAL
    | UNKNOWN
}

public class GenericTypeArguments {
    public let typeArguments: ArrayList<String> = ArrayList<String>()
    public init() {}
}

public class LambdaPattern {
    public var name: String = ""
    public init() {}
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
