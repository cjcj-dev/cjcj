package cangjie_compiler::lex

import cangjie_compiler::basic.*
import cangjie_compiler::utils.IsAlnum as UtilsIsAlnum
import cangjie_compiler::utils.IsASCIIIdContinue as UtilsIsASCIIIdContinue
import cangjie_compiler::utils.IsASCIIIdStart as UtilsIsASCIIIdStart
import cangjie_compiler::utils.IsCJXIDStart as UtilsIsCJXIDStart
import cangjie_compiler::utils.IsDigit as UtilsIsDigit
import cangjie_compiler::utils.IsXDigit as UtilsIsXDigit
import cangjie_compiler::utils.IsXIDContinue as UtilsIsXIDContinue
import cangjie_compiler::utils.NFC as UtilsNFC
import cangjie_compiler::utils.CJC_ASSERT
import std.collection.*

public let BYTE_X_FLAG: UInt8 = 0x80u8
public let BYTE_2_FLAG: UInt8 = 0xc0u8
public let BYTE_3_FLAG: UInt8 = 0xe0u8
public let BYTE_4_FLAG: UInt8 = 0xf0u8
public let BYTE_5_FLAG: UInt8 = 0xf8u8
public let BYTE_6_FLAG: UInt8 = 0xfcu8
public let LOW_6_BIT_MASK: UInt32 = 0x3fu32
public let LOW_5_BIT_MASK: UInt32 = 0x1fu32
public let LOW_4_BIT_MASK: UInt32 = 0x0fu32
public let LOW_3_BIT_MASK: UInt32 = 0x07u32
public let LOW_2_BIT_MASK: UInt32 = 0x03u32
public let LOW_1_BIT_MASK: UInt32 = 0x01u32
public let UTF8_1_MAX: UInt32 = 0x7fu32
public let UTF8_2_MAX: UInt32 = 0x07ffu32
public let UTF8_3_MAX: UInt32 = 0xffffu32
public let UTF8_4_MAX: UInt32 = 0x10ffffu32
public let UTF8_5_MAX: UInt32 = 0x3ffffffu32
public let UTF8_6_MAX: UInt32 = 0x7fffffffu32
public let LEFT_SHIFT_30: UInt8 = 30u8
public let LEFT_SHIFT_24: UInt8 = 24u8
public let LEFT_SHIFT_18: UInt8 = 18u8
public let LEFT_SHIFT_12: UInt8 = 12u8
public let LEFT_SHIFT_6: UInt8 = 6u8
private let BYTE_4_BASE: UInt32 = 65536u32
private let BYTE_3_BASE: UInt32 = 2048u32
private let BYTE_2_BASE: UInt32 = 128u32
public let BYTE_1_STEP: UInt8 = 1u8
public let BYTE_2_STEP: UInt8 = 2u8
public let BYTE_3_STEP: UInt8 = 3u8
public let BYTE_4_STEP: UInt8 = 4u8
public let BYTE_5_STEP: UInt8 = 5u8
public let BYTE_6_STEP: UInt8 = 6u8
public let ERROR_UTF8: Int64 = -2
public let BYTE_3_INDEX: UInt8 = 2u8
public let BYTE_4_INDEX: UInt8 = 3u8
public let BYTE_5_INDEX: UInt8 = 4u8
public let BYTE_6_INDEX: UInt8 = 5u8
public let UNICODE_MAX_NUM: Int64 = 8
public let BIN_BASE: Int64 = 2
public let OCT_BASE: Int64 = 8
public let DEC_BASE: Int64 = 10
public let HEX_BASE: Int64 = 16

private enum LexerContext {
    | NORMAL
    | QUOTE
}

private func LexerContextIndex(ctx: LexerContext): Int64 {
    return match (ctx) {
        case LexerContext.NORMAL => 0
        case LexerContext.QUOTE => 1
    }
}

extend LexerContext <: Equatable<LexerContext> {
    public operator func ==(right: LexerContext): Bool {
        return LexerContextIndex(this) == LexerContextIndex(right)
    }

    public operator func !=(right: LexerContext): Bool {
        return !(this == right)
    }
}

public struct LexerConfig {
    public var fileID: UInt64 = 0u64
    public var posBase: Position = BEGIN_POSITION
    public var collectTokenStream: Bool = false
    public var splitAmbiguousToken: Bool = true

    public init() {}

    public init(
        fileID!: UInt64 = 0u64,
        posBase!: Position = BEGIN_POSITION,
        collectTokenStream!: Bool = false,
        splitAmbiguousToken!: Bool = true
    ) {
        this.fileID = fileID
        this.posBase = posBase
        this.collectTokenStream = collectTokenStream
        this.splitAmbiguousToken = splitAmbiguousToken
    }
}

private func copyTokenList(source: ArrayList<Token>): ArrayList<Token> {
    let ret = ArrayList<Token>()
    for (token in source) {
        ret.add(token)
    }
    return ret
}

private func copyOffsets(source: ArrayList<Int64>): ArrayList<Int64> {
    let ret = ArrayList<Int64>()
    for (offset in source) {
        ret.add(offset)
    }
    return ret
}

private func byteString(value: UInt8): String {
    return String.fromUtf8([value])
}

private func isDigit(value: Int64): Bool {
    return UtilsIsDigit(value)
}

private func isHexDigit(value: Int64): Bool {
    return UtilsIsXDigit(value)
}

private func isAlnum(value: Int64): Bool {
    return UtilsIsAlnum(value)
}

private func lowerByte(value: UInt8): UInt8 {
    if (value >= b'A' && value <= b'Z') {
        return value + 32u8
    }
    return value
}

private func isAsciiIdentifierStart(value: Int64): Bool {
    if (value < 0 || value > 127) {
        return false
    }
    return UtilsIsASCIIIdStart(UInt32(value))
}

private func isAsciiIdentifierContinue(value: Int64): Bool {
    if (value < 0 || value > 127) {
        return false
    }
    return UtilsIsASCIIIdContinue(UInt32(value))
}

private func isCJXIDStart(value: Int64): Bool {
    if (value < 0 || value > 0x10ffff) {
        return false
    }
    return UtilsIsCJXIDStart(UInt32(value))
}

private func isXIDContinue(value: Int64): Bool {
    if (value < 0 || value > 0x10ffff) {
        return false
    }
    return UtilsIsXIDContinue(UInt32(value))
}

private func NormalizeIdentifierNFC(value: String): String {
    return UtilsNFC(value)
}

private func isLegalEscape(value: Int64): Bool {
    return value == Int64(b't') || value == Int64(b'b') || value == Int64(b'r') || value == Int64(b'n') ||
        value == Int64(b'f') || value == Int64(b'v') || value == Int64(b'0') || value == Int64(b'\'') ||
        value == Int64(b'"') || value == Int64(b'\\')
}

private func isMacroEscape(value: UInt8): Bool {
    return value == b'$' || value == b'@' || value == b'(' || value == b')' || value == b'[' || value == b']'
}

private func isQuote(value: Int64): Bool {
    return value == Int64(b'\'') || value == Int64(b'"')
}

public class LexerImpl {
    private let diag: DiagnosticEngine
    private let source: Source
    private let input: String
    private let bytes: Array<Byte>
    private let fileID: UInt64
    private var pNext: Int64 = 0
    private var pCurrent: Int64 = 0
    private var pResetNext: Int64 = 0
    private var pResetCurrent: Int64 = 0
    private var currentChar: Int64 = -1
    private var ehEnabled: Bool = false
    private var lineResetOffsetsFromBase: Int64 = 0
    private var tokenKind: TokenKind = TokenKind.ILLEGAL
    private var pos: Position = BEGIN_POSITION
    private let posBase: Position
    private let splitAmbiguousToken: Bool
    private let lineOffsetsFromBase: ArrayList<Int64> = ArrayList<Int64>()
    private var resetLineOffsetsFromBase: ArrayList<Int64> = ArrayList<Int64>()
    private let lookAheadCache: ArrayList<Token> = ArrayList<Token>()
    private var resetLookAheadCache: ArrayList<Token> = ArrayList<Token>()
    private var enableScan: Bool = true
    private let tokens: ArrayList<Token> = ArrayList<Token>()
    private var curToken: Int64 = 0
    private var resetToken: Int64 = 0
    private var enableCollect: Bool = false
    private var enableCollectTokenStream: Bool = false
    private let collectTokensFindCache: HashSet<Position> = HashSet<Position>()
    private let collectTokens: ArrayList<Token> = ArrayList<Token>()
    private let tokenStream: TreeSet<Token> = TreeSet<Token>()
    private let stringPartsMap: HashMap<Token, ArrayList<StringPart>> = HashMap<Token, ArrayList<StringPart>>()
    private let comments: ArrayList<Token> = ArrayList<Token>()
    private var success: Bool = true
    private let stringStarts: ArrayList<(Int64, Bool)> = ArrayList<(Int64, Bool)>()
    private let interpolations: ArrayList<Int64> = ArrayList<Int64>()
    private let ctx: ArrayList<LexerContext> = ArrayList<LexerContext>()

    public init(input: String, diag: DiagnosticEngine, sm: SourceManager, args: LexerConfig) {
        this.diag = diag
        this.source = sm.GetSource(args.fileID)
        this.input = input
        this.bytes = input.toArray()
        this.fileID = args.fileID
        this.posBase = args.posBase
        this.splitAmbiguousToken = args.splitAmbiguousToken
        this.enableCollectTokenStream = args.collectTokenStream
        lineOffsetsFromBase.add(0)
        EnterNormalMod()
    }

    public init(input: String, diag: DiagnosticEngine, source: Source, args: LexerConfig) {
        this.diag = diag
        this.source = source
        this.input = input
        this.bytes = input.toArray()
        this.fileID = args.fileID
        this.posBase = args.posBase
        this.splitAmbiguousToken = args.splitAmbiguousToken
        this.enableCollectTokenStream = args.collectTokenStream
        lineOffsetsFromBase.add(0)
        EnterNormalMod()
    }

    public init(inputTokens: Array<Token>, diag: DiagnosticEngine, sm: SourceManager, args: LexerConfig) {
        this.diag = diag
        this.source = sm.GetSource(args.fileID)
        this.input = ""
        this.bytes = Array<Byte>()
        this.fileID = args.fileID
        this.posBase = args.posBase
        this.splitAmbiguousToken = args.splitAmbiguousToken
        this.enableCollectTokenStream = args.collectTokenStream
        this.enableScan = false
        lineOffsetsFromBase.add(0)
        EnterNormalMod()
        for (token in inputTokens) {
            if (token.kind == TokenKind.IDENTIFIER && LookupKeyword(token.Value()) != TokenKind.IDENTIFIER) {
                let tempLexer = LexerImpl(token.Value(), diag, sm, LexerConfig(posBase: token.Begin()))
                let expanded = tempLexer.GetTokens()
                for (expandedToken in expanded) {
                    tokens.add(expandedToken)
                }
            } else {
                tokens.add(token)
            }
        }
        if (!tokens.isEmpty()) {
            let lastToken = tokens[tokens.size - 1]
            pos = Position(lastToken.Begin().fileID, lastToken.Begin().line, lastToken.Begin().column + 1)
        } else {
            pos = Position(0u64, 0, 0)
        }
    }

    public func Next(): Token {
        var token = Token(TokenKind.SENTINEL, "", BEGIN_POSITION, BEGIN_POSITION)
        if (lookAheadCache.isEmpty()) {
            token = Scan()
        } else {
            token = lookAheadCache[0]
            lookAheadCache.remove(at: 0)
        }
        CollectToken(token)
        return token
    }

    public func LookAhead(num: Int64): ArrayList<Token> {
        if (num <= lookAheadCache.size) {
            return lookAheadCache
        }
        while (lookAheadCache.size < num) {
            let token = Scan()
            if (token.kind != TokenKind.COMMENT) {
                lookAheadCache.add(token)
            }
            if (token.kind == TokenKind.END) {
                break
            }
        }
        return lookAheadCache
    }

    public func Seeing(kinds: Array<TokenKind>, skipNewline!: Bool = false, skipComments!: Bool = true): Bool {
        ReserveToken(kinds.size + 1, skipNewline, skipComments)
        var kindIndex: Int64 = 0
        var cacheIndex: Int64 = 0
        while (kindIndex < kinds.size && cacheIndex < lookAheadCache.size) {
            let token = lookAheadCache[cacheIndex]
            cacheIndex++
            if (skipNewline && token.kind == TokenKind.NL) {
                continue
            }
            if (kinds[kindIndex] != token.kind) {
                return false
            }
            kindIndex++
        }
        return kindIndex == kinds.size
    }

    public func LookAheadSkipNL(num: Int64): ArrayList<Token> {
        let ret = ArrayList<Token>()
        for (token in lookAheadCache) {
            if (token.kind != TokenKind.NL) {
                ret.add(token)
            }
            if (ret.size >= num) {
                return ret
            }
        }
        while (ret.size < num) {
            let token = Scan()
            if (token.kind == TokenKind.COMMENT) {
                continue
            }
            lookAheadCache.add(token)
            if (token.kind != TokenKind.NL) {
                ret.add(token)
            }
            if (token.kind == TokenKind.END) {
                break
            }
        }
        return ret
    }

