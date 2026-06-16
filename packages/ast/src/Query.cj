package cangjie_compiler::ast

import std.collection.*

public enum QueryKind {
    | ALWAYS
    | NAME
    | SCOPE
    | SCOPE_LEVEL
    | AST_KIND
    | POSITION
    | FILE_HASH
    | AND
    | OR
    | NOT
}

private func QueryKindIndex(kind: QueryKind): Int64 {
    return match (kind) {
        case QueryKind.ALWAYS => 0
        case QueryKind.NAME => 1
        case QueryKind.SCOPE => 2
        case QueryKind.SCOPE_LEVEL => 3
        case QueryKind.AST_KIND => 4
        case QueryKind.POSITION => 5
        case QueryKind.FILE_HASH => 6
        case QueryKind.AND => 7
        case QueryKind.OR => 8
        case QueryKind.NOT => 9
    }
}

extend QueryKind <: Equatable<QueryKind> {
    public operator func ==(right: QueryKind): Bool {
        return QueryKindIndex(this) == QueryKindIndex(right)
    }

    public operator func !=(right: QueryKind): Bool {
        return !(this == right)
    }
}

public enum MatchKind {
    | PRECISE
    | PREFIX
    | SUFFIX
}

private func MatchKindIndex(kind: MatchKind): Int64 {
    return match (kind) {
        case MatchKind.PRECISE => 0
        case MatchKind.PREFIX => 1
        case MatchKind.SUFFIX => 2
    }
}

extend MatchKind <: Equatable<MatchKind> {
    public operator func ==(right: MatchKind): Bool {
        return MatchKindIndex(this) == MatchKindIndex(right)
    }

    public operator func !=(right: MatchKind): Bool {
        return !(this == right)
    }
}

public enum PositionCompare {
    | EQ
    | LT
    | LE
    | GT
    | GE
}

private func PositionCompareIndex(kind: PositionCompare): Int64 {
    return match (kind) {
        case PositionCompare.EQ => 0
        case PositionCompare.LT => 1
        case PositionCompare.LE => 2
        case PositionCompare.GT => 3
        case PositionCompare.GE => 4
    }
}

extend PositionCompare <: Equatable<PositionCompare> {
    public operator func ==(right: PositionCompare): Bool {
        return PositionCompareIndex(this) == PositionCompareIndex(right)
    }

    public operator func !=(right: PositionCompare): Bool {
        return !(this == right)
    }
}

public open class Query {
    public let kind: QueryKind
    public init(kind: QueryKind) {
        this.kind = kind
    }

    public open func Match(symbol: Symbol): Bool {
        return symbol.name == symbol.name
    }

    public open func PrettyPrint(): String {
        return "*"
    }
}

private func stringMatches(value: String, expected: String, matchKind: MatchKind): Bool {
    if (matchKind == MatchKind.PREFIX) {
        return value.startsWith(expected)
    }
    if (matchKind == MatchKind.SUFFIX) {
        return value.endsWith(expected)
    }
    return value == expected
}

public class NameQuery <: Query {
    public var value: String = ""
    public var matchKind: MatchKind = MatchKind.PRECISE

    public init(value: String, matchKind!: MatchKind = MatchKind.PRECISE) {
        super(QueryKind.NAME)
        this.value = value
        this.matchKind = matchKind
    }

    public override func Match(symbol: Symbol): Bool {
        return stringMatches(symbol.name, value, matchKind)
    }

    public override func PrettyPrint(): String {
        return "name=${printPattern(value, matchKind)}"
    }
}

public class ScopeQuery <: Query {
    public var value: String = ""
    public var matchKind: MatchKind = MatchKind.PRECISE

    public init(value: String, matchKind!: MatchKind = MatchKind.PRECISE) {
        super(QueryKind.SCOPE)
        this.value = value
        this.matchKind = matchKind
    }

    public override func Match(symbol: Symbol): Bool {
        if (matchKind == MatchKind.SUFFIX) {
            return false
        }
        return stringMatches(GetScopeNameWithoutTail(symbol.scopeName), value, matchKind)
    }

    public override func PrettyPrint(): String {
        return "scope_name=${printPattern(value, matchKind)}"
    }
}

public class ASTKindQuery <: Query {
    public var value: ASTKind = ASTKind.NODE
    public var valueText: String = ""
    public var matchKind: MatchKind = MatchKind.PRECISE

    public init(value: ASTKind) {
        super(QueryKind.AST_KIND)
        this.value = value
        valueText = ASTKindName(value)
    }

    public init(value: String, matchKind!: MatchKind = MatchKind.PRECISE) {
        super(QueryKind.AST_KIND)
        valueText = value
        this.matchKind = matchKind
    }

