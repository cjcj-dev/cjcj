package cangjie_compiler::parse

import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import std.collection.*

public class Parser {
    private let impl: ParserImpl

    public init(fileID: UInt64, input: String, diag: DiagnosticEngine, sm: SourceManager, attachComment!: Bool = false, parseDeclFile!: Bool = false) {
        impl = ParserImpl(fileID, input, diag, sm, attachComment, parseDeclFile)
    }

    public init(input: String, diag: DiagnosticEngine, sm: SourceManager, pos!: Position = Position(0, 1, 1), attachComment!: Bool = false, parseDeclFile!: Bool = false) {
        impl = ParserImpl(input, diag, sm, pos, attachComment, parseDeclFile)
    }

    public init(inputTokens: Array<Token>, diag: DiagnosticEngine, sm: SourceManager, attachComment!: Bool = false, parseDeclFile!: Bool = false) {
        impl = ParserImpl(inputTokens, diag, sm, attachComment, parseDeclFile)
    }

    public func GetLineNum(): Int64 { return impl.GetLineNum() }
    public func ParseTopLevel(): File { return impl.ParseTopLevel() }
    public func ParseDecl(scopeKind: ScopeKind): Decl {
        let decl = impl.ParseDecl(scopeKind)
        impl.FinalizeDeclTree(decl)
        return decl
    }
    public func ParseExpr(): Expr { return impl.ParseExpr() }
    public func ParseExprLibast(): Expr { return impl.ParseExpr(ExprKind.UNKNOWN_EXPR) }
    public func ParseType(): Type { return impl.ParseType() }
    public func ParsePattern(): Pattern { return impl.ParsePattern() }
    public func ParseAnnotationArguments(anno: Annotation): Unit { impl.ParseAnnotationArguments(anno) }
    public func ParseCustomAnnotation(): Annotation { return impl.ParseCustomAnnotation() }

    public func ParseNodes(scope: ScopeKind, currentMacroCall: Node): ArrayList<Node> {
        return impl.ParseNodes(scope, currentMacroCall)
    }

    public func EnableCustomAnno(): Parser {
        impl.EnableCustomAnno()
        return this
    }

    public func GetProcessedTokens(): Int64 { return impl.GetProcessedTokens() }
    public func GetPrimaryDeclIdentRawValue(): String { return impl.GetPrimaryDeclIdentRawValue() }

    public func SetEHEnabled(enabled: Bool): Parser {
        impl.enableEH = enabled
        impl.lexer.SetEHEnabled(enabled)
        return this
    }

    public func IsEHEnabled(): Bool { return impl.enableEH }

    public func SetModuleName(name: String): Parser {
        impl.SetModuleName(name)
        return this
    }

    public func SetPrimaryDecl(decl: String): Parser {
        impl.SetPrimaryDecl(decl)
        return this
    }

    public func SetForImport(isForImport: Bool): Parser {
        impl.SetForImport(isForImport)
        return this
    }

    public func SetCurFile(file: File): Parser {
        impl.SetCurFile(file)
        return this
    }

    public func SetCompileOptions(opts: GlobalOptions): Unit { impl.SetCompileOptions(opts) }
    public func GetDiagnosticEngine(): DiagnosticEngine { return impl.GetDiagnosticEngine() }
    public func GetLexerDiagnosticEngine(): BasicDiagnosticEngine { return impl.GetLexerDiagnosticEngine() }
    public func GetCommentsMap(): TokenVecMap { return impl.commentsMap }

    public func Skip(kind: TokenKind): Bool { return impl.Skip(kind) }
    public func Peek(): Token { return impl.Peek() }
    public func Next(): Unit { impl.Next() }
    public func Seeing(kind: TokenKind): Bool { return impl.Seeing(kind) }
    public func Seeing(left: TokenKind, right: TokenKind): Bool { return impl.Seeing(left, right) }
    public func SeeingAny(kinds: Array<TokenKind>): Bool { return impl.SeeingAny(kinds) }
    public func Seeing(kinds: Array<TokenKind>, skipNewline!: Bool = true): Bool { return impl.Seeing(kinds, skipNewline: skipNewline) }
    public func SeeingCombinator(kinds: Array<TokenKind>): Bool { return impl.SeeingCombinator(kinds) }
    public func SeeingTokenAndCombinator(kind: TokenKind, cmb: Array<TokenKind>): Bool {
        return impl.SeeingTokenAndCombinator(kind, cmb)
    }
    public func SkipCombinator(kinds: Array<TokenKind>): Bool { return impl.SkipCombinator(kinds) }
    public func LookAhead(): Token { return impl.LookAhead() }
    public func LastToken(): Token { return impl.LastToken() }
    public func CurMacroCall(): Option<Node> { return impl.CurMacroCall() }

    public func AttachCommentToNodes(nodes: ArrayList<Node>): Unit {
        impl.AttachCommentToNodes(nodes)
    }
}
