package cjcj::parse

import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DiagnosticBuilder as BasicDiagnosticBuilder
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.Range as BasicRange
import std.collection.*

public class ParserImpl {
    public let diag: BasicDiagnosticEngine
    public let sourceManager: SourceManager
    public let lexer: Lexer
    // C++ anchor: cangjie_compiler/src/Parse/ParserImpl.h:150
    var inputString: String = ""
    private let tokenLines: HashSet<Int64> = HashSet<Int64>()
    public var lookahead: Token = Token(TokenKind.SENTINEL, "", INVALID_POSITION, INVALID_POSITION)
    public var lastToken: Token = Token(TokenKind.SENTINEL, "", INVALID_POSITION, INVALID_POSITION)
    public var lastNoneNLToken: Token = Token(TokenKind.SENTINEL, "", INVALID_POSITION, INVALID_POSITION)
    public var newlineSkipped: Bool = true
    public var skipNL: Bool = true
    public var firstNLPosition: Position = DEFAULT_POSITION
    // C++ anchor: cangjie_compiler/src/Parse/ParserImpl.h:140-144
    public var enableThis: Bool = false
    public var deadlocked: Bool = false
    public var enableCustomAnno: Bool = false
    public var forImport: Bool = false
    public var inForeignBlock: Bool = false
    public var moduleName: String = ""
    public var currentFile: Option<File> = None
    public var curMacroCall: Option<Node> = None
    public var lastPrimaryDeclIdent: String = ""
    public var lastPrimaryDeclIdentIsRaw: Bool = false
    public var curPrimaryDeclIdent: String = ""
    public var curPrimaryDeclIdentIsRaw: Bool = false
    public var enableEH: Bool = false
    public var enableInteropCJMapping: Bool = false
    public var parseDeclFile: Bool = false
    public var enableAttachComment: Bool = false
    public var compileOptions: GlobalOptions = GlobalOptions()
    public var scanDepPkg: Bool = false
    public let commentsMap: TokenVecMap = TokenVecMap()
    public let chainedAST: ArrayList<Node> = ArrayList<Node>()
    public let bracketsStack: ArrayList<TokenKind> = ArrayList<TokenKind>()
    let intrinsics: HashSet<Node> = HashSet<Node>()

    public init(fileID: UInt64, input: String, diag: BasicDiagnosticEngine, sm: SourceManager, attachComment: Bool, parsingDeclFiles: Bool) {
        this.diag = diag
        this.sourceManager = sm
        this.diag.SetSourceManager(sm)
        this.lexer = Lexer(fileID, input, diag, sm, cts: attachComment)
        this.enableAttachComment = attachComment
        this.parseDeclFile = parsingDeclFiles
        Init()
    }

    public init(input: String, diag: BasicDiagnosticEngine, sm: SourceManager, pos: Position, attachComment: Bool, parsingDeclFiles: Bool) {
        this.diag = diag
        this.sourceManager = sm
        this.diag.SetSourceManager(sm)
        this.lexer = Lexer(input, diag, sm, pos, cts: attachComment)
        this.enableAttachComment = attachComment
        this.parseDeclFile = parsingDeclFiles
        Init()
    }

    public init(inputTokens: Array<Token>, diag: BasicDiagnosticEngine, sm: SourceManager, attachComment: Bool, parsingDeclFiles: Bool) {
        this.diag = diag
        this.sourceManager = sm
        this.diag.SetSourceManager(sm)
        this.lexer = Lexer(inputTokens, diag, sm, cts: attachComment)
        this.enableAttachComment = attachComment
        this.parseDeclFile = parsingDeclFiles
        Init()
    }

    private func Init(): Unit {
        Next()
    }

    public func GetLineNum(): Int64 {
        return if (tokenLines.isEmpty()) { 1 } else { tokenLines.size }
    }

    public func GetProcessedTokens(): Int64 {
        return lexer.GetCurrentToken()
    }