    public func GetComments(): ArrayList<Token> {
        let ret = copyTokenList(comments)
        comments.clear()
        return ret
    }

    public func GetTokenStream(): TreeSet<Token> {
        return tokenStream
    }

    public func EnterQuoteMod(): Unit {
        ctx.add(LexerContext.QUOTE)
    }

    public func ExitQuoteMod(): Unit {
        CJC_ASSERT(!ctx.isEmpty() && ctx[ctx.size - 1] == LexerContext.QUOTE)
        ctx.remove(at: ctx.size - 1)
    }

    public func EnterNormalMod(): Unit {
        ctx.add(LexerContext.NORMAL)
    }

    public func ExitNormalMod(): Unit {
        CJC_ASSERT(!ctx.isEmpty() && ctx[ctx.size - 1] == LexerContext.NORMAL)
        ctx.remove(at: ctx.size - 1)
    }

    public func SetResetPoint(): Unit {
        pResetCurrent = pCurrent
        pResetNext = pNext
        resetLookAheadCache = copyTokenList(lookAheadCache)
        resetLineOffsetsFromBase = copyOffsets(lineOffsetsFromBase)
        lineResetOffsetsFromBase = lineOffsetsFromBase.size
        resetToken = curToken
    }

    public func Reset(): Unit {
        pCurrent = pResetCurrent
        pNext = pResetNext
        lookAheadCache.clear()
        for (token in resetLookAheadCache) {
            lookAheadCache.add(token)
        }
        lineOffsetsFromBase.clear()
        for (offset in resetLineOffsetsFromBase) {
            lineOffsetsFromBase.add(offset)
        }
        curToken = resetToken
    }

    public func GetPosBase(): Position {
        return posBase
    }

    public func GetFileID(): UInt64 {
        return fileID
    }

    public func ClearStringParts(t: Token): Unit {
        if (stringPartsMap.contains(t)) {
            stringPartsMap.remove(t)
        }
    }

    public func SetEHEnabled(enabled: Bool): Unit {
        ehEnabled = enabled
    }

    public func GetStrParts(t: Token): ArrayList<StringPart> {
        CJC_ASSERT(t.kind == TokenKind.STRING_LITERAL || t.kind == TokenKind.MULTILINE_STRING)
        if (let Some(parts) <- stringPartsMap.get(t)) {
            return parts
        }
        if (!enableScan) {
            let syntheticInput = if (t.kind == TokenKind.MULTILINE_STRING) {
                "\"\"\"\n" + ProcessQuotaMarks(t.Value()) + "\"\"\""
            } else {
                "\"" + ProcessQuotaMarks(t.Value(), processSingle: true) + "\""
            }
            let tempLexer = LexerImpl(syntheticInput, diag, source, LexerConfig(posBase: t.Begin()))
            tempLexer.Scan()
            stringPartsMap.add(t, tempLexer.TakeFirstStringParts())
        }
        if (let Some(parts) <- stringPartsMap.get(t)) {
            return parts
        }
        CJC_ASSERT(false)
        return ArrayList<StringPart>()
    }

    private func TakeFirstStringParts(): ArrayList<StringPart> {
        let ret = ArrayList<StringPart>()
        for ((_, parts) in stringPartsMap) {
            for (part in parts) {
                ret.add(part)
            }
            return ret
        }
        return ret
    }

    public func GetTokens(): Array<Token> {
        let ret = ArrayList<Token>()
        var token = Next()
        while (token.kind != TokenKind.END) {
            ret.add(token)
            token = Next()
        }
        return ret.toArray()
    }

    public func GetCollectTokens(): Array<Token> {
        return collectTokens.toArray()
    }

    public func StartCollectTokens(): Bool {
        if (enableCollect) {
            return false
        }
        enableCollect = true
        collectTokens.clear()
        collectTokensFindCache.clear()
        return true
    }

    public func StopCollectTokens(bStart: Bool): Unit {
        if (bStart) {
            enableCollect = false
        }
    }

    public func GetCurrentToken(): Int64 {
        var tokenNumber = curToken
        for (token in lookAheadCache) {
            if (token.kind != TokenKind.SENTINEL && token.kind != TokenKind.ILLEGAL && token.kind != TokenKind.END) {
                tokenNumber--
            }
        }
        return tokenNumber
    }

    private func IsQuoteContext(): Bool {
        CJC_ASSERT(!ctx.isEmpty())
        return ctx[ctx.size - 1] == LexerContext.QUOTE
    }

    private func ReserveToken(num: Int64, skipNewline: Bool, skipComments: Bool): Unit {
        var index: Int64 = 0
        if (skipNewline) {
            var cacheIndex: Int64 = 0
            while (cacheIndex < lookAheadCache.size && index < num) {
                if (lookAheadCache[cacheIndex].kind != TokenKind.NL) {
                    index++
                }
                cacheIndex++
            }
        } else {
            index = lookAheadCache.size
        }
        while (index < num) {
            let token = Scan()
            if (token.kind == TokenKind.COMMENT && skipComments) {
                continue
            }
            lookAheadCache.add(token)
            if (!skipNewline || token.kind != TokenKind.NL) {
                index++
            }
        }
    }

    private func CollectToken(token: Token): Unit {
        if (!enableCollect) {
            return
        }
        if (!collectTokensFindCache.contains(token.Begin())) {
            collectTokens.add(token)
            collectTokensFindCache.add(token.Begin())
        }
    }

    private func LookupKeyword(literal: String): TokenKind {
        let mapped = match (literal) {
            case "." => TokenKind.DOT
            case "," => TokenKind.COMMA
            case "(" => TokenKind.LPAREN
            case ")" => TokenKind.RPAREN
            case "[" => TokenKind.LSQUARE
            case "]" => TokenKind.RSQUARE
            case "{" => TokenKind.LCURL
            case "}" => TokenKind.RCURL
            case "**" => TokenKind.EXP
            case "*" => TokenKind.MUL
            case "%" => TokenKind.MOD
            case "/" => TokenKind.DIV
            case "+" => TokenKind.ADD
            case "-" => TokenKind.SUB
            case "++" => TokenKind.INCR
            case "--" => TokenKind.DECR
            case "&&" => TokenKind.AND
            case "||" => TokenKind.OR
            case "??" => TokenKind.COALESCING
            case "|>" => TokenKind.PIPELINE
            case "~>" => TokenKind.COMPOSITION
            case "!" => TokenKind.NOT
            case "&" => TokenKind.BITAND
            case "|" => TokenKind.BITOR
            case "^" => TokenKind.BITXOR
            case "~" => TokenKind.BITNOT
            case "<<" => TokenKind.LSHIFT
            case ">>" => TokenKind.RSHIFT
            case ":" => TokenKind.COLON
            case ";" => TokenKind.SEMI
            case "=" => TokenKind.ASSIGN
            case "+=" => TokenKind.ADD_ASSIGN
            case "-=" => TokenKind.SUB_ASSIGN
            case "*=" => TokenKind.MUL_ASSIGN
            case "**=" => TokenKind.EXP_ASSIGN
            case "/=" => TokenKind.DIV_ASSIGN
            case "%=" => TokenKind.MOD_ASSIGN
            case "&&=" => TokenKind.AND_ASSIGN
            case "||=" => TokenKind.OR_ASSIGN
            case "&=" => TokenKind.BITAND_ASSIGN
            case "|=" => TokenKind.BITOR_ASSIGN
            case "^=" => TokenKind.BITXOR_ASSIGN
            case "<<=" => TokenKind.LSHIFT_ASSIGN
            case ">>=" => TokenKind.RSHIFT_ASSIGN
            case "->" => TokenKind.ARROW
            case "<-" => TokenKind.BACKARROW
            case "=>" => TokenKind.DOUBLE_ARROW
            case ".." => TokenKind.RANGEOP
            case "..=" => TokenKind.CLOSEDRANGEOP
            case "..." => TokenKind.ELLIPSIS
            case "#" => TokenKind.HASH
            case "@" => TokenKind.AT
            case "?" => TokenKind.QUEST
            case "<" => TokenKind.LT
            case ">" => TokenKind.GT
            case "<=" => TokenKind.LE
            case ">=" => TokenKind.GE
            case "is" => TokenKind.IS
            case "as" => TokenKind.AS
            case "!=" => TokenKind.NOTEQ
            case "==" => TokenKind.EQUAL
            case "_" => TokenKind.WILDCARD
            case "Int8" => TokenKind.INT8
            case "Int16" => TokenKind.INT16
            case "Int32" => TokenKind.INT32
            case "Int64" => TokenKind.INT64
            case "IntNative" => TokenKind.INTNATIVE
            case "UInt8" => TokenKind.UINT8
            case "UInt16" => TokenKind.UINT16
            case "UInt32" => TokenKind.UINT32
            case "UInt64" => TokenKind.UINT64
            case "UIntNative" => TokenKind.UINTNATIVE
            case "Float16" => TokenKind.FLOAT16
            case "Float32" => TokenKind.FLOAT32
            case "Float64" => TokenKind.FLOAT64
            case "Rune" => TokenKind.RUNE
            case "Bool" => TokenKind.BOOLEAN
            case "Nothing" => TokenKind.NOTHING
            case "Unit" => TokenKind.UNIT
            case "struct" => TokenKind.STRUCT
            case "enum" => TokenKind.ENUM
            case "VArray" => TokenKind.VARRAY
            case "This" => TokenKind.THISTYPE
            case "package" => TokenKind.PACKAGE
            case "import" => TokenKind.IMPORT
            case "class" => TokenKind.CLASS
            case "interface" => TokenKind.INTERFACE
            case "func" => TokenKind.FUNC
            case "macro" => TokenKind.MACRO
            case "quote" => TokenKind.QUOTE
            case "$" => TokenKind.DOLLAR
            case "let" => TokenKind.LET
            case "var" => TokenKind.VAR
            case "const" => TokenKind.CONST
            case "type" => TokenKind.TYPE
            case "init" => TokenKind.INIT
            case "this" => TokenKind.THIS
            case "super" => TokenKind.SUPER
            case "if" => TokenKind.IF
            case "else" => TokenKind.ELSE
            case "case" => TokenKind.CASE
            case "try" => TokenKind.TRY
            case "catch" => TokenKind.CATCH
            case "finally" => TokenKind.FINALLY
            case "for" => TokenKind.FOR
            case "do" => TokenKind.DO
            case "while" => TokenKind.WHILE
            case "throw" => TokenKind.THROW
            case "return" => TokenKind.RETURN
            case "continue" => TokenKind.CONTINUE
            case "break" => TokenKind.BREAK
            case "in" => TokenKind.IN
            case "!in" => TokenKind.NOT_IN
            case "match" => TokenKind.MATCH
            case "where" => TokenKind.WHERE
            case "extend" => TokenKind.EXTEND
            case "with" => TokenKind.WITH
            case "prop" => TokenKind.PROP
            case "static" => TokenKind.STATIC
            case "public" => TokenKind.PUBLIC
            case "private" => TokenKind.PRIVATE
            case "internal" => TokenKind.INTERNAL
            case "protected" => TokenKind.PROTECTED
            case "override" => TokenKind.OVERRIDE
            case "redef" => TokenKind.REDEF
            case "abstract" => TokenKind.ABSTRACT
            case "sealed" => TokenKind.SEALED
            case "open" => TokenKind.OPEN
            case "foreign" => TokenKind.FOREIGN
            case "inout" => TokenKind.INOUT
            case "mut" => TokenKind.MUT
            case "unsafe" => TokenKind.UNSAFE
            case "operator" => TokenKind.OPERATOR
            case "spawn" => TokenKind.SPAWN
            case "synchronized" => TokenKind.SYNCHRONIZED
            case "<:" => TokenKind.UPPERBOUND
            case "main" => TokenKind.MAIN
            case "@!" => TokenKind.AT_EXCL
            case "common" => TokenKind.COMMON
            case "specific" => TokenKind.SPECIFIC
            case "perform" => TokenKind.PERFORM
            case "resume" => TokenKind.RESUME
            case "throwing" => TokenKind.THROWING
            case "handle" => TokenKind.HANDLE
            case "::" => TokenKind.DOUBLE_COLON
            case "features" => TokenKind.FEATURES
            case "true" => TokenKind.BOOL_LITERAL
            case "false" => TokenKind.BOOL_LITERAL
            case _ => TokenKind.IDENTIFIER
        }
        if (!ehEnabled &&
            (mapped == TokenKind.PERFORM || mapped == TokenKind.RESUME || mapped == TokenKind.THROWING ||
                mapped == TokenKind.HANDLE)) {
            return TokenKind.IDENTIFIER
        }
        return mapped
    }

    private func currentByte(): UInt8 {
        if (pCurrent < 0 || pCurrent >= bytes.size) {
            return 0u8
        }
        return bytes[pCurrent]
    }

    private func getNextChar(index: Int64): UInt8 {
        let target = pNext + index
        if (target < 0 || target >= bytes.size) {
            return 0u8
        }
        return bytes[target]
    }

    private func getByte(index: Int64): UInt8 {
        if (index < 0 || index >= bytes.size) {
            return 0u8
        }
        return bytes[index]
    }

