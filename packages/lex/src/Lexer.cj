package cangjie_compiler::lex

import cangjie_compiler::basic.*
import std.collection.*

public class Lexer {
    private let impl: LexerImpl

    public init(fileID: UInt64, input: String, diag: DiagnosticEngine, sm: SourceManager, cts!: Bool = false) {
        impl = LexerImpl(input, diag, sm, LexerConfig(fileID: fileID, posBase: Position(fileID, 1, 1), collectTokenStream: cts))
    }

    public init(fileID: UInt64, input: String, diag: DiagnosticEngine, sm: SourceManager, pos: Position) {
        impl = LexerImpl(input, diag, sm, LexerConfig(fileID: fileID, posBase: pos))
    }

    public init(input: String, diag: DiagnosticEngine, sm: SourceManager, cts!: Bool = false, splitAmbi!: Bool = true) {
        impl = LexerImpl(input, diag, sm, LexerConfig(collectTokenStream: cts, splitAmbiguousToken: splitAmbi))
    }

    public init(input: String, diag: DiagnosticEngine, sm: SourceManager, pos: Position, cts!: Bool = false) {
        impl = LexerImpl(input, diag, sm, LexerConfig(posBase: pos, collectTokenStream: cts))
    }

    public init(input: String, diag: DiagnosticEngine, source: Source, pos: Position, cts!: Bool = false) {
        impl = LexerImpl(input, diag, source, LexerConfig(posBase: pos, collectTokenStream: cts))
    }

    public init(inputTokens: Array<Token>, diag: DiagnosticEngine, sm: SourceManager, cts!: Bool = false) {
        impl = LexerImpl(inputTokens, diag, sm, LexerConfig(collectTokenStream: cts))
    }

    public func Next(): Token {
        return impl.Next()
    }

    public func LookAhead(num: Int64): ArrayList<Token> {
        return impl.LookAhead(num)
    }

    public func Seeing(kinds: Array<TokenKind>, skipNewline!: Bool = false, skipComments!: Bool = true): Bool {
        return impl.Seeing(kinds, skipNewline: skipNewline, skipComments: skipComments)
    }

    public func LookAheadSkipNL(num: Int64): ArrayList<Token> {
        return impl.LookAheadSkipNL(num)
    }

    public func GetComments(): Array<Token> {
        return impl.GetComments().toArray()
    }

    public func GetTokenStream(): HashSet<Token> {
        return impl.GetTokenStream()
    }

    public func EnterQuoteMod(): Unit {
        impl.EnterQuoteMod()
    }

    public func ExitQuoteMod(): Unit {
        impl.ExitQuoteMod()
    }

    public func EnterNormalMod(): Unit {
        impl.EnterNormalMod()
    }

    public func ExitNormalMod(): Unit {
        impl.ExitNormalMod()
    }

    public func SetResetPoint(): Unit {
        impl.SetResetPoint()
    }

    public func Reset(): Unit {
        impl.Reset()
    }

    public func GetPosBase(): Position {
        return impl.GetPosBase()
    }

    public func GetFileID(): UInt64 {
        return impl.GetFileID()
    }

    public func ClearStringParts(t: Token): Unit {
        impl.ClearStringParts(t)
    }

    public func SetEHEnabled(enabled: Bool): Unit {
        impl.SetEHEnabled(enabled)
    }

    public func GetStrParts(t: Token): ArrayList<StringPart> {
        return impl.GetStrParts(t)
    }

    public func GetTokens(): Array<Token> {
        return impl.GetTokens()
    }

    public func GetCollectTokens(): Array<Token> {
        return impl.GetCollectTokens()
    }

    public func StartCollectTokens(): Bool {
        return impl.StartCollectTokens()
    }

    public func StopCollectTokens(bStart: Bool): Unit {
        impl.StopCollectTokens(bStart)
    }

    public func GetCurrentToken(): Int64 {
        return impl.GetCurrentToken()
    }
}

public func ProcessQuotaMarks(value: String, processSingle!: Bool = false): String {
    var inDollar = false
    var leftCurl: Int64 = 0
    var quoteNum: Int64 = 0
    let builder = StringBuilder()
    let bytes = value.toArray()
    var index: Int64 = 0
    while (index < bytes.size) {
        let ch = bytes[index]
        let existing = builder.toString()
        if (!existing.isEmpty() && existing[existing.size - 1] == b'$' && ch == b'{') {
            inDollar = true
        }
        if (inDollar && ch == b'{') {
            leftCurl++
        }
        if (inDollar && ch == b'}') {
            if (leftCurl > 0) {
                leftCurl--
            }
            if (leftCurl == 0) {
                inDollar = false
            }
        }
        if (inDollar) {
            builder.append(String.fromUtf8([ch]))
            index++
            continue
        }
        if (ch == b'"' && (existing.isEmpty() || existing[existing.size - 1] != b'\\')) {
            quoteNum++
            if (quoteNum == 3) {
                quoteNum = 0
                builder.append("\\\"\\\"\\\"")
            }
            index++
            continue
        }
        while (quoteNum > 0) {
            builder.append(if (processSingle) { "\\\"" } else { "\"" })
            quoteNum--
        }
        builder.append(String.fromUtf8([ch]))
        index++
    }
    while (quoteNum > 0) {
        builder.append(if (processSingle) { "\\\"" } else { "\"" })
        quoteNum--
    }
    return builder.toString()
}