    public func GetPrimaryDeclIdentRawValue(): String {
        return if (curPrimaryDeclIdentIsRaw) { "`" + curPrimaryDeclIdent + "`" } else { curPrimaryDeclIdent }
    }

    public func EnableCustomAnno(): ParserImpl {
        enableCustomAnno = true
        return this
    }

    public func SetModuleName(name: String): ParserImpl {
        moduleName = name
        return this
    }

    public func SetPrimaryDecl(decl: String, isRawId!: Bool = false): Unit {
        lastPrimaryDeclIdent = curPrimaryDeclIdent
        lastPrimaryDeclIdentIsRaw = curPrimaryDeclIdentIsRaw
        curPrimaryDeclIdent = decl
        curPrimaryDeclIdentIsRaw = isRawId
    }

    public func RevertPrimaryDecl(): Unit {
        curPrimaryDeclIdent = lastPrimaryDeclIdent
        curPrimaryDeclIdentIsRaw = lastPrimaryDeclIdentIsRaw
    }

    public func SetForImport(isForImport: Bool): ParserImpl {
        forImport = isForImport
        return this
    }

    public func SetCurFile(file: File): ParserImpl {
        currentFile = file
        return this
    }

    public func SetCompileOptions(opts: GlobalOptions): Unit {
        compileOptions = opts
        scanDepPkg = opts.scanDepPkg
        enableInteropCJMapping = opts.enableInteropCJMapping
        enableEH = opts.enableEH
        lexer.SetEHEnabled(opts.enableEH)
    }

    public func GetDiagnosticEngine(): BasicDiagnosticEngine {
        return diag
    }

    // Lexer and parser share one basic DiagnosticEngine, matching C++ ParserImpl.
    public func GetLexerDiagnosticEngine(): BasicDiagnosticEngine {
        return diag
    }

    public func Peek(): Token {
        return lookahead
    }

    public func LookAhead(): Token {
        return lookahead
    }

    public func LastToken(): Token {
        return lastToken
    }

    public func CurMacroCall(): Option<Node> {
        return curMacroCall
    }

    public func Next(): Unit {
        if (lookahead.kind != TokenKind.COMMENT && lookahead.kind != TokenKind.END) {
            lastToken = lookahead
            if (lookahead.kind != TokenKind.NL) {
                lastNoneNLToken = lookahead
            }
        }
        deadlocked = false
        var token = lexer.Next()
        RecordTokenLines(token)
        if (token.kind == TokenKind.LCURL || token.kind == TokenKind.LPAREN ||
            token.kind == TokenKind.LSQUARE) {
            bracketsStack.add(token.kind)
        }
        var matchingBracket = LookupMatchingOpenBracket(token.kind)
        if (matchingBracket != TokenKind.ILLEGAL && !bracketsStack.isEmpty() &&
            matchingBracket == bracketsStack[bracketsStack.size - 1]) {
            bracketsStack.remove(at: bracketsStack.size - 1)
        }
        newlineSkipped = false
        var firstNLFlag = true
        if (token.kind == TokenKind.NL) {
            newlineSkipped = true
            firstNLPosition = token.Begin()
            firstNLFlag = false
        }
        while (token.kind == TokenKind.COMMENT || (skipNL && token.kind == TokenKind.NL)) {
            token = lexer.Next()
            RecordTokenLines(token)
            if (token.kind == TokenKind.LCURL || token.kind == TokenKind.LPAREN ||
                token.kind == TokenKind.LSQUARE) {
                bracketsStack.add(token.kind)
            }
            matchingBracket = LookupMatchingOpenBracket(token.kind)
            if (matchingBracket != TokenKind.ILLEGAL && !bracketsStack.isEmpty() &&
                matchingBracket == bracketsStack[bracketsStack.size - 1]) {
                bracketsStack.remove(at: bracketsStack.size - 1)
            }
            if (token.kind == TokenKind.NL) {
                newlineSkipped = true
                if (firstNLFlag) {
                    firstNLPosition = token.Begin()
                    firstNLFlag = false
                }
            }
        }
        if (token.kind == TokenKind.END && !lastToken.Begin().IsZero()) {
            token.SetValuePos(token.Value(), lastToken.End(), lastToken.End())
        }
        lookahead = token
    }