    private func IsCurrentCharLineTerminator(): Bool {
        return GetLineTerminatorLength(bytes, pCurrent) > 0u8
    }

    private func TryRegisterLineOffset(): Unit {
        var terminateOffset: Int64 = 0
        if (IsCurrentCharLineTerminator()) {
            terminateOffset = pNext
        }
        if (terminateOffset > lineOffsetsFromBase[lineOffsetsFromBase.size - 1]) {
            lineOffsetsFromBase.add(terminateOffset)
        }
    }

    private func CheckArraySize(len: Int64): Bool {
        if (pNext + len > bytes.size) {
            if (success) {
                lexDiagnose(diag, DiagKindRefactor.lex_illegal_UTF8_encoding_byte, GetPos(pNext), ToBinaryString(currentByte()))
                success = false
            }
            pNext = bytes.size
            currentChar = ERROR_UTF8
            return false
        }
        return true
    }

    private func CheckIllegalUTF8InStringLiteral(byte: UInt32): Bool {
        if (byte >= UInt32(BYTE_2_FLAG) || byte < UInt32(BYTE_X_FLAG)) {
            if (success) {
                lexDiagnose(
                    diag, DiagKindRefactor.lex_illegal_UTF8_encoding_byte, GetPos(pCurrent),
                    ToBinaryString(UInt8(byte))
                )
                success = false
            }
            return true
        }
        return false
    }

    private func CheckUnicodeSecurity(ch: Int64): Bool {
        let isControlPictures = ch >= 0x2400 && ch <= 0x243f
        let isPrivateUseAreas = (ch >= 0xe000 && ch <= 0xf8ff) || (ch >= 0xf0000 && ch <= 0xffffd) ||
            (ch >= 0x100000 && ch <= 0x10fffd)
        let isSpecials = ch >= 0xfff0 && ch <= 0xfffb
        let isTags = ch >= 0xe0000 && ch <= 0xe007f
        let isBidirectionalNeutralFormatting = ch == 0x061c || ch == 0x200e || ch == 0x200f
        let isBidirectionalGeneralFormatting = (ch >= 0x202a && ch <= 0x202e) || (ch >= 0x2066 && ch <= 0x2069)
        let isInterlinearAnnotationChar = ch == 0xfff9 || ch == 0xfffa || ch == 0xfffb
        let isPrefixedFormatControl = (ch >= 0x0600 && ch <= 0x0605) || ch == 0x06dd || ch == 0x070f ||
            ch == 0x0890 || ch == 0x0891 || ch == 0x110bd || ch == 0x110cd
        let isEgyptianHieroglyphs = ch >= 0x13430 && ch <= 0x13438
        let isBrahmi = ch == 0x1107f || ch == 0x094d || ch == 0x09cd || ch == 0x0a4d || ch == 0x0acd ||
            ch == 0x0b4d || ch == 0x0bcd || ch == 0x0c4d || ch == 0x0ccd || ch == 0x0d3b || ch == 0x0d3c ||
            ch == 0x0d4d || ch == 0x0dca || ch == 0x0e3a || ch == 0x0e4e || ch == 0x0eba || ch == 0x1039 ||
            ch == 0x1714 || ch == 0x1715 || ch == 0x1734 || ch == 0x17d1 || ch == 0x17d2 || ch == 0x1a60 ||
            ch == 0x1a7a || ch == 0x1b44 || ch == 0x1baa || ch == 0x1bab || ch == 0x1bf2 || ch == 0x1bf3 ||
            ch == 0xa806 || ch == 0xa82c || ch == 0xa8c4 || ch == 0xa953 || ch == 0xa9c0 || ch == 0xaaf6 ||
            ch == 0x10a3f || ch == 0x11046 || ch == 0x11070 || ch == 0x110b9 || ch == 0x11133 || ch == 0x111c0 ||
            ch == 0x11235 || ch == 0x112ea || ch == 0x1134d || ch == 0x11442 || ch == 0x114c2 || ch == 0x115bf ||
            ch == 0x1163f || ch == 0x116b6 || ch == 0x1172b || ch == 0x11839 || ch == 0x1193d || ch == 0x1193e ||
            ch == 0x119e0 || ch == 0x11a34 || ch == 0x11a47 || ch == 0x11a99 || ch == 0x11c3f || ch == 0x11d44 ||
            ch == 0x11d45 || ch == 0x11d97
        let isHistoricalViramas = ch == 0x0f84 || ch == 0x103a || ch == 0x193b || ch == 0xabed || ch == 0x11134
        let isMongolianVariation = ch >= 0x180b && ch <= 0x180e
        let isGenericVariation = (ch >= 0xfe00 && ch <= 0xfe0f) || (ch >= 0xe0100 && ch <= 0xe01ef)
        let isTagCharacters = (ch >= 0xe0020 && ch <= 0xe007f) || ch == 0xe0001 || ch == 0x2d7f || ch == 0x1680
        let isIdeographic = (ch >= 0x2ff0 && ch <= 0x2ffb) || ch == 0x303e
        let isMusicalFormatControl = ch >= 0x1d173 && ch <= 0x1d17a
        let isShorthandFormat = ch >= 0x1bca0 && ch <= 0x1bca3
        let isDeprecatedAlternate = ch >= 0x206a && ch <= 0x206f
        let isOther = ch == 0xfffc || ch == 0xfffd
        let isSpecialPurposeCharacters = isBidirectionalNeutralFormatting || isBidirectionalGeneralFormatting ||
            isInterlinearAnnotationChar || isPrefixedFormatControl || isEgyptianHieroglyphs || isBrahmi ||
            isHistoricalViramas || isMongolianVariation || isGenericVariation || isTagCharacters || isIdeographic ||
            isMusicalFormatControl || isShorthandFormat || isDeprecatedAlternate || isOther
        let isSecurity = isControlPictures || isPrivateUseAreas || isSpecials || isTags || isSpecialPurposeCharacters
        return !isSecurity
    }

    private func CheckUnsecureUnicodeValue(ch: Int64): Unit {
        if (!CheckUnicodeSecurity(ch)) {
            let args = ConvertUnicode(ch)
            let builder = diag.DiagnoseRefactor(DiagKindRefactor.lex_unsecure_unicode, GetPos(pCurrent), arguments: [args])
            builder.AddMainHintArguments([args])
            success = false
        }
    }

    private func ReadUTF8CharFromMultiBytes(first: UInt8): Int64 {
        if (!CheckArraySize(2)) {
            return ERROR_UTF8
        }
        let byte1 = UInt32(first)
        let byte2 = UInt32(getByte(pNext + 1))
        CheckIllegalUTF8InStringLiteral(byte2)
        if (byte2 >= UInt32(BYTE_2_FLAG) || byte2 < UInt32(BYTE_X_FLAG)) {
            pNext += if (byte2 < UInt32(BYTE_X_FLAG)) { 1 } else { 2 }
            return ERROR_UTF8
        } else if (first >= BYTE_4_FLAG) {
            if (!CheckArraySize(4)) {
                return ERROR_UTF8
            }
            let byte3 = UInt32(getByte(pNext + 2))
            let byte4 = UInt32(getByte(pNext + 3))
            CheckIllegalUTF8InStringLiteral(byte3)
            CheckIllegalUTF8InStringLiteral(byte4)
            let ch = ((byte1 & LOW_3_BIT_MASK) << 18) | ((byte2 & LOW_6_BIT_MASK) << 12) |
                ((byte3 & LOW_6_BIT_MASK) << 6) | (byte4 & LOW_6_BIT_MASK)
            CheckUnsecureUnicodeValue(Int64(ch))
            pNext += 4
            if (ch < BYTE_4_BASE) {
                return ERROR_UTF8
            }
            return Int64(ch)
        } else if (first >= BYTE_3_FLAG) {
            if (!CheckArraySize(3)) {
                return ERROR_UTF8
            }
            let byte3 = UInt32(getByte(pNext + 2))
            CheckIllegalUTF8InStringLiteral(byte3)
            let ch = ((byte1 & LOW_4_BIT_MASK) << 12) | ((byte2 & LOW_6_BIT_MASK) << 6) |
                (byte3 & LOW_6_BIT_MASK)
            CheckUnsecureUnicodeValue(Int64(ch))
            pNext += 3
            if (ch < BYTE_3_BASE) {
                return ERROR_UTF8
            }
            return Int64(ch)
        } else {
            let ch = ((byte1 & LOW_5_BIT_MASK) << 6) | (byte2 & LOW_6_BIT_MASK)
            CheckUnsecureUnicodeValue(Int64(ch))
            pNext += 2
            if (ch < BYTE_2_BASE) {
                return ERROR_UTF8
            }
            return Int64(ch)
        }
    }

    private func DecodeUTF8At(index: Int64): (Int64, Int64, Bool) {
        if (index < 0 || index >= bytes.size) {
            return (-1, index, false)
        }
        let first = bytes[index]
        if (first < BYTE_X_FLAG) {
            return (Int64(first), index + 1, true)
        }
        if (first < BYTE_2_FLAG) {
            return (Int64(first), index, false)
        }
        if (index + 1 >= bytes.size) {
            return (Int64(first), index, false)
        }
        let byte1 = UInt32(first)
        let byte2 = UInt32(getByte(index + 1))
        if (byte2 >= UInt32(BYTE_2_FLAG) || byte2 < UInt32(BYTE_X_FLAG)) {
            return (Int64(byte1), index, false)
        }
        if (first >= BYTE_4_FLAG) {
            if (index + 3 >= bytes.size) {
                return (Int64(byte1), index, false)
            }
            let byte3 = UInt32(getByte(index + 2))
            let byte4 = UInt32(getByte(index + 3))
            if (byte3 >= UInt32(BYTE_2_FLAG) || byte3 < UInt32(BYTE_X_FLAG) ||
                byte4 >= UInt32(BYTE_2_FLAG) || byte4 < UInt32(BYTE_X_FLAG)) {
                return (Int64(byte1), index, false)
            }
            let ch = ((byte1 & LOW_3_BIT_MASK) << 18) | ((byte2 & LOW_6_BIT_MASK) << 12) |
                ((byte3 & LOW_6_BIT_MASK) << 6) | (byte4 & LOW_6_BIT_MASK)
            return (Int64(ch), index + 4, ch >= BYTE_4_BASE && ch <= UTF8_4_MAX)
        }
        if (first >= BYTE_3_FLAG) {
            if (index + 2 >= bytes.size) {
                return (Int64(byte1), index, false)
            }
            let byte3 = UInt32(getByte(index + 2))
            if (byte3 >= UInt32(BYTE_2_FLAG) || byte3 < UInt32(BYTE_X_FLAG)) {
                return (Int64(byte1), index, false)
            }
            let ch = ((byte1 & LOW_4_BIT_MASK) << 12) | ((byte2 & LOW_6_BIT_MASK) << 6) |
                (byte3 & LOW_6_BIT_MASK)
            let legalScalar = ch <= 0xd7ffu32 || (ch >= 0xe000u32 && ch <= UTF8_4_MAX)
            return (Int64(ch), index + 3, ch >= BYTE_3_BASE && legalScalar)
        }
        let ch = ((byte1 & LOW_5_BIT_MASK) << 6) | (byte2 & LOW_6_BIT_MASK)
        return (Int64(ch), index + 2, ch >= BYTE_2_BASE)
    }

    private func ReadUTF8Char(): Unit {
        pCurrent = pNext
        if (pNext >= bytes.size) {
            currentChar = -1
            return
        }
        let first = bytes[pNext]
        if (first < BYTE_2_FLAG) {
            currentChar = Int64(first)
            if (first == b'\r' && getNextChar(1) == b'\n') {
                pNext += 2
            } else {
                pNext++
            }
            TryRegisterLineOffset()
            if (first >= BYTE_X_FLAG && success) {
                lexDiagnose(diag, DiagKindRefactor.lex_illegal_UTF8_encoding_byte, GetPos(pCurrent), ToBinaryString(first))
                success = false
            }
            return
        }
        var decoded = ReadUTF8CharFromMultiBytes(first)
        while (decoded == ERROR_UTF8 && pNext < bytes.size) {
            let nextFirst = bytes[pNext]
            if (nextFirst < BYTE_X_FLAG) {
                pCurrent = pNext
                pNext++
                currentChar = ERROR_UTF8
                return
            }
            decoded = ReadUTF8CharFromMultiBytes(nextFirst)
        }
        currentChar = decoded
    }

    private func Back(): Unit {
        pNext = pCurrent
    }

    private func IsAdjacent(first: Int64, second: Int64): Bool {
        if (getByte(first) == b'\r' && first + 1 < bytes.size && getByte(first + 1) == b'\n') {
            return second - first == 2
        }
        return second - first == 1
    }

    private func MoveCurrentToNextByte(): Unit {
        if (pNext < bytes.size) {
            pCurrent = pNext
            currentChar = Int64(bytes[pCurrent])
            pNext++
            return
        }
        pCurrent = pNext
        currentChar = 0
    }