    public override func Match(symbol: Symbol): Bool {
        if (matchKind == MatchKind.PREFIX) {
            return false
        }
        if (let Some(node) <- symbol.node) {
            return stringMatches(ASTKindName(node.astKind), valueText, matchKind)
        }
        return false
    }

    public override func PrettyPrint(): String {
        return "ast_kind=${printPattern(valueText, matchKind)}"
    }
}

public class ScopeLevelQuery <: Query {
    public var level: UInt32 = 0u32

    public init(level: UInt32) {
        super(QueryKind.SCOPE_LEVEL)
        this.level = level
    }

    public override func Match(symbol: Symbol): Bool {
        if (let Some(node) <- symbol.node) {
            return node.scopeLevel == level
        }
        return false
    }

    public override func PrettyPrint(): String {
        return "scope_level=${level}"
    }
}

public class FileHashQuery <: Query {
    public var fileHash: UInt64 = 0

    public init(fileHash: UInt64) {
        super(QueryKind.FILE_HASH)
        this.fileHash = fileHash
    }

    public override func Match(symbol: Symbol): Bool {
        if (let Some(node) <- symbol.node) {
            if (let Some(file) <- node.curFile) {
                return file.fileHash == fileHash
            }
        }
        return false
    }

    public override func PrettyPrint(): String {
        return "fileHash:${fileHash}"
    }
}

public class PositionQuery <: Query {
    public var pos: Position = INVALID_POSITION
    public var comparator: PositionCompare = PositionCompare.EQ

    public init(pos: Position, comparator!: PositionCompare = PositionCompare.EQ) {
        super(QueryKind.POSITION)
        this.pos = pos
        this.comparator = comparator
    }

    public override func Match(symbol: Symbol): Bool {
        if (let Some(node) <- symbol.node) {
            let begin = node.GetBegin()
            let end = node.GetEnd()
            let contains = ComparePosition(begin, pos) <= 0 && ComparePosition(pos, end) <= 0
            if (comparator == PositionCompare.EQ) {
                return contains
            }
            if (comparator == PositionCompare.LT) {
                return ComparePosition(end, pos) < 0
            }
            if (comparator == PositionCompare.LE) {
                return ComparePosition(end, pos) < 0 || contains
            }
            if (comparator == PositionCompare.GT) {
                return ComparePosition(begin, pos) > 0
            }
            return ComparePosition(begin, pos) > 0 || contains
        }
        return false
    }

    public override func PrettyPrint(): String {
        let op = match (comparator) {
            case PositionCompare.EQ => "="
            case PositionCompare.LT => "<"
            case PositionCompare.LE => "<="
            case PositionCompare.GT => ">"
            case PositionCompare.GE => ">="
        }
        return "_${op}${pos.ToString()}"
    }
}

private func ComparePosition(left: Position, right: Position): Int64 {
    if (left.fileID < right.fileID) {
        return -1
    }
    if (left.fileID > right.fileID) {
        return 1
    }
    if (left < right) {
        return -1
    }
    if (right < left) {
        return 1
    }
    return 0
}

private func printPattern(value: String, matchKind: MatchKind): String {
    if (matchKind == MatchKind.PREFIX) {
        return value + "*"
    }
    if (matchKind == MatchKind.SUFFIX) {
        return "*" + value
    }
    return value
}

public class CompoundQuery <: Query {
    public let children: ArrayList<Query> = ArrayList<Query>()

    public init(kind: QueryKind) {
        super(kind)
    }

    public override func Match(symbol: Symbol): Bool {
        if (kind == QueryKind.AND) {
            for (child in children) {
                if (!child.Match(symbol)) {
                    return false
                }
            }
            return true
        }
        if (kind == QueryKind.OR) {
            for (child in children) {
                if (child.Match(symbol)) {
                    return true
                }
            }
            return false
        }
        if (kind == QueryKind.NOT) {
            if (children.size == 1) {
                return !children[0].Match(symbol)
            }
            if (children.size >= 2) {
                return children[0].Match(symbol) && !children[1].Match(symbol)
            }
        }
        return true
    }

    public override func PrettyPrint(): String {
        if (children.isEmpty()) {
            return "*"
        }
        if (kind == QueryKind.NOT && children.size == 1) {
            return "!(" + children[0].PrettyPrint() + ")"
        }
        let op = if (kind == QueryKind.AND) { "&&" } else if (kind == QueryKind.OR) { "||" } else { "!" }
        var out = "(" + children[0].PrettyPrint()
        var idx: Int64 = 1
        while (idx < children.size) {
            out += op + children[idx].PrettyPrint()
            idx++
        }
        return out + ")"
    }
}