    private func RecordTokenLines(token: Token): Unit {
        if (token.Begin().line <= 0 || token.End().line <= 0) {
            return
        }
        var line = token.Begin().line
        while (line <= token.End().line) {
            tokenLines.add(line)
            line++
        }
    }

    public func Skip(kind: TokenKind): Bool {
        if (Seeing(kind)) {
            Next()
            return true
        }
        return false
    }

    public func Seeing(kind: TokenKind): Bool {
        return Peek().kind == kind
    }

    public func Seeing(left: TokenKind, right: TokenKind): Bool {
        let index = TokenKindIndex(Peek().kind)
        return index >= TokenKindIndex(left) && index <= TokenKindIndex(right)
    }

    public func SeeingAny(kinds: Array<TokenKind>): Bool {
        for (kind in kinds) {
            if (Seeing(kind)) {
                return true
            }
        }
        return false
    }

    public func Seeing(kinds: Array<TokenKind>, skipNewline!: Bool = true): Bool {
        if (kinds.isEmpty()) {
            return false
        }
        if (lookahead.kind != kinds[0]) {
            return false
        }
        if (kinds.size == 1) {
            return true
        }
        let ahead = if (skipNewline) { lexer.LookAheadSkipNL(kinds.size - 1) } else { lexer.LookAhead(kinds.size - 1) }
        var idx: Int64 = 1
        while (idx < kinds.size) {
            if ((idx - 1) >= ahead.size || ahead[idx - 1].kind != kinds[idx]) {
                return false
            }
            idx++
        }
        return true
    }

    public func SkipBlank(blank0: TokenKind, blank1!: TokenKind = TokenKind.SENTINEL): Unit {
        while (Seeing(blank0) || (blank1 != TokenKind.SENTINEL && Seeing(blank1))) {
            Next()
        }
    }

    // C++: src/Parse/ParserImpl.h:484-491 ParserImpl::MakeInvalid.
    public static func MakeInvalid<T>(node: T, pos: Position): T where T <: Node {
        node.EnableAttr(Attribute.IS_BROKEN)
        node.begin = pos
        node.end = pos
        return node
    }

    public func SkipNLOrSemi(): Bool {
        var found = newlineSkipped
        let oldSkip = skipNL
        skipNL = false
        while (Seeing(TokenKind.NL) || Seeing(TokenKind.SEMI)) {
            found = true
            Next()
        }
        skipNL = oldSkip
        return found
    }

    public func SkipSemi(): Unit {
        SkipBlank(TokenKind.SEMI)
    }