    private func GetPos(current: Int64): Position {
        var offset = if (current > bytes.size) { bytes.size } else { current }
        if (offset < 0) {
            offset = 0
        }
        var loc = lineOffsetsFromBase.size - 1
        if (offset < lineOffsetsFromBase[lineOffsetsFromBase.size - 1]) {
            var idx: Int64 = 0
            while (idx + 1 < lineOffsetsFromBase.size && lineOffsetsFromBase[idx + 1] <= offset) {
                idx++
            }
            loc = idx
        }
        if (bytes.size > 0 && current == bytes.size && loc != 0) {
            if (bytes[current - 1] == b'\n') {
                loc--
            }
            if (current - 2 >= 0 && bytes[current - 2] == b'\r' && bytes[current - 1] == b'\n') {
                offset--
            }
        }
        let columnBase = if (loc == 0) { posBase.column } else { 1 }
        let column = columnBase + offset - lineOffsetsFromBase[loc]
        return Position(posBase.fileID, posBase.line + loc, column)
    }

    private func ConvertCurrentChar(): String {
        if (IsCurrentCharLineTerminator()) {
            return "new line character"
        }
        return ConvertChar(currentChar)
    }

    private func PrefixName(prefix: UInt8): String {
        return match (prefix) {
            case b'x' => "hexadecimal"
            case b'o' => "octal"
            case b'b' => "binary"
            case _ => "decimal"
        }
    }

    private func DigitRangeText(prefix: UInt8): String {
        return match (prefix) {
            case b'b' => "0~1"
            case b'o' => "0~7"
            case b'x' => "0~9 or a~f"
            case _ => "0~9"
        }
    }

    private func DiagUnexpectedDecimalPoint(reasonPoint: Int64): Unit {
        let baseChar = lowerByte(getByte(reasonPoint))
        let prefix = PrefixName(baseChar)
        let builder = diag.DiagnoseRefactor(
            DiagKindRefactor.lex_unexpected_decimal_point, GetPos(pCurrent), arguments: [prefix]
        )
        let reasonRange = MakeRange(GetPos(reasonPoint - 1), GetPos(reasonPoint) + 1)
        builder.AddHint(reasonRange, arguments: [prefix])
        builder.AddNote("only decimal or hexadecimal number can support fractional part")
        let decimalHelp = DiagHelp("if you expect a decimal fraction, could remove the prefix")
        decimalHelp.AddSubstitution(reasonRange, " ")
        builder.AddHelp(decimalHelp)
        let hexadecimalHelp = DiagHelp("if you expect a hexadecimal fraction, could use hexadecimal prefix")
        hexadecimalHelp.AddSubstitution(reasonRange, "0x")
        builder.AddHelp(hexadecimalHelp)
    }

    private func DiagExpectedDigit(base: UInt8): Unit {
        let name = PrefixName(base)
        let builder = diag.DiagnoseRefactor(
            DiagKindRefactor.lex_expected_digit, MakeRange(GetPos(pCurrent), GetPos(pNext)),
            arguments: [name, ConvertCurrentChar()]
        )
        builder.AddMainHintArguments([name])
    }

    private func DiagUnexpectedDigit(base: Int64, reasonPoint: Int64): Unit {
        let baseChar = lowerByte(getByte(reasonPoint))
        let name = PrefixName(baseChar)
        let builder = diag.DiagnoseRefactor(
            DiagKindRefactor.lex_unexpected_digit, GetPos(pCurrent),
            arguments: [ConvertCurrentChar(), name]
        )
        var rangePrefix = b'd'
        if (base != DEC_BASE) {
            builder.AddHint(
                MakeRange(GetPos(reasonPoint - 1), GetPos(reasonPoint) + 1),
                arguments: ["of this " + name + " prefix"]
            )
            rangePrefix = baseChar
        } else if (baseChar == b'e' || baseChar == b'p') {
            builder.AddHint(GetPos(reasonPoint), arguments: ["the exponent part base is decimal"])
        } else {
            builder.AddHint(MakeRange(GetPos(reasonPoint), GetPos(pCurrent)), arguments: ["the default base is decimal"])
        }
        builder.AddNote(name + " may only contain digit within " + DigitRangeText(rangePrefix))
    }

    private func DiagUnexpectedExponentPart(exp: UInt8, prefix: UInt8, reasonPoint: Int64): Unit {
        let prefixName = PrefixName(prefix)
        if (prefix != b'd' && prefix != b'x') {
            let reasonRange = MakeRange(GetPos(reasonPoint - 1), GetPos(reasonPoint) + 1)
            let builder = diag.DiagnoseRefactor(
                DiagKindRefactor.lex_unexpected_exponent_part, GetPos(pCurrent),
                arguments: [byteString(UInt8(currentChar)), prefixName]
            )
            builder.AddHint(reasonRange, arguments: ["of this " + prefixName + " prefix"])
            builder.AddNote("only decimal or hexadecimal number can support exponent part")
            return
        }
        if (exp == b'e' && prefix == b'x') {
            let reasonRange = MakeRange(GetPos(reasonPoint - 1), GetPos(reasonPoint) + 1)
            let builder = diag.DiagnoseRefactor(
                DiagKindRefactor.lex_unexpected_exponent_part, GetPos(pCurrent),
                arguments: [byteString(UInt8(currentChar)), prefixName]
            )
            builder.AddHint(reasonRange, arguments: ["of this " + prefixName + " prefix"])
            let help = DiagHelp("could try to modify it to hexadecimal exponent type")
            help.AddSubstitution(GetPos(pCurrent), "p")
            builder.AddHelp(help)
            return
        }
        if (exp == b'p' && prefix == b'd') {
            let reasonRange = MakeRange(GetPos(reasonPoint), GetPos(pCurrent))
            let builder = diag.DiagnoseRefactor(
                DiagKindRefactor.lex_unexpected_exponent_part, GetPos(pCurrent),
                arguments: [byteString(UInt8(currentChar)), prefixName]
            )
            builder.AddHint(reasonRange, arguments: ["the default base is decimal"])
            let help = DiagHelp("could try to modify it to " + prefixName + " exponent type")
            help.AddSubstitution(GetPos(pCurrent), "e")
            builder.AddHelp(help)
        }
    }

    private func DiagExpectedExponentPart(reasonPoint: Int64): Unit {
        let start = reasonPoint - 1
        let reasonRange = MakeRange(GetPos(start), GetPos(pCurrent))
        let builder = diag.DiagnoseRefactor(
            DiagKindRefactor.lex_expected_exponent_part, GetPos(pCurrent), arguments: [input[start..pCurrent]]
        )
        builder.AddHint(reasonRange)
    }

    private func DiagIllegalUnicodeAtCurrent(): Unit {
        let args = ConvertUnicode(currentChar)
        let builder = diag.DiagnoseRefactor(DiagKindRefactor.lex_illegal_unicode, GetPos(pCurrent), arguments: [args])
        builder.AddMainHintArguments([args])
    }

    private func TryConsumeIdentifierUTF8Char(): Bool {
        CJC_ASSERT(pNext != pCurrent)
        pCurrent = pNext
        let decoded = DecodeUTF8At(pNext)
        if (!decoded[2]) {
            currentChar = decoded[0]
            pNext = pCurrent + 1
            DiagIllegalUnicodeAtCurrent()
            success = false
            return false
        }
        currentChar = decoded[0]
        pNext = decoded[1]
        if (!isXIDContinue(currentChar)) {
            DiagIllegalUnicodeAtCurrent()
            success = false
            return false
        }
        return true
    }

    private func DiagSmallExpectedDigit(hasDigit: Bool, base: UInt8): Unit {
        if (!hasDigit && success) {
            DiagExpectedDigit(base)
            success = false
        }
    }

    private func TrimmedHex(value: UInt32): String {
        let raw = ToHexString(value, len: 8)
        var idx: Int64 = 0
        while (idx + 1 < raw.size && raw[idx] == b'0') {
            idx++
        }
        return raw[idx..]
    }

    private func IsLegalUnicodeScalar(value: UInt32): Bool {
        return value <= 0xd7ffu32 || (value >= 0xe000u32 && value <= UTF8_4_MAX)
    }

    private func DiagExpectedRightBracket(pStart: Int64): Unit {
        let builder = diag.DiagnoseRefactor(
            DiagKindRefactor.lex_expected_right_bracket, GetPos(pCurrent), arguments: [ConvertCurrentChar()]
        )
        builder.AddHint(GetPos(pStart + 2))
        builder.AddNote("unicode escape may contain 8 hexadecimal digits at most")
    }

    private func DiagExpectedRightBracketOrHexadecimal(pStart: Int64): Unit {
        let builder = diag.DiagnoseRefactor(
            DiagKindRefactor.lex_expected_right_bracket_or_hexadecimal, GetPos(pCurrent),
            arguments: [ConvertCurrentChar()]
        )
        builder.AddHint(MakeRange(GetPos(pStart), GetPos(pStart + 2)))
        builder.AddNote("unicode escape may only contain hexadecimal digits")
    }

    private func ProcessUnicodeEscape(): Unit {
        var hexNum: Int64 = 0
        var hexVal: UInt32 = 0u32
        let escapeStart = pCurrent - 1
        ReadUTF8Char()
        if (currentChar != Int64(b'{')) {
            if (success) {
                let builder = diag.DiagnoseRefactor(
                    DiagKindRefactor.lex_expected_left_bracket, GetPos(pCurrent), arguments: [ConvertCurrentChar()]
                )
                builder.AddHint(MakeRange(GetPos(pCurrent - 2), GetPos(pCurrent)))
                success = false
            }
            return
        }
        while (true) {
            ReadUTF8Char()
            if (hexNum == UNICODE_MAX_NUM || !isHexDigit(currentChar)) {
                Back()
                break
            }
            hexNum++
            if (currentChar <= Int64(b'9')) {
                hexVal = (hexVal << 4) | UInt32(currentChar - Int64(b'0'))
            } else if (currentChar >= Int64(b'a')) {
                hexVal = (hexVal << 4) | (UInt32(currentChar - Int64(b'a')) + 10u32)
            } else {
                hexVal = (hexVal << 4) | (UInt32(currentChar - Int64(b'A')) + 10u32)
            }
        }
        if (hexNum == 0 && success) {
            DiagExpectedDigit(b'x')
            success = false
        }
        if (hexNum == UNICODE_MAX_NUM && isHexDigit(currentChar) && success) {
            DiagExpectedRightBracket(escapeStart)
            Back()
            success = false
        }
        ReadUTF8Char()
        if (currentChar != Int64(b'}') && success) {
            if (hexNum == UNICODE_MAX_NUM) {
                DiagExpectedRightBracket(escapeStart)
            } else {
                DiagExpectedRightBracketOrHexadecimal(escapeStart)
            }
            Back()
            success = false
        }
        if (!IsLegalUnicodeScalar(hexVal) && success) {
            lexDiagnose(
                diag, DiagKindRefactor.lex_illegal_uni_character_literal,
                MakeRange(GetPos(escapeStart), GetPos(pNext)), TrimmedHex(hexVal)
            )
        }
    }

    private func EscapeNote(target: String, isByteLiteral: Bool): String {
        var note = "found " + if (isByteLiteral) { "11" } else { "12" } + " possible escapes: "
        note += "'\\b', '\\t', '\\n', '\\v', '\\f', '\\r', "
        note += "'\\0', '\\\\', '\\'', '\\\"', '\\u{__}'"
        if (!isByteLiteral) {
            note += ", '\\$'"
        }
        return note + " in " + target + " literal"
    }

    private func DiagUnrecognizedEscape(pStart: Int64, isInString: Bool, isByteLiteral: Bool): Unit {
        var target = if (isInString) { "string" } else { "rune" }
        if (isByteLiteral) {
            target += " byte"
        }
        if (isInString && isByteLiteral) {
            target = "byte array"
        }
        let escaped = "\\" + ConvertCurrentChar()
        let builder = diag.DiagnoseRefactor(
            DiagKindRefactor.lex_unrecognized_escape,
            MakeRange(GetPos(pCurrent - 1), GetPos(pCurrent) + ConvertCurrentChar().size),
            arguments: [escaped, target]
        )
        if (getByte(pStart) == b'"' && getByte(pStart + 1) == b'"') {
            builder.AddHint(MakeRange(GetPos(pStart), GetPos(pStart + 3)), arguments: [target])
        } else {
            builder.AddHint(GetPos(pStart), arguments: [target])
        }
        builder.AddNote(EscapeNote(target, isByteLiteral))
    }

    private func ProcessEscape(pStart: Int64, isInString: Bool, isByteLiteral: Bool): Unit {
        ReadUTF8Char()
        if (isLegalEscape(currentChar) || (!isByteLiteral && currentChar == Int64(b'$'))) {
            return
        }
        if (currentChar == Int64(b'u')) {
            ProcessUnicodeEscape()
            return
        }
        if (success) {
            DiagUnrecognizedEscape(pStart, isInString, isByteLiteral)
            success = false
        }
        Back()
    }