private enum QueryTokenKind {
    | IDENT
    | COLON
    | STAR
    | LPAREN
    | RPAREN
    | COMMA
    | AND
    | OR
    | NOT
    | EQ
    | LT
    | LE
    | GT
    | GE
    | END
}

private func QueryTokenKindIndex(kind: QueryTokenKind): Int64 {
    return match (kind) {
        case QueryTokenKind.IDENT => 0
        case QueryTokenKind.COLON => 1
        case QueryTokenKind.STAR => 2
        case QueryTokenKind.LPAREN => 3
        case QueryTokenKind.RPAREN => 4
        case QueryTokenKind.COMMA => 5
        case QueryTokenKind.AND => 6
        case QueryTokenKind.OR => 7
        case QueryTokenKind.NOT => 8
        case QueryTokenKind.EQ => 9
        case QueryTokenKind.LT => 10
        case QueryTokenKind.LE => 11
        case QueryTokenKind.GT => 12
        case QueryTokenKind.GE => 13
        case QueryTokenKind.END => 14
    }
}

extend QueryTokenKind <: Equatable<QueryTokenKind> {
    public operator func ==(right: QueryTokenKind): Bool {
        return QueryTokenKindIndex(this) == QueryTokenKindIndex(right)
    }

    public operator func !=(right: QueryTokenKind): Bool {
        return !(this == right)
    }
}

private class QueryToken {
    public var kind: QueryTokenKind = QueryTokenKind.END
    public var text: String = ""
    public init(kind: QueryTokenKind, text: String) {
        this.kind = kind
        this.text = text
    }
}

private class QueryParser {
    private let tokens: ArrayList<QueryToken> = ArrayList<QueryToken>()
    private var index: Int64 = 0

    public init(input: String) {
        tokenize(input)
    }

    public func Parse(): Query {
        if (tokens.isEmpty()) {
            return Query(QueryKind.ALWAYS)
        }
        let query = parseBoolean()
        return query
    }

    private func current(): QueryToken {
        if (index < tokens.size) {
            return tokens[index]
        }
        return QueryToken(QueryTokenKind.END, "")
    }

    private func advance(): QueryToken {
        let token = current()
        if (index < tokens.size) {
            index++
        }
        return token
    }

    private func matchToken(kind: QueryTokenKind): Bool {
        if (current().kind == kind) {
            index++
            return true
        }
        return false
    }

    private func parseBoolean(): Query {
        var left = parseUnary()
        while (current().kind == QueryTokenKind.AND || current().kind == QueryTokenKind.OR ||
            current().kind == QueryTokenKind.NOT) {
            let opToken = advance()
            let right = parseUnary()
            let compoundKind = if (opToken.kind == QueryTokenKind.AND) {
                QueryKind.AND
            } else if (opToken.kind == QueryTokenKind.OR) {
                QueryKind.OR
            } else {
                QueryKind.NOT
            }
            let combined = CompoundQuery(compoundKind)
            combined.children.add(left)
            combined.children.add(right)
            left = combined
        }
        return left
    }

    private func parseUnary(): Query {
        if (matchToken(QueryTokenKind.NOT)) {
            let query = CompoundQuery(QueryKind.NOT)
            query.children.add(parseUnary())
            return query
        }
        if (matchToken(QueryTokenKind.LPAREN)) {
            let inner = parseBoolean()
            matchToken(QueryTokenKind.RPAREN)
            return inner
        }
        return parseTerm()
    }

    private func parseTerm(): Query {
        let keyToken = advance()
        if (keyToken.kind != QueryTokenKind.IDENT) {
            return Query(QueryKind.ALWAYS)
        }
        if (keyToken.text == "_") {
            return parsePositionTerm()
        }
        if (!matchToken(QueryTokenKind.COLON)) {
            return NameQuery(keyToken.text)
        }
        var matchKind = MatchKind.PRECISE
        var value = ""
        if (matchToken(QueryTokenKind.STAR)) {
            matchKind = MatchKind.SUFFIX
        }
        let valueToken = advance()
        if (valueToken.kind == QueryTokenKind.IDENT) {
            value = valueToken.text
        }
        if (matchToken(QueryTokenKind.STAR)) {
            matchKind = MatchKind.PREFIX
        }
        if (keyToken.text == "name") {
            return NameQuery(value, matchKind: matchKind)
        }
        if (keyToken.text == "scope_name" || keyToken.text == "scopeName" || keyToken.text == "scope") {
            return ScopeQuery(value, matchKind: matchKind)
        }
        if (keyToken.text == "ast_kind" || keyToken.text == "astKind" || keyToken.text == "kind") {
            return ASTKindQuery(value, matchKind: matchKind)
        }
        if (keyToken.text == "scope_level" || keyToken.text == "scopeLevel" || keyToken.text == "level") {
            return ScopeLevelQuery(UInt32(parseUInt(value)))
        }
        if (keyToken.text == "fileHash") {
            return FileHashQuery(parseUInt(value))
        }
        return NameQuery(value, matchKind: matchKind)
    }