    public func Expect(kind: TokenKind, _: String): Token {
        let token = Peek()
        if (!Skip(kind)) {
            let expectStr = "'" + TokenKindLiteral(kind) + "'"
            let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_character, lookahead, expectStr,
                ConvertToken(lookahead))
            builder.AddMainHintArguments(expectStr)
            builder.Emit()
        }
        return token
    }

    public func ParseDiagnoseRefactor(
        kind: BasicDiagKindRefactor,
        node: Node,
        pos: Position,
        arguments!: Array<String> = Array<String>()
    ): BasicDiagnosticBuilder {
        if (let Some(macroCall) <- node.curMacroCall) {
            if (let Some(invocation) <- macroCall.GetConstInvocation()) {
                return diag.DiagnoseRefactor(kind, invocation.macroCallDiagInfo, pos, formatArgs: arguments)
            }
        }
        return diag.DiagnoseRefactor(kind, pos, arguments: arguments)
    }

    public func ParseDiagnoseRefactor(
        kind: BasicDiagKindRefactor,
        node: Node,
        range: BasicRange,
        arguments!: Array<String> = Array<String>()
    ): BasicDiagnosticBuilder {
        if (let Some(macroCall) <- node.curMacroCall) {
            if (let Some(invocation) <- macroCall.GetConstInvocation()) {
                return diag.DiagnoseRefactor(kind, invocation.macroCallDiagInfo, range, formatArgs: arguments)
            }
        }
        return diag.DiagnoseRefactor(kind, range, arguments: arguments)
    }

    public func ParseDiagnoseRefactor(
        kind: BasicDiagKindRefactor,
        pos: Position,
        arguments!: Array<String> = Array<String>()
    ): BasicDiagnosticBuilder {
        let node = Node()
        node.begin = pos
        node.end = pos + 1
        if (let Some(macroCall) <- curMacroCall) {
            node.curMacroCall = macroCall
        }
        return ParseDiagnoseRefactor(kind, node, pos, arguments: arguments)
    }

    public func ParseDiagnoseRefactor(kind: BasicDiagKindRefactor, pos: Position, argument: String): BasicDiagnosticBuilder {
        return ParseDiagnoseRefactor(kind, pos, arguments: [argument])
    }

    public func ParseDiagnoseRefactor(
        kind: BasicDiagKindRefactor,
        pos: Position,
        arg0: String,
        arg1: String
    ): BasicDiagnosticBuilder {
        return ParseDiagnoseRefactor(kind, pos, arguments: [arg0, arg1])
    }

    public func ParseDiagnoseRefactor(
        kind: BasicDiagKindRefactor,
        pos: Position,
        arg0: String,
        arg1: String,
        arg2: String
    ): BasicDiagnosticBuilder {
        return ParseDiagnoseRefactor(kind, pos, arguments: [arg0, arg1, arg2])
    }

    public func ParseDiagnoseRefactor(
        kind: BasicDiagKindRefactor,
        range: BasicRange,
        arguments!: Array<String> = Array<String>()
    ): BasicDiagnosticBuilder {
        let node = Node()
        node.begin = range.begin
        node.end = range.end
        if (let Some(macroCall) <- curMacroCall) {
            node.curMacroCall = macroCall
        }
        return ParseDiagnoseRefactor(kind, node, range, arguments: arguments)
    }

    public func ParseDiagnoseRefactor(kind: BasicDiagKindRefactor, range: BasicRange, argument: String): BasicDiagnosticBuilder {
        return ParseDiagnoseRefactor(kind, range, arguments: [argument])
    }

    public func ParseDiagnoseRefactor(
        kind: BasicDiagKindRefactor,
        range: BasicRange,
        arg0: String,
        arg1: String
    ): BasicDiagnosticBuilder {
        return ParseDiagnoseRefactor(kind, range, arguments: [arg0, arg1])
    }

    public func ParseDiagnoseRefactor(
        kind: BasicDiagKindRefactor,
        range: BasicRange,
        arg0: String,
        arg1: String,
        arg2: String
    ): BasicDiagnosticBuilder {
        return ParseDiagnoseRefactor(kind, range, arguments: [arg0, arg1, arg2])
    }

    public func ParseDiagnoseRefactor(
        kind: BasicDiagKindRefactor,
        token: Token,
        arguments!: Array<String> = Array<String>()
    ): BasicDiagnosticBuilder {
        let node = Node()
        node.begin = token.Begin()
        node.end = token.End()
        if (let Some(macroCall) <- curMacroCall) {
            node.curMacroCall = macroCall
        }
        return ParseDiagnoseRefactor(kind, node, MakeRange(token.Begin(), token.End()), arguments: arguments)
    }

    public func ParseDiagnoseRefactor(kind: BasicDiagKindRefactor, token: Token, argument: String): BasicDiagnosticBuilder {
        return ParseDiagnoseRefactor(kind, token, arguments: [argument])
    }

    public func ParseDiagnoseRefactor(
        kind: BasicDiagKindRefactor,
        token: Token,
        arg0: String,
        arg1: String
    ): BasicDiagnosticBuilder {
        return ParseDiagnoseRefactor(kind, token, arguments: [arg0, arg1])
    }

    public func ParseDiagnoseRefactor(
        kind: BasicDiagKindRefactor,
        token: Token,
        arg0: String,
        arg1: String,
        arg2: String
    ): BasicDiagnosticBuilder {
        return ParseDiagnoseRefactor(kind, token, arguments: [arg0, arg1, arg2])
    }

    public func ParseDiagnoseRefactor(
        kind: BasicDiagKindRefactor,
        node: Node,
        arguments!: Array<String> = Array<String>()
    ): BasicDiagnosticBuilder {
        return ParseDiagnoseRefactor(kind, node, MakeRange(node.GetBegin(), node.GetEnd()), arguments: arguments)
    }

    public func ParseDiagnoseRefactor(kind: BasicDiagKindRefactor, node: Node, argument: String): BasicDiagnosticBuilder {
        return ParseDiagnoseRefactor(kind, node, arguments: [argument])
    }

    public func ParseDiagnoseRefactor(
        kind: BasicDiagKindRefactor,
        node: Node,
        arg0: String,
        arg1: String
    ): BasicDiagnosticBuilder {
        return ParseDiagnoseRefactor(kind, node, arguments: [arg0, arg1])
    }

    public func ParseDiagnoseRefactor(
        kind: BasicDiagKindRefactor,
        node: Node,
        arg0: String,
        arg1: String,
        arg2: String
    ): BasicDiagnosticBuilder {
        return ParseDiagnoseRefactor(kind, node, arguments: [arg0, arg1, arg2])
    }
}