    private func ProcessDigits(base: Int64, hasDigitRef: Bool, reasonPoint: Int64, isFloatRef: Bool): (Bool, Bool, Bool) {
        var hasDigit = hasDigitRef
        var isFloat = false
        var hasTypeSuffix = false
        var digitIndex: Int64 = 0
        while (true) {
            if (digitIndex == 0 && isFloatRef && isDigit(currentChar)) {
                isFloat = true
                tokenKind = TokenKind.FLOAT_LITERAL
            }
            if (currentChar > Int64(ASCII_BASE)) {
                if (success) {
                    DiagExpectedDigit(lowerByte(getByte(reasonPoint)))
                    success = false
                }
            } else if (isDigit(currentChar)) {
                hasDigit = true
                if (base <= DEC_BASE && currentChar >= Int64(b'0') + base && success) {
                    DiagUnexpectedDigit(base, reasonPoint)
                    success = false
                }
            } else if (isHexDigit(currentChar)) {
                let xdigitResult = ProcessXdigit(base, hasDigit, reasonPoint)
                hasDigit = xdigitResult[0]
                if (!xdigitResult[1]) {
                    break
                }
            } else if (tokenKind != TokenKind.FLOAT_LITERAL && hasDigit &&
                (currentChar == Int64(b'i') || currentChar == Int64(b'u'))) {
                hasTypeSuffix = true
                ProcessIntegerSuffix()
                return (hasDigit, isFloat, hasTypeSuffix)
            } else if (currentChar == Int64(b'_')) {
            } else {
                break
            }
            ReadUTF8Char()
            digitIndex++
        }
        return (hasDigit, isFloat, hasTypeSuffix)
    }

    private func ProcessXdigit(base: Int64, hasDigitRef: Bool, reasonPoint: Int64): (Bool, Bool) {
        var hasDigit = hasDigitRef
        if (base != HEX_BASE && (currentChar == Int64(b'e') || currentChar == Int64(b'E'))) {
            return (hasDigit, false)
        }
        if (base != HEX_BASE && currentChar == Int64(b'f')) {
            return (hasDigit, false)
        }
        hasDigit = true
        if (base != HEX_BASE && success) {
            DiagUnexpectedDigit(base, reasonPoint)
            success = false
        }
        return (hasDigit, true)
    }

    private func GetSuffix(pSuffixStart: Int64): String {
        while (isAlnum(currentChar)) {
            ReadUTF8Char()
        }
        if (pSuffixStart + 1 < pCurrent) {
            return input[pSuffixStart + 1..pCurrent]
        }
        return ""
    }

    private func ProcessIntegerSuffix(): Unit {
        let suffixType = byteString(UInt8(currentChar))
        let pSuffixStart = pCurrent
        let suffix = GetSuffix(pSuffixStart)
        if (!(suffix == "64" || suffix == "32" || suffix == "8" || suffix == "16")) {
            let builder = diag.DiagnoseRefactor(
                DiagKindRefactor.lex_illegal_integer_suffix, MakeRange(GetPos(pSuffixStart), GetPos(pCurrent)),
                arguments: [suffixType + suffix]
            )
            builder.AddNote(
                "integer literal type suffix can only be 'u8', 'u16', 'u32', 'u64', 'i8', 'i16', 'i32', 'i64'"
            )
            success = false
            tokenKind = TokenKind.ILLEGAL
        }
        Back()
    }

    private func ProcessFloatSuffix(prefix: UInt8): Unit {
        tokenKind = TokenKind.FLOAT_LITERAL
        let pSuffixStart = pCurrent
        if (prefix != b'd') {
            lexDiagnose(diag, DiagKindRefactor.lex_illegal_non_decimal_float, GetPos(pSuffixStart))
            success = false
            tokenKind = TokenKind.ILLEGAL
        }
        let suffix = GetSuffix(pSuffixStart)
        if (!(suffix == "64" || suffix == "32" || suffix == "16")) {
            let builder = diag.DiagnoseRefactor(
                DiagKindRefactor.lex_illegal_float_suffix, MakeRange(GetPos(pSuffixStart), GetPos(pCurrent)),
                arguments: ["f" + suffix]
            )
            builder.AddNote("float literal type suffix can only be 'f16', 'f32', 'f64'")
            success = false
            tokenKind = TokenKind.ILLEGAL
        }
    }

    private func ScanNumberIntegerPart(
        pStart: Int64,
        baseRef: Int64,
        prefixRef: UInt8,
        hasDigitRef: Bool,
        reasonPointRef: Int64
    ): (Int64, UInt8, Bool, Int64, Bool) {
        tokenKind = TokenKind.INTEGER_LITERAL
        var base = baseRef
        var prefix = prefixRef
        var hasDigit = hasDigitRef
        var reasonPoint = reasonPointRef
        let nextChar = getNextChar(0)
        if (currentChar == Int64(b'0')) {
            if (nextChar == b'i' || nextChar == b'u' || nextChar == b'f') {
                base = DEC_BASE
                prefix = b'd'
                hasDigit = true
                let digits = ProcessDigits(base, hasDigit, reasonPoint, false)
                return (base, prefix, digits[0], reasonPoint, digits[2])
            }
            ReadUTF8Char()
            let lower = lowerByte(UInt8(currentChar))
            if (lower == b'x') {
                reasonPoint = pCurrent
                ReadUTF8Char()
                base = HEX_BASE
                prefix = b'x'
            } else if (lower == b'o') {
                reasonPoint = pCurrent
                ReadUTF8Char()
                base = OCT_BASE
                prefix = b'o'
            } else if (lower == b'b') {
                reasonPoint = pCurrent
                ReadUTF8Char()
                base = BIN_BASE
                prefix = b'b'
            } else {
                reasonPoint = pStart
                base = DEC_BASE
                prefix = b'd'
                hasDigit = true
            }
        }
        if (prefix != b'd' && currentChar == Int64(b'_') && success) {
            DiagExpectedDigit(prefix)
            success = false
        }
        let digitsResult = ProcessDigits(base, hasDigit, reasonPoint, false)
        return (base, prefix, digitsResult[0], reasonPoint, digitsResult[2])
    }

    private func ScanNumberDecimalPart(
        base: Int64,
        prefix: UInt8,
        hasDigitRef: Bool,
        isFloatRef: Bool,
        reasonPoint: Int64
    ): (Bool, Bool) {
        var hasDigit = hasDigitRef
        var isFloat = isFloatRef
        if ((prefix == b'o' || prefix == b'b') && success) {
            DiagUnexpectedDecimalPoint(reasonPoint)
            success = false
        }
        ReadUTF8Char()
        let digits = ProcessDigits(base, hasDigit, reasonPoint, true)
        hasDigit = digits[0]
        isFloat = digits[1]
        return (hasDigit, isFloat)
    }

    private func IsIllegalStartDecimalPart(pStart: Int64, pEnd: Int64): Bool {
        if (pStart > pEnd || getByte(pStart) != b'0') {
            return false
        }
        var start = pStart + 1
        if (start > pEnd) {
            return false
        }
        if (getByte(start) >= b'0' && getByte(start) <= b'9') {
            return true
        }
        if (getByte(start) != b'_') {
            return false
        }
        start++
        while (start <= pEnd && getByte(start) == b'_') {
            start++
        }
        return start <= pEnd && getByte(start) >= b'0' && getByte(start) <= b'9'
    }

    private func ScanNumber(pStart: Int64): Token {
        var base: Int64 = DEC_BASE
        var prefix: UInt8 = b'd'
        var reasonPoint = pStart
        var hasDigit = false
        var dotPos: Int64 = -1
        if (currentChar != Int64(b'.')) {
            let integerPart = ScanNumberIntegerPart(pStart, base, prefix, hasDigit, reasonPoint)
            base = integerPart[0]
            prefix = integerPart[1]
            hasDigit = integerPart[2]
            reasonPoint = integerPart[3]
            if (integerPart[4]) {
                if (IsIllegalStartDecimalPart(pStart, pCurrent)) {
                    lexDiagnose2(diag, DiagKindRefactor.lex_cannot_start_with_digit, GetPos(pStart), "integer", "0")
                }
                Back()
                return Token(tokenKind, input[pStart..pNext], pos, GetPos(pNext))
            }
            dotPos = pCurrent
        }
        var isFloat = false
        var hasDot = false
        if (currentChar == Int64(b'.')) {
            if (prefix == b'x') {
                if (!isHexDigit(Int64(getNextChar(0)))) {
                    DiagSmallExpectedDigit(hasDigit, prefix)
                    Back()
                    return Token(tokenKind, input[pStart..pNext], pos, GetPos(pNext))
                }
            } else if (!isDigit(Int64(getNextChar(0)))) {
                DiagSmallExpectedDigit(hasDigit, prefix)
                Back()
                return Token(tokenKind, input[pStart..pNext], pos, GetPos(pNext))
            }
            if (IsIllegalStartDecimalPart(pStart, pCurrent)) {
                lexDiagnose2(diag, DiagKindRefactor.lex_cannot_start_with_digit, GetPos(pStart), "float", "0")
            }
            hasDigit = false
            let decimalPart = ScanNumberDecimalPart(base, prefix, hasDigit, isFloat, reasonPoint)
            hasDigit = decimalPart[0]
            isFloat = decimalPart[1]
            hasDot = true
        } else if (IsIllegalStartDecimalPart(pStart, pCurrent)) {
            lexDiagnose2(diag, DiagKindRefactor.lex_cannot_start_with_digit, GetPos(pStart), "integer", "0")
        }
        DiagSmallExpectedDigit(hasDigit, prefix)
        isFloat = ProcessNumberExponentPart(prefix, reasonPoint, isFloat)
        ProcessNumberFloatSuffix(prefix, isFloat, hasDot)
        if (!isFloat && hasDot && success && dotPos > 0) {
            pNext = dotPos
            pCurrent = dotPos - 1
        }
        return Token(tokenKind, input[pStart..pNext], pos, GetPos(pNext))
    }

    private func ProcessNumberExponentPart(prefix: UInt8, reasonPoint: Int64, isFloatRef: Bool): Bool {
        var isFloat = isFloatRef
        let exp = lowerByte(UInt8(currentChar))
        if (exp == b'e' || exp == b'p') {
            if (success && ((prefix != b'd' && prefix != b'x') || (exp == b'e' && prefix == b'x') ||
                (exp == b'p' && prefix == b'd'))) {
                DiagUnexpectedExponentPart(exp, prefix, reasonPoint)
                success = false
            }
            isFloat = true
            tokenKind = TokenKind.FLOAT_LITERAL
            ScanNumberExponentPart(reasonPoint)
        } else if (success && prefix == b'x' && tokenKind == TokenKind.FLOAT_LITERAL && isFloat) {
            DiagExpectedExponentPart(reasonPoint)
            success = false
        }
        return isFloat
    }

    private func ScanNumberExponentPart(reasonPoint: Int64): Unit {
        let expReasonPoint = if (reasonPoint == pCurrent) { reasonPoint } else { pCurrent }
        ReadUTF8Char()
        tokenKind = TokenKind.FLOAT_LITERAL
        if (currentChar == Int64(b'-')) {
            ReadUTF8Char()
        }
        if (currentChar == Int64(b'_') && success) {
            DiagExpectedDigit(b'd')
            success = false
        }
        var expHasDigit = false
        let digits = ProcessDigits(DEC_BASE, expHasDigit, expReasonPoint, false)
        expHasDigit = digits[0]
        if (!expHasDigit && success) {
            DiagExpectedDigit(b'd')
            success = false
        }
    }

    private func ProcessNumberFloatSuffix(prefix: UInt8, isFloat: Bool, hasDot: Bool): Unit {
        let nonDigitStart = pCurrent
        var hasSuffix = false
        if (currentChar == Int64(b'f')) {
            ProcessFloatSuffix(prefix)
            hasSuffix = true
        }
        let suffixBegin = pCurrent
        while (isAlnum(currentChar) || currentChar == Int64(b'.') || currentChar == Int64(b'_')) {
            if (currentChar == Int64(b'.') && getNextChar(0) == b'.' && getNextChar(1) != b'.') {
                Back()
                break
            }
            if (pNext >= bytes.size) {
                break
            }
            if (currentChar == Int64(b'.')) {
                let decoded = DecodeUTF8At(pNext)
                if (decoded[2]) {
                    if (isCJXIDStart(decoded[0])) {
                        break
                    }
                    currentChar = decoded[0]
                    pNext = decoded[1]
                    continue
                }
                currentChar = decoded[0]
                break
            }
            ReadUTF8Char()
        }
        if (((!isFloat && hasSuffix) || (suffixBegin != pNext && !IsAdjacent(suffixBegin, pNext) &&
            (isFloat || !hasDot))) && success) {
            let errPoint = if (isFloat) { suffixBegin } else { nonDigitStart }
            var args = input[errPoint..pCurrent]
            if (args.isEmpty()) {
                args = "."
            }
            let builder = diag.DiagnoseRefactor(
                DiagKindRefactor.lex_unknown_suffix, MakeRange(GetPos(errPoint), GetPos(pCurrent)),
                arguments: [args]
            )
            builder.AddMainHintArguments([args])
        }
        Back()
    }

    private func ScanDotPrefixSymbol(): Token {
        if (getNextChar(0) == b'.') {
            ReadUTF8Char()
            if (getNextChar(0) == b'.') {
                ReadUTF8Char()
                return Token(TokenKind.ELLIPSIS, "...", pos, GetPos(pNext))
            } else if (getNextChar(0) == b'=') {
                ReadUTF8Char()
                return Token(TokenKind.CLOSEDRANGEOP, "..=", pos, GetPos(pNext))
            }
            return Token(TokenKind.RANGEOP, "..", pos, GetPos(pNext))
        }
        return Token(TokenKind.DOT, ".", pos, GetPos(pNext))
    }