    private func parsePositionTerm(): Query {
        var cmp = PositionCompare.EQ
        if (matchToken(QueryTokenKind.EQ)) {
            cmp = PositionCompare.EQ
        } else if (matchToken(QueryTokenKind.LE)) {
            cmp = PositionCompare.LE
        } else if (matchToken(QueryTokenKind.LT)) {
            cmp = PositionCompare.LT
        } else if (matchToken(QueryTokenKind.GE)) {
            cmp = PositionCompare.GE
        } else if (matchToken(QueryTokenKind.GT)) {
            cmp = PositionCompare.GT
        }
        matchToken(QueryTokenKind.LPAREN)
        let file = parseUInt(advance().text)
        matchToken(QueryTokenKind.COMMA)
        let line = Int64(parseUInt(advance().text))
        matchToken(QueryTokenKind.COMMA)
        let column = Int64(parseUInt(advance().text))
        matchToken(QueryTokenKind.RPAREN)
        return PositionQuery(Position(file, line, column), comparator: cmp)
    }

    private func tokenize(input: String): Unit {
        var pos: Int64 = 0
        while (pos < input.size) {
            let ch = input[pos]
            if (ch == b' ' || ch == b'\t' || ch == b'\n' || ch == b'\r') {
                pos++
            } else if (ch == b':') {
                tokens.add(QueryToken(QueryTokenKind.COLON, ":"))
                pos++
            } else if (ch == b'*') {
                tokens.add(QueryToken(QueryTokenKind.STAR, "*"))
                pos++
            } else if (ch == b'(') {
                tokens.add(QueryToken(QueryTokenKind.LPAREN, "("))
                pos++
            } else if (ch == b')') {
                tokens.add(QueryToken(QueryTokenKind.RPAREN, ")"))
                pos++
            } else if (ch == b',') {
                tokens.add(QueryToken(QueryTokenKind.COMMA, ","))
                pos++
            } else if (ch == b'&' && pos + 1 < input.size && input[pos + 1] == b'&') {
                tokens.add(QueryToken(QueryTokenKind.AND, "&&"))
                pos += 2
            } else if (ch == b'|' && pos + 1 < input.size && input[pos + 1] == b'|') {
                tokens.add(QueryToken(QueryTokenKind.OR, "||"))
                pos += 2
            } else if (ch == b'!') {
                tokens.add(QueryToken(QueryTokenKind.NOT, "!"))
                pos++
            } else if (ch == b'=' ) {
                tokens.add(QueryToken(QueryTokenKind.EQ, "="))
                pos++
            } else if (ch == b'<' && pos + 1 < input.size && input[pos + 1] == b'=') {
                tokens.add(QueryToken(QueryTokenKind.LE, "<="))
                pos += 2
            } else if (ch == b'<') {
                tokens.add(QueryToken(QueryTokenKind.LT, "<"))
                pos++
            } else if (ch == b'>' && pos + 1 < input.size && input[pos + 1] == b'=') {
                tokens.add(QueryToken(QueryTokenKind.GE, ">="))
                pos += 2
            } else if (ch == b'>') {
                tokens.add(QueryToken(QueryTokenKind.GT, ">"))
                pos++
            } else {
                let start = pos
                while (pos < input.size && isIdentByte(input[pos])) {
                    pos++
                }
                if (start == pos) {
                    pos++
                } else {
                    tokens.add(QueryToken(QueryTokenKind.IDENT, input[start..pos]))
                }
            }
        }
    }

    private func isIdentByte(ch: UInt8): Bool {
        return (ch >= b'a' && ch <= b'z') || (ch >= b'A' && ch <= b'Z') ||
            (ch >= b'0' && ch <= b'9') || ch == b'_' || ch == b'-' || ch == b'.' || ch == b'$'
    }

    private func parseUInt(text: String): UInt64 {
        var out: UInt64 = 0
        for (byte in text.toArray()) {
            if (byte >= b'0' && byte <= b'9') {
                out = out * 10 + UInt64(byte - b'0')
            }
        }
        return out
    }
}

public func ParseQuery(input: String): Query {
    if (input.isEmpty()) {
        return Query(QueryKind.ALWAYS)
    }
    return QueryParser(input).Parse()
}