public class ChainScope <: Resource {
    private let parser: ParserImpl
    private var closed: Bool = false

    public init(parser: ParserImpl, node: Node) {
        this.parser = parser
        parser.chainedAST.add(node)
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        parser.chainedAST.remove(at: parser.chainedAST.size - 1)
        closed = true
    }

    public func isClosed(): Bool {
        return closed
    }
}

public class ParserScope {
    private let ref: ParserImpl
    private let oldLookAhead: Token
    private let oldSkipToken: Token
    private let oldLastToken: Token
    private let oldLastNoneNLToken: Token
    private let oldNewlineSkipped: Bool

    public init(parser: ParserImpl) {
        ref = parser
        oldLookAhead = parser.lookahead
        oldSkipToken = parser.lastToken
        oldLastToken = parser.lastToken
        oldLastNoneNLToken = parser.lastNoneNLToken
        oldNewlineSkipped = parser.newlineSkipped
        parser.lexer.SetResetPoint()
    }

    public func ResetParserScope(): Unit {
        ref.lookahead = oldLookAhead
        ref.lastToken = oldSkipToken
        ref.lexer.Reset()
        ref.lastToken = oldLastToken
        ref.lastNoneNLToken = oldLastNoneNLToken
        ref.newlineSkipped = oldNewlineSkipped
    }
}

public func IsBuiltinAnnotation(moduleName: String, identifier: String): Bool {
    if (identifier == "ConstSafe") {
        return moduleName == "std"
    }
    return NameToAnnotationKind(identifier) != AnnotationKind.CUSTOM
}