    private func ScanNumberOrDotPrefixSymbol(pStart: Int64): Token {
        if (currentChar == Int64(b'.') && !isDigit(Int64(getNextChar(0)))) {
            return ScanDotPrefixSymbol()
        }
        return ScanNumber(pStart)
    }

    private func ScanIdentifierContinue(resRef: Token, pStart: Int64): Token {
        var res = resRef
        res.kind = TokenKind.IDENTIFIER
        while (pNext < bytes.size) {
            let nextValue = Int64(getNextChar(0))
            if (isAsciiIdentifierContinue(nextValue)) {
                pCurrent = pNext
                pNext++
                continue
            }
            if (nextValue <= 127) {
                break
            }
            if (!TryConsumeIdentifierUTF8Char()) {
                res.kind = TokenKind.ILLEGAL
                break
            }
        }
        var value = input[pStart..pNext]
        if (res.kind == TokenKind.IDENTIFIER) {
            value = NormalizeIdentifierNFC(value)
        }
        res.SetValuePos(value, GetPos(pStart), GetPos(pNext))
        return res
    }

    private func ScanIdentifierOrKeyword(resRef: Token, pStart: Int64): Token {
        var res = resRef
        if (isAsciiIdentifierStart(currentChar)) {
            res = ScanIdentifierContinue(res, pStart)
            res.kind = LookupKeyword(res.Value())
            return res
        }
        if (isCJXIDStart(currentChar)) {
            res = ScanIdentifierContinue(res, pStart)
            return res
        }
        if (success) {
            lexDiagnose(diag, DiagKindRefactor.lex_illegal_unicode, GetPos(pStart), ConvertCurrentChar())
            success = false
        }
        res.SetValuePos(input[pStart..pNext], GetPos(pStart), GetPos(pNext))
        res.kind = TokenKind.ILLEGAL
        return res
    }

    private func ScanBackquotedIdentifierPart(resRef: Token): (Token, Bool) {
        var res = resRef
        ReadUTF8Char()
        if (isCJXIDStart(currentChar)) {
            res = ScanIdentifierContinue(res, pCurrent)
            if (res.Value() == "_") {
                res.kind = TokenKind.WILDCARD
                lexDiagnose(diag, DiagKindRefactor.lex_expected_letter_after_underscore, MakeRange(GetPos(pCurrent), GetPos(pCurrent + 1)))
            }
            MoveCurrentToNextByte()
            return (res, true)
        }
        return (res, false)
    }

    private func ScanBackquotedIdentifier(pStart: Int64): Token {
        var res = Token(TokenKind.ILLEGAL)
        var isPackageIdent = false
        var scanned = ScanBackquotedIdentifierPart(res)
        res = scanned[0]
        if (scanned[1]) {
            while (currentChar == Int64(b'.') || currentChar == Int64(b'-') || currentChar == Int64(b' ')) {
                isPackageIdent = true
                let pLast = pCurrent
                scanned = ScanBackquotedIdentifierPart(res)
                res = scanned[0]
                if (scanned[1]) {
                    continue
                }
                if (IsAdjacent(pLast, pCurrent) && success) {
                    lexDiagnose(diag, DiagKindRefactor.lex_expected_identifier, GetPos(pCurrent), ConvertCurrentChar())
                    success = false
                }
                break
            }
        }

        res.SetValuePos("`" + res.Value(), GetPos(pStart), GetPos(pNext))
        res.kind = if (isPackageIdent) { TokenKind.PACKAGE_IDENTIFIER } else { TokenKind.IDENTIFIER }

        if (currentChar == Int64(b'`')) {
            if (IsAdjacent(pStart, pCurrent) && success) {
                lexDiagnose(diag, DiagKindRefactor.lex_expected_identifier, GetPos(pCurrent), ConvertCurrentChar())
                success = false
            }
            res.SetValuePos(res.Value() + "`", res.Begin(), res.End())
        } else {
            Back()
            if (!IsAdjacent(pStart, pCurrent) && success) {
                let builder = diag.DiagnoseRefactor(
                    DiagKindRefactor.lex_expected_back_quote, GetPos(pCurrent), arguments: [ConvertCurrentChar()]
                )
                builder.AddHint(GetPos(pStart))
                success = false
            } else if (success) {
                lexDiagnose(diag, DiagKindRefactor.lex_expected_identifier, GetPos(pCurrent), ConvertCurrentChar())
                success = false
            }
            while (currentChar != Int64(b'`') && currentChar != Int64(b' ') && !IsCurrentCharLineTerminator() &&
                currentChar != -1) {
                ReadUTF8Char()
            }
        }
        return res
    }

    private func DiagUnterminatedSingleLineString(pStart: Int64, isMatchEnd: Bool, isJString: Bool): Unit {
        let builder = diag.DiagnoseRefactor(
            DiagKindRefactor.lex_unterminated_single_line_string,
            MakeRange(GetPos(pStart), GetPos(pCurrent) + 1)
        )
        if (!interpolations.isEmpty() && !stringStarts.isEmpty()) {
            let interpolation = interpolations[interpolations.size - 1]
            let stringStart = stringStarts[stringStarts.size - 1]
            if (interpolation < pStart && !stringStart[1]) {
                builder.AddHint(MakeRange(GetPos(interpolation), GetPos(interpolation + 2)))
            }
        }
        if (!isMatchEnd && !isJString) {
            builder.AddNote("consider using multi-line string if you intended to include '\\n' in string")
        }
    }

    private func DiagUnterminatedMultiLineString(pStart: Int64): Unit {
        let builder = diag.DiagnoseRefactor(
            DiagKindRefactor.lex_unterminated_multi_line_string,
            MakeRange(GetPos(pStart), GetPos(pCurrent))
        )
        if (!interpolations.isEmpty() && !stringStarts.isEmpty()) {
            let interpolation = interpolations[interpolations.size - 1]
            let stringStart = stringStarts[stringStarts.size - 1]
            if (interpolation < pStart && stringStart[1]) {
                builder.AddHint(MakeRange(GetPos(interpolation), GetPos(interpolation + 2)))
            }
        }
    }

    private func DiagUnterminatedRawString(pStart: Int64): Unit {
        let builder = diag.DiagnoseRefactor(
            DiagKindRefactor.lex_unterminated_raw_string,
            MakeRange(GetPos(pStart), GetPos(pCurrent))
        )
        if (!interpolations.isEmpty() && !stringStarts.isEmpty()) {
            let interpolation = interpolations[interpolations.size - 1]
            let stringStart = stringStarts[stringStarts.size - 1]
            if (interpolation < pStart && !stringStart[1]) {
                builder.AddHint(MakeRange(GetPos(interpolation), GetPos(interpolation + 2)))
            }
        }
    }

    private func DiagUnterminatedInterpolation(): Unit {
        if (interpolations.isEmpty()) {
            lexDiagnose(diag, DiagKindRefactor.lex_unterminated_interpolation, GetPos(pCurrent))
            return
        }
        let interpolation = interpolations[interpolations.size - 1]
        let builder = diag.DiagnoseRefactor(
            DiagKindRefactor.lex_unterminated_interpolation,
            MakeRange(GetPos(interpolation), GetPos(pCurrent) + 1)
        )
        if (!stringStarts.isEmpty()) {
            builder.AddHint(GetPos(stringStarts[stringStarts.size - 1][0]))
        }
    }

    private func ProcessIllegalToken(needStringParts: Bool, multiLine: Bool, pStart: Int64, isJString!: Bool = false): Token {
        let isMatchEnd = currentChar == -1
        if (success) {
            if (multiLine) {
                DiagUnterminatedMultiLineString(pStart)
            } else {
                DiagUnterminatedSingleLineString(pStart, isMatchEnd, isJString)
            }
            success = false
        }
        let tokKind = if (multiLine) {
            TokenKind.MULTILINE_STRING
        } else if (isJString) {
            TokenKind.JSTRING_LITERAL
        } else {
            TokenKind.STRING_LITERAL
        }
        let token = Token(tokKind, input[pStart..pCurrent], pos, GetPos(pCurrent))
        if (needStringParts) {
            let parts = ArrayList<StringPart>()
            parts.add(StringPart(StringPartKind.STR, token.Value(), token.Begin(), token.End()))
            stringPartsMap.add(token, parts)
        }
        return token
    }

    private func ScanStringOrJString(pStart: Int64, needStringParts!: Bool = true, isJString!: Bool = false): (Token, Bool) {
        var res = true
        let stringParts = ArrayList<StringPart>()
        var begin = pStart + 1
        stringStarts.add((pStart, false))
        tokenKind = if (isJString) { TokenKind.JSTRING_LITERAL } else { TokenKind.STRING_LITERAL }
        var offset: Int64 = 1
        var beginPos = GetPos(begin)
        if (isJString) {
            ReadUTF8Char()
            offset++
            begin = pStart + offset
            beginPos = GetPos(begin)
        }
        let quoteChar = currentChar
        while (true) {
            ReadUTF8Char()
            if (currentChar == quoteChar) {
                stringParts.add(StringPart(StringPartKind.STR, input[begin..pCurrent], beginPos, GetPos(pCurrent)))
                break
            } else if (IsCurrentCharLineTerminator() || currentChar == -1) {
                stringStarts.remove(at: stringStarts.size - 1)
                return (ProcessIllegalToken(needStringParts, false, if (isJString) { pStart + 1 } else { pStart }, isJString: isJString), false)
            } else if (currentChar == Int64(b'\\')) {
                ProcessEscape(pStart, true, false)
            } else if (currentChar == Int64(b'$') && getNextChar(0) == b'{' && !isJString) {
                let processed = ProcessStringInterpolation(begin, beginPos, stringParts, false)
                begin = processed[0]
                beginPos = GetPos(begin)
                res = processed[1] == 1
                if (!res) {
                    break
                }
            }
        }
        var ret = Token(tokenKind, input[pStart + offset..pCurrent], pos, GetPos(pNext))
        ret.isSingleQuote = quoteChar == Int64(b'\'')
        if (needStringParts) {
            stringPartsMap.add(ret, stringParts)
        }
        stringStarts.remove(at: stringStarts.size - 1)
        return (ret, res)
    }

    private func ScanInterpolationString(allowNewLine: Bool): Bool {
        interpolations.add(pCurrent)
        ReadUTF8Char()
        let balanced = ScanInterpolationStringLiteralHoleBalancedText(b'}', allowNewLine)
        interpolations.remove(at: interpolations.size - 1)
        return balanced && currentChar == Int64(b'}')
    }

    private func ScanInterpolationStringLiteralHoleComment(allowNewline: Bool): Bool {
        if (getNextChar(0) == b'/' && !allowNewline) {
            while (true) {
                ReadUTF8Char()
                if (IsCurrentCharLineTerminator() || currentChar == -1) {
                    break
                }
            }
            if (success) {
                DiagUnterminatedInterpolation()
                success = false
            }
            Back()
            return false
        }
        if (getNextChar(0) == b'*' || getNextChar(0) == b'/') {
            return ScanComment(pCurrent, allowNewLine: allowNewline)[1]
        }
        return true
    }

    private func ProcessInterpolationStringLiteralLineBreak(allowNewline: Bool): Bool {
        if (IsCurrentCharLineTerminator() && allowNewline) {
            return true
        }
        if (success) {
            let interpolation = if (interpolations.isEmpty()) { pCurrent } else { interpolations[interpolations.size - 1] }
            let builder = diag.DiagnoseRefactor(
                DiagKindRefactor.lex_unterminated_interpolation,
                MakeRange(GetPos(interpolation), GetPos(pCurrent) + 1)
            )
            if (!allowNewline && currentChar != -1 && !stringStarts.isEmpty()) {
                builder.AddHint(GetPos(stringStarts[stringStarts.size - 1][0]))
            }
            success = false
        }
        return false
    }

    private func ScanInterpolationStringLiteralHoleBalancedTextString(): Bool {
        CJC_ASSERT(currentChar == Int64(b'\'') || currentChar == Int64(b'"'))
        if (getNextChar(0) == UInt8(currentChar) && getNextChar(1) == UInt8(currentChar)) {
            return ScanMultiLineString(pCurrent, needStringParts: false)[1]
        }
        return ScanStringOrJString(pCurrent, needStringParts: false)[1]
    }

    private func ScanInterpolationStringLiteralHoleBalancedText(endingChar: UInt8, allowNewline: Bool): Bool {
        while (true) {
            ReadUTF8Char()
            if (isQuote(currentChar)) {
                if (!ScanInterpolationStringLiteralHoleBalancedTextString()) {
                    return false
                }
            } else if (currentChar == Int64(b'#') && getNextChar(0) == b'#') {
                if (!ScanMultiLineRawString(pCurrent)[1]) {
                    return false
                }
            } else if (currentChar == Int64(b'{')) {
                if (!ScanInterpolationStringLiteralHoleBalancedText(b'}', allowNewline)) {
                    return false
                }
            } else if (currentChar == Int64(endingChar)) {
                return true
            } else if (currentChar == -1 || IsCurrentCharLineTerminator()) {
                if (!ProcessInterpolationStringLiteralLineBreak(allowNewline)) {
                    return false
                }
            } else if (currentChar == Int64(b'/')) {
                if (!ScanInterpolationStringLiteralHoleComment(allowNewline)) {
                    return false
                }
            }
        }
        return true
    }

    private func ProcessStringInterpolation(
        pStart: Int64,
        beginPos: Position,
        stringParts: ArrayList<StringPart>,
        allowNewLine: Bool
    ): (Int64, Int64) {
        var begin = pStart
        var localBeginPos = beginPos
        let interpolationAtBegin = allowNewLine && GetPos(pCurrent).column == 1
        if (begin != pCurrent || interpolationAtBegin) {
            stringParts.add(StringPart(StringPartKind.STR, input[begin..pCurrent], localBeginPos, GetPos(pCurrent)))
            begin = pCurrent
            localBeginPos = GetPos(begin)
        }
        let closeBrace = ScanInterpolationString(allowNewLine)
        if (closeBrace) {
            stringParts.add(StringPart(StringPartKind.EXPR, input[begin..pCurrent + 1], localBeginPos, GetPos(pCurrent + 1)))
            begin = pCurrent + 1
        }
        return (begin, if (closeBrace) { 1 } else { 0 })
    }

    private func ScanMultiLineString(pStart: Int64, needStringParts!: Bool = true): (Token, Bool) {
        var res = true
        let stringParts = ArrayList<StringPart>()
        stringStarts.add((pCurrent, true))
        let quoteChar = currentChar
        ReadUTF8Char()
        ReadUTF8Char()
        var beginOffset: Int64 = 3
        let terminatorLength = Int64(GetLineTerminatorLength(bytes, pNext))
        if (terminatorLength > 0) {
            beginOffset += terminatorLength
        } else if (success) {
            let builder = diag.DiagnoseRefactor(DiagKindRefactor.lex_multiline_string_start_from_newline, GetPos(pNext))
            builder.AddHint(MakeRange(GetPos(pStart), GetPos(pNext)))
            success = false
        }
        var begin = pStart + beginOffset
        var beginPos = GetPos(begin)
        while (true) {
            ReadUTF8Char()
            if (currentChar == Int64(b'\\')) {
                ProcessEscape(pStart, true, false)
            } else if (currentChar == quoteChar && getNextChar(0) == UInt8(quoteChar) && getNextChar(1) == UInt8(quoteChar)) {
                stringParts.add(StringPart(StringPartKind.STR, input[begin..pCurrent], beginPos, GetPos(pCurrent)))
                ReadUTF8Char()
                ReadUTF8Char()
                break
            } else if (currentChar == -1) {
                stringStarts.remove(at: stringStarts.size - 1)
                return (ProcessIllegalToken(needStringParts, true, pStart), false)
            } else if (currentChar == Int64(b'$') && getNextChar(0) == b'{') {
                let processed = ProcessStringInterpolation(begin, beginPos, stringParts, true)
                begin = processed[0]
                beginPos = GetPos(begin)
                res = processed[1] == 1
            }
        }
        var ret = Token(TokenKind.MULTILINE_STRING, input[pStart + beginOffset..pCurrent - 2], pos, GetPos(pNext))
        ret.isSingleQuote = quoteChar == Int64(b'\'')
        if (needStringParts) {
            stringPartsMap.add(ret, stringParts)
        }
        stringStarts.remove(at: stringStarts.size - 1)
        return (ret, res)
    }

    private func ConsumeNChar(n: UInt32): Unit {
        var count: UInt32 = 0u32
        while (count < n) {
            ReadUTF8Char()
            count++
        }
    }

    private func ScanMultiLineRawString(pStart: Int64): (Token, Bool) {
        var delimiterNum: UInt32 = 0u32
        while (currentChar == Int64(b'#')) {
            delimiterNum++
            ReadUTF8Char()
        }
        if (currentChar != Int64(b'"') && currentChar != Int64(b'\'')) {
            if (IsQuoteContext()) {
                pCurrent = pStart
                pNext = pStart + 1
                return (Token(TokenKind.HASH, "#", GetPos(pStart), GetPos(pNext)), false)
            }
            if (success) {
                let builder = diag.DiagnoseRefactor(
                    DiagKindRefactor.lex_expected_quote_in_raw_string, GetPos(pCurrent),
                    arguments: [ConvertCurrentChar()]
                )
                builder.AddHint(MakeRange(GetPos(pStart), GetPos(pCurrent)))
                success = false
            }
            return (Token(TokenKind.MULTILINE_RAW_STRING, "", pos, GetPos(pCurrent)), false)
        }
        let quoteChar = currentChar
        while (true) {
            ReadUTF8Char()
            if (currentChar == quoteChar && getNextChar(0) == b'#') {
                var tmp = pNext
                var count = delimiterNum
                while (tmp < bytes.size && bytes[tmp] == b'#' && count > 0u32) {
                    count--
                    tmp++
                }
                if (count == 0u32) {
                    ConsumeNChar(delimiterNum)
                    break
                }
            } else if (currentChar == -1) {
                if (success) {
                    if (IsQuoteContext()) {
                        pCurrent = pStart
                        pNext = pStart + 1
                        return (Token(TokenKind.HASH, "#", GetPos(pStart), GetPos(pNext)), false)
                    }
                    DiagUnterminatedRawString(pStart)
                    success = false
                }
                return (Token(TokenKind.MULTILINE_RAW_STRING, "", pos, GetPos(pNext)), false)
            }
        }
        var tok = Token(
            TokenKind.MULTILINE_RAW_STRING,
            input[pStart + Int64(delimiterNum) + 1..pCurrent - Int64(delimiterNum)],
            pos,
            GetPos(pNext)
        )
        tok.delimiterNum = delimiterNum
        tok.isSingleQuote = quoteChar == Int64(b'\'')
        return (tok, false)
    }

    private func ScanMultiLineComment(pStart: Int64, allowNewLine: Bool): (Token, Bool) {
        var level: Int64 = 1
        while (currentChar != -1 && level > 0) {
            ReadUTF8Char()
            if (IsCurrentCharLineTerminator() && success && !allowNewLine) {
                DiagUnterminatedInterpolation()
                success = false
                break
            }
            if (currentChar == Int64(b'*') && getNextChar(0) == b'/') {
                level--
                ReadUTF8Char()
            } else if (currentChar == Int64(b'/') && getNextChar(0) == b'*') {
                level++
                ReadUTF8Char()
            }
        }
        if (level > 0 && success) {
            lexDiagnose(diag, DiagKindRefactor.lex_unterminated_block_comment, MakeRange(GetPos(pStart), GetPos(pCurrent)))
            success = false
            return (Token(TokenKind.COMMENT, input[pStart..pNext], pos, GetPos(pNext)), false)
        }
        return (Token(TokenKind.COMMENT, input[pStart..pNext], pos, GetPos(pNext)), true)
    }

    private func ScanComment(pStart: Int64, allowNewLine!: Bool = true): (Token, Bool) {
        ReadUTF8Char()
        if (currentChar == Int64(b'*')) {
            return ScanMultiLineComment(pStart, allowNewLine)
        }
        while (currentChar != -1 && !IsCurrentCharLineTerminator()) {
            ReadUTF8Char()
        }
        if (IsCurrentCharLineTerminator()) {
            Back()
        }
        return (Token(TokenKind.COMMENT, input[pStart..pNext], pos, GetPos(pNext)), true)
    }

    private func ScanCharDiagUnterminated(pStart: Int64): Unit {
        if (success) {
            lexDiagnose(diag, DiagKindRefactor.lex_unterminated_char_literal, MakeRange(GetPos(pStart), GetPos(pCurrent) + 1))
            success = false
        }
    }

    private func DiagCharactersOverflow(pStart: Int64): Unit {
        let range = MakeRange(GetPos(pStart), GetPos(pCurrent + 1))
        let builder = diag.DiagnoseRefactor(DiagKindRefactor.lex_characters_overflow, range)
        let innerBegin = pStart + 2
        let inner = if (innerBegin <= pCurrent) { input[innerBegin..pCurrent] } else { "" }
        let help = DiagHelp("if you intended to write a string literal, use '\"'")
        help.AddSubstitution(range, "\"" + inner + "\"")
        builder.AddHelp(help)
    }

    private func ProcessIllegalCharValue(pStart: Int64, beginOffset: Int64): (Token, Bool) {
        if (currentChar == Int64(b'\'')) {
            if (success) {
                lexDiagnose(diag, DiagKindRefactor.lex_expected_character_in_char_literal, MakeRange(GetPos(pStart), GetPos(pCurrent + 1)))
                success = false
            }
            return (Token(TokenKind.RUNE_LITERAL, input[pStart + beginOffset..pCurrent], pos, GetPos(pCurrent)), true)
        }
        ScanCharDiagUnterminated(pStart)
        return (Token(TokenKind.RUNE_LITERAL, input[pStart + beginOffset..pCurrent], pos, GetPos(pCurrent)), false)
    }

    private func ProcessIllegalRightQuotation(pStart: Int64, quoteChar: Int64): Bool {
        while (currentChar != quoteChar && !IsCurrentCharLineTerminator() && currentChar != -1) {
            ReadUTF8Char()
        }
        if (currentChar != quoteChar) {
            ScanCharDiagUnterminated(pStart)
            return false
        }
        if (success) {
            DiagCharactersOverflow(pStart)
            success = false
        }
        return true
    }

    private func ScanChar(pStart: Int64, isByteLiteral!: Bool = false): (Token, Bool) {
        ReadUTF8Char()
        let quoteChar = currentChar
        let beginOffset: Int64 = 2
        ReadUTF8Char()
        if (currentChar == quoteChar || IsCurrentCharLineTerminator()) {
            return ProcessIllegalCharValue(pStart, beginOffset)
        }
        if (currentChar == Int64(b'\\')) {
            ProcessEscape(pStart, false, isByteLiteral)
        }
        ReadUTF8Char()
        var ok = true
        if (currentChar != quoteChar) {
            ok = ProcessIllegalRightQuotation(pStart, quoteChar)
        }
        var tok = Token(TokenKind.RUNE_LITERAL, input[pStart + beginOffset..pCurrent], pos, GetPos(pNext))
        tok.isSingleQuote = quoteChar == Int64(b'\'')
        return (tok, ok)
    }

    private func DiagUnrecognizedCharInByte(c: Int64, str: String, pStart: Int64, range: (Position, Position)): Unit {
        let builder = diag.DiagnoseRefactor(
            DiagKindRefactor.lex_unrecognized_char_in_binary_string,
            MakeRange(range[0], range[1]), arguments: [ConvertChar(c), str]
        )
        let hintPos = GetPos(pStart)
        builder.AddHint(MakeRange(hintPos, hintPos + 2), arguments: [str])
        builder.AddNote("character in " + str + " must be ASCII")
    }

    private func ScanByteUInt8(pStart: Int64): Token {
        let intByteGapLen: Int64 = 3
        var token = ScanChar(pStart, isByteLiteral: true)[0]
        if (let Some(position) <- token.Value().indexOf("\\u")) {
            let leftCurl = token.Value().indexOf("{", position)
            let rightCurl = token.Value().indexOf("}", position)
            if (let Some(lCurl) <- leftCurl) {
                if (let Some(rCurl) <- rightCurl) {
                    if (rCurl - lCurl > intByteGapLen && success) {
                        lexDiagnose(
                            diag, DiagKindRefactor.lex_too_many_digits, GetPos(pStart + intByteGapLen), token.Value()
                        )
                        success = false
                    }
                }
            }
        }
        let codepoints = UTF8ToChar32(token.Value())
        if (!codepoints.isEmpty() && codepoints[0] > UInt32(ASCII_BASE) && success) {
            DiagUnrecognizedCharInByte(
                Int64(codepoints[0]), "character byte literal", pStart, (GetPos(pStart + 2), GetPos(pCurrent))
            )
            success = false
        }
        token.SetValue("b'" + token.Value() + "'")
        token.kind = TokenKind.RUNE_BYTE_LITERAL
        return token
    }

    private func ScanSingleOrMultiLineString(pStart: Int64): Token {
        success = true
        CJC_ASSERT(currentChar == Int64(b'\'') || currentChar == Int64(b'"'))
        if (getNextChar(0) == UInt8(currentChar) && getNextChar(1) == UInt8(currentChar)) {
            return ScanMultiLineString(pStart)[0]
        }
        return ScanStringOrJString(pStart)[0]
    }

    private func IsCharOrString(): Bool {
        return (currentChar == Int64(b'b') && getNextChar(0) == b'\'') ||
            (currentChar == Int64(b'r') && (getNextChar(0) == b'\'' || getNextChar(0) == b'"')) ||
            currentChar == Int64(b'#') || currentChar == Int64(b'\'') || currentChar == Int64(b'"')
    }