public func AnnotationKindToString(kind: AnnotationKind): String {
    return match (kind) {
        case AnnotationKind.JAVA_MIRROR => "JavaMirror"
        case AnnotationKind.JAVA_IMPL => "JavaImpl"
        case AnnotationKind.JAVA_HAS_DEFAULT => "JavaHasDefault"
        case AnnotationKind.OBJ_C_MIRROR => "ObjCMirror"
        case AnnotationKind.OBJ_C_IMPL => "ObjCImpl"
        case AnnotationKind.FOREIGN_GETTER_NAME => "ForeignGetterName"
        case AnnotationKind.FOREIGN_SETTER_NAME => "ForeignSetterName"
        case AnnotationKind.OBJ_C_INIT => "ObjCInit"
        case AnnotationKind.OBJ_C_OPTIONAL => "ObjCOptional"
        case AnnotationKind.FOREIGN_NAME => "ForeignName"
        case AnnotationKind.CALLING_CONV => "CallingConv"
        case AnnotationKind.C => "C"
        case AnnotationKind.ATTRIBUTE => "Attribute"
        case AnnotationKind.INTRINSIC => "Intrinsic"
        case AnnotationKind.NUMERIC_OVERFLOW => "Overflow"
        case AnnotationKind.WHEN => "When"
        case AnnotationKind.FASTNATIVE => "FastNative"
        case AnnotationKind.ANNOTATION => "Annotation"
        case AnnotationKind.CONSTSAFE => "ConstSafe"
        case AnnotationKind.DEPRECATED => "Deprecated"
        case AnnotationKind.FROZEN => "Frozen"
        case AnnotationKind.ENSURE_PREPARED_TO_MOCK => "EnsurePreparedToMock"
        case AnnotationKind.NON_PRODUCT => "NonProduct"
        case AnnotationKind.CUSTOM => "Custom"
        case AnnotationKind.JAVA => "Java"
        case AnnotationKind.UNKNOWN => "Unknown"
        case AnnotationKind.NO_HEAP_ALLOC => "NoHeapAlloc"
        case AnnotationKind.NO_WRITE_BARRIER => "NoWriteBarrier"
        case AnnotationKind.NO_WRITE_BARRIER_REC => "NoWriteBarrierRec"
        case AnnotationKind.NO_STACK_GROW => "NoStackGrow"
        case AnnotationKind.SYSTEM_STACK => "SystemStack"
    }
}

public func NameToAnnotationKind(name: String): AnnotationKind {
    if (name == "JavaMirror") { return AnnotationKind.JAVA_MIRROR }
    if (name == "JavaImpl") { return AnnotationKind.JAVA_IMPL }
    if (name == "JavaHasDefault") { return AnnotationKind.JAVA_HAS_DEFAULT }
    if (name == "ObjCMirror") { return AnnotationKind.OBJ_C_MIRROR }
    if (name == "ObjCImpl") { return AnnotationKind.OBJ_C_IMPL }
    if (name == "ForeignGetterName") { return AnnotationKind.FOREIGN_GETTER_NAME }
    if (name == "ForeignSetterName") { return AnnotationKind.FOREIGN_SETTER_NAME }
    if (name == "ObjCInit") { return AnnotationKind.OBJ_C_INIT }
    if (name == "ObjCOptional") { return AnnotationKind.OBJ_C_OPTIONAL }
    if (name == "ForeignName") { return AnnotationKind.FOREIGN_NAME }
    if (name == "CallingConv") { return AnnotationKind.CALLING_CONV }
    if (name == "C") { return AnnotationKind.C }
    if (name == "Attribute") { return AnnotationKind.ATTRIBUTE }
    if (name == "Intrinsic") { return AnnotationKind.INTRINSIC }
    if (name == "OverflowThrowing" || name == "OverflowWrapping" || name == "OverflowSaturating") {
        return AnnotationKind.NUMERIC_OVERFLOW
    }
    if (name == "When") { return AnnotationKind.WHEN }
    if (name == "FastNative") { return AnnotationKind.FASTNATIVE }
    if (name == "Annotation") { return AnnotationKind.ANNOTATION }
    if (name == "ConstSafe") { return AnnotationKind.CONSTSAFE }
    if (name == "Deprecated") { return AnnotationKind.DEPRECATED }
    if (name == "Frozen") { return AnnotationKind.FROZEN }
    if (name == "EnsurePreparedToMock") { return AnnotationKind.ENSURE_PREPARED_TO_MOCK }
    if (name == "NonProduct") { return AnnotationKind.NON_PRODUCT }
    if (name == "NoHeapAlloc") { return AnnotationKind.NO_HEAP_ALLOC }
    if (name == "NoWriteBarrier") { return AnnotationKind.NO_WRITE_BARRIER }
    if (name == "NoWriteBarrierRec") { return AnnotationKind.NO_WRITE_BARRIER_REC }
    if (name == "NoStackGrow") { return AnnotationKind.NO_STACK_GROW }
    if (name == "SystemStack") { return AnnotationKind.SYSTEM_STACK }
    return AnnotationKind.CUSTOM
}