    private func ScanCharOrString(pStart: Int64): Token {
        if (currentChar == Int64(b'b') && getNextChar(0) == b'\'') {
            return ScanByteUInt8(pStart)
        }
        if (currentChar == Int64(b'r') && (getNextChar(0) == b'\'' || getNextChar(0) == b'"')) {
            return ScanChar(pStart)[0]
        }
        if (currentChar == Int64(b'#')) {
            return ScanMultiLineRawString(pStart)[0]
        }
        if (currentChar == Int64(b'\'') || currentChar == Int64(b'"')) {
            return ScanSingleOrMultiLineString(pStart)
        }
        return ScanSymbol(pStart)
    }

    private func ScanSymbolPlus(): Unit {
        ReadUTF8Char()
        if (currentChar == Int64(b'+')) {
            return
        }
        if (currentChar == Int64(b'&')) {
            ReadUTF8Char()
            if (currentChar == Int64(b'=')) {
                return
            }
        } else if (currentChar == Int64(b'=')) {
            return
        }
        Back()
    }

    private func ScanSymbolHyphen(): Unit {
        ReadUTF8Char()
        if (currentChar == Int64(b'-')) {
            return
        }
        if (currentChar == Int64(b'=')) {
            return
        }
        if (currentChar == Int64(b'&')) {
            ReadUTF8Char()
            if (currentChar == Int64(b'=')) {
                return
            }
        } else if (currentChar == Int64(b'>')) {
            return
        }
        Back()
    }

    private func ScanSymbolAsterisk(): Unit {
        ReadUTF8Char()
        if (currentChar == Int64(b'*')) {
            ReadUTF8Char()
            if (currentChar == Int64(b'&')) {
                ReadUTF8Char()
                if (currentChar == Int64(b'=')) {
                    return
                }
            } else if (currentChar == Int64(b'=')) {
                return
            }
        } else if (currentChar == Int64(b'=')) {
            return
        } else if (currentChar == Int64(b'&')) {
            ReadUTF8Char()
            if (currentChar == Int64(b'=')) {
                return
            }
        }
        Back()
    }

    private func ScanSymbolAmpersand(): Unit {
        ReadUTF8Char()
        if (currentChar == Int64(b'&')) {
            ReadUTF8Char()
            if (currentChar == Int64(b'=')) {
                return
            }
        } else if (currentChar == Int64(b'=')) {
            return
        }
        Back()
    }

    private func ScanSymbolExclamation(): Unit {
        if (getNextChar(0) == b'i' && getNextChar(1) == b'n' &&
            (getNextChar(2) == b' ' || getNextChar(2) == b'\r' || getNextChar(2) == b'\n')) {
            ReadUTF8Char()
            ReadUTF8Char()
            return
        }
        ReadUTF8Char()
        if (currentChar == Int64(b'=')) {
            return
        }
        Back()
    }

    private func ScanSymbolLessThan(): Unit {
        ReadUTF8Char()
        if (currentChar == Int64(b'<')) {
            ReadUTF8Char()
            if (currentChar == Int64(b'=')) {
                return
            }
        } else if (currentChar == Int64(b'=')) {
            return
        } else if (currentChar == Int64(b':')) {
            return
        } else if (currentChar == Int64(b'-')) {
            return
        }
        Back()
    }

    private func ScanSymbolGreaterThan(): Unit {
        if (splitAmbiguousToken) {
            return
        }
        ReadUTF8Char()
        if (currentChar == Int64(b'>')) {
            ReadUTF8Char()
            if (currentChar == Int64(b'=')) {
                return
            }
        } else if (currentChar == Int64(b'=')) {
            return
        }
        Back()
    }

    private func ScanSymbolAt(): Unit {
        ReadUTF8Char()
        if (currentChar == Int64(b'!')) {
            return
        }
        Back()
    }

    private func ScanSymbolEqual(): Unit {
        ReadUTF8Char()
        if (currentChar == Int64(b'=')) {
            return
        }
        if (currentChar == Int64(b'>')) {
            return
        }
        Back()
    }

    private func ScanSymbolPercentSign(): Unit {
        ReadUTF8Char()
        if (currentChar == Int64(b'=')) {
            return
        }
        Back()
    }

    private func ScanSymbolVerticalBar(): Unit {
        ReadUTF8Char()
        if (currentChar == Int64(b'|')) {
            ReadUTF8Char()
            if (currentChar == Int64(b'=')) {
                return
            }
        } else if (currentChar == Int64(b'=')) {
            return
        } else if (currentChar == Int64(b'>')) {
            return
        }
        Back()
    }

    private func ScanSymbolTilde(): Unit {
        ReadUTF8Char()
        if (currentChar != Int64(b'>')) {
            Back()
        }
    }

    private func ScanSymbolCaret(): Unit {
        if (getNextChar(0) == b'=') {
            ReadUTF8Char()
        }
    }

    private func ScanSymbolQuest(): Unit {
        if (splitAmbiguousToken) {
            return
        }
        if (getNextChar(0) == b'?') {
            ReadUTF8Char()
        }
    }

    private func ScanSymbolColon(): Unit {
        ReadUTF8Char()
        if (currentChar != Int64(b':')) {
            Back()
        }
    }

    private func scanSimpleSymbolLiteral(): String {
        let start = pCurrent
        let first = currentByte()
        if (first == b'~') {
            ScanSymbolTilde()
        } else if (first == b'+') {
            ScanSymbolPlus()
        } else if (first == b'-') {
            ScanSymbolHyphen()
        } else if (first == b'*') {
            ScanSymbolAsterisk()
        } else if (first == b'&') {
            ScanSymbolAmpersand()
        } else if (first == b'^') {
            ScanSymbolCaret()
        } else if (first == b'!') {
            ScanSymbolExclamation()
        } else if (first == b'<') {
            ScanSymbolLessThan()
        } else if (first == b'>') {
            ScanSymbolGreaterThan()
        } else if (first == b'=') {
            ScanSymbolEqual()
        } else if (first == b'%') {
            ScanSymbolPercentSign()
        } else if (first == b'|') {
            ScanSymbolVerticalBar()
        } else if (first == b'?') {
            ScanSymbolQuest()
        } else if (first == b'@') {
            ScanSymbolAt()
        } else if (first == b':') {
            ScanSymbolColon()
        }
        return input[start..pNext]
    }

    private func GetSymbolToken(pStart: Int64): Token {
        let literal = input[pStart..pNext]
        let kind = LookupKeyword(literal)
        if (kind == TokenKind.IDENTIFIER) {
            if (success) {
                DiagUnknownStartOfToken(GetPos(pStart))
                success = false
            }
            return Token(TokenKind.ILLEGAL, literal, pos, GetPos(pNext))
        }
        return Token(kind, literal, pos, GetPos(pNext))
    }

    private func DiagUnknownStartOfToken(curPos: Position): Unit {
        let arg = ConvertCurrentChar()
        let builder = diag.DiagnoseRefactor(DiagKindRefactor.lex_unknown_start_of_token, curPos, arguments: [arg])
        builder.AddMainHintArguments([arg])
    }

    private func DiagUnexpectedDollarIdentifier(t: Token): Unit {
        let foundWildcard = t.kind == TokenKind.WILDCARD
        let foundMsg = (if (foundWildcard) { "symbol '" } else { "keyword '" }) + t.Value() + "'"
        let builder = diag.DiagnoseRefactor(
            DiagKindRefactor.lex_expected_identifier_after_dollar, MakeRange(t.Begin(), t.End()),
            arguments: [foundMsg]
        )
        if (foundWildcard) {
            builder.diagnostic.mainHint.str = "expected a Unicode XID_Continue after underscore"
            return
        }
        let help = DiagHelp("you could escape keyword as identifier using '`'")
        help.AddSubstitution(MakeRange(t.Begin(), t.End()), "`" + t.Value() + "`")
        builder.AddHelp(help)
    }

    private func ScanSymbol(pStart: Int64): Token {
        if (currentChar == Int64(b'$')) {
            ReadUTF8Char()
            if (isCJXIDStart(currentChar)) {
                let tok = ScanIdentifierOrKeyword(Token(TokenKind.IDENTIFIER), pStart + 1)
                if (tok.kind != TokenKind.IDENTIFIER) {
                    DiagUnexpectedDollarIdentifier(tok)
                }
                return Token(TokenKind.DOLLAR_IDENTIFIER, "$" + tok.Value(), pos, GetPos(pNext))
            }
            if (currentChar == Int64(b'`')) {
                let tok = ScanBackquotedIdentifier(pStart + 1)
                return Token(TokenKind.DOLLAR_IDENTIFIER, "$" + tok.Value(), pos, GetPos(pNext))
            }
            Back()
        } else {
            scanSimpleSymbolLiteral()
        }
        return GetSymbolToken(pStart)
    }

    private func ScanFromTokens(): Token {
        if (curToken >= tokens.size) {
            return Token(TokenKind.END, "", pos, pos)
        }
        if (splitAmbiguousToken) {
            var currentToken = tokens[curToken]
            if (currentToken.kind == TokenKind.COALESCING) {
                let curPos = currentToken.Begin()
                let endPos = currentToken.End()
                currentToken.kind = TokenKind.QUEST
                currentToken.SetValuePos("?", curPos + 1, endPos + 1)
                tokens[curToken] = currentToken
                return Token(TokenKind.QUEST, "?", curPos, endPos)
            }
            if (currentToken.kind == TokenKind.RSHIFT_ASSIGN) {
                let curPos = currentToken.Begin()
                let endPos = currentToken.End()
                currentToken.kind = TokenKind.GE
                currentToken.SetValuePos(">=", curPos + 1, endPos + 1)
                tokens[curToken] = currentToken
                return Token(TokenKind.GT, ">", curPos, endPos)
            }
            if (currentToken.kind == TokenKind.RSHIFT) {
                let curPos = currentToken.Begin()
                let endPos = currentToken.End()
                currentToken.kind = TokenKind.GT
                currentToken.SetValuePos(">", curPos + 1, endPos + 1)
                tokens[curToken] = currentToken
                return Token(TokenKind.GT, ">", curPos, endPos)
            }
            if (currentToken.kind == TokenKind.GE) {
                let curPos = currentToken.Begin()
                let endPos = currentToken.End()
                currentToken.kind = TokenKind.ASSIGN
                currentToken.SetValuePos("=", curPos + 1, endPos + 1)
                tokens[curToken] = currentToken
                return Token(TokenKind.GT, ">", curPos, endPos)
            }
        }
        let token = tokens[curToken]
        curToken++
        return token
    }

    private func ScanDivOrComment(pStart: Int64): Token {
        if (getNextChar(0) != b'/' && getNextChar(0) != b'*') {
            if (getNextChar(0) == b'=') {
                ReadUTF8Char()
                return Token(TokenKind.DIV_ASSIGN, "/=", pos, pos + 2)
            }
            return Token(TokenKind.DIV, "/", pos, pos + 1)
        }
        let token = ScanComment(pStart)[0]
        comments.add(token)
        return token
    }

    private func ScanBase(): Token {
        let pStart = pNext
        success = true
        ReadUTF8Char()
        pos = GetPos(pStart)
        if (currentChar == -1) {
            return Token(TokenKind.END, "", pos, pos)
        }
        if (currentChar == Int64(b'\n')) {
            return Token(TokenKind.NL, "\n", pos, pos + 1)
        }
        if (GetLineTerminatorLength(bytes, pCurrent) == WINDOWS_LINE_TERMINATOR_LENGTH) {
            return Token(TokenKind.NL, "\r\n", pos, pos + 1)
        }
        if (IsCharOrString()) {
            return ScanCharOrString(pStart)
        }
        if (currentChar == Int64(b'J') && getNextChar(0) == b'"') {
            return ScanStringOrJString(pStart, needStringParts: false, isJString: true)[0]
        }
        if (isCJXIDStart(currentChar)) {
            return ScanIdentifierOrKeyword(Token(TokenKind.IDENTIFIER), pStart)
        }
        if (currentChar == Int64(b'`')) {
            return ScanBackquotedIdentifier(pStart)
        }
        if (isDigit(currentChar) || currentChar == Int64(b'.')) {
            return ScanNumberOrDotPrefixSymbol(pStart)
        }
        if (currentChar == Int64(b'/')) {
            return ScanDivOrComment(pStart)
        }
        if (currentChar == Int64(b'\\') && isMacroEscape(getNextChar(0))) {
            return Token(TokenKind.ILLEGAL, "\\", pos, pos + 1)
        }
        return ScanSymbol(pStart)
    }

    private func Scan(): Token {
        var ret = Token(TokenKind.INTEGER_LITERAL, "", BEGIN_POSITION, BEGIN_POSITION)
        if (!enableScan) {
            ret = ScanFromTokens()
            if (enableCollectTokenStream) {
                tokenStream.add(ret)
            }
            return ret
        }
        if (bytes.size == 0) {
            ret = Token(TokenKind.END, "", posBase, posBase)
        } else if (pNext >= bytes.size) {
            ret = Token(TokenKind.END, "", GetPos(pNext), GetPos(pNext))
        } else {
            while (getNextChar(0) == b' ' || getNextChar(0) == b'\t' || getNextChar(0) == b'\f') {
                pNext++
            }
            ret = ScanBase()
        }
        if (enableCollectTokenStream) {
            tokenStream.add(ret)
        }
        return ret
    }
}
