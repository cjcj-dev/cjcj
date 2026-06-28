package cangjie_compiler::frontend

import cangjie_compiler::basic.Token as BasicToken
import cangjie_compiler::lex.Lexer as CangjieLexer
import cangjie_compiler::lex.Token as CangjieToken
import cangjie_compiler::lex.TokenKind as CangjieTokenKind
import cangjie_compiler::lex.TokenKindLiteral
import cangjie_compiler::lex.TokenKindValue
import cangjie_compiler::utils.FileUtil
import std.collection.*

public func StableSourcePathHash(path: String): UInt64 {
    var hash = 0u64
    var index = 1u64
    for (byte in path.toArray()) {
        hash += UInt64(byte) * index
        index++
    }
    return hash
}

public class FrontendLexer {
    private let lexer: CangjieLexer

    public init(fileID: UInt64, input: String, diag: DiagnosticEngine, sm: SourceManager) {
        lexer = CangjieLexer(fileID, input, diag.AsBasicDiagnosticEngine(), sm)
    }

    public func Next(): FrontendToken {
        return AdaptLexToken(lexer.Next())
    }

    public func GetComments(): Array<BasicToken> {
        let out = ArrayList<BasicToken>()
        for (token in lexer.GetComments()) {
            out.add(BasicToken(token.Begin(), token.End(), kind: TokenKindValue(token.kind), value: token.Value()))
        }
        return out.toArray()
    }
}

private func AdaptLexToken(token: CangjieToken): FrontendToken {
    let value = LexTokenValue(token)
    return FrontendToken(LexTokenCategory(token.kind, value), value, token.Begin(), token.End(),
        rawKindName: TokenKindValue(token.kind))
}

private func LexTokenValue(token: CangjieToken): String {
    let value = token.Value()
    if (!value.isEmpty() || token.kind == CangjieTokenKind.END) {
        return value
    }
    return TokenKindLiteral(token.kind)
}

private func LexTokenCategory(kind: CangjieTokenKind, value: String): FrontendTokenKind {
    if (kind == CangjieTokenKind.IDENTIFIER || kind == CangjieTokenKind.PACKAGE_IDENTIFIER ||
        kind == CangjieTokenKind.DOLLAR_IDENTIFIER || kind == CangjieTokenKind.WILDCARD) {
        return FrontendTokenKind.IDENTIFIER
    }
    if (kind == CangjieTokenKind.INTEGER_LITERAL || kind == CangjieTokenKind.RUNE_BYTE_LITERAL) {
        return FrontendTokenKind.INTEGER_LITERAL
    }
    if (kind == CangjieTokenKind.FLOAT_LITERAL) {
        return FrontendTokenKind.FLOAT_LITERAL
    }
    if (kind == CangjieTokenKind.STRING_LITERAL || kind == CangjieTokenKind.JSTRING_LITERAL ||
        kind == CangjieTokenKind.MULTILINE_STRING || kind == CangjieTokenKind.MULTILINE_RAW_STRING ||
        kind == CangjieTokenKind.RUNE_LITERAL) {
        return FrontendTokenKind.STRING_LITERAL
    }
    if (kind == CangjieTokenKind.BOOL_LITERAL) {
        return FrontendTokenKind.BOOL_LITERAL
    }
    if (kind == CangjieTokenKind.COMMENT) {
        return FrontendTokenKind.COMMENT
    }
    if (kind == CangjieTokenKind.NL) {
        return FrontendTokenKind.NL
    }
    if (kind == CangjieTokenKind.END) {
        return FrontendTokenKind.END
    }
    return if (IsKeyword(value)) { FrontendTokenKind.KEYWORD } else { FrontendTokenKind.OPERATOR }
}

public func ReadFileContent(path: String): (Bool, String, String) {
    let failedReason = Box<String>("")
    let content = FileUtil.ReadFileContent(path, failedReason)
    if (let Some(text) <- content) {
        return (true, text, "")
    }
    return (false, "", failedReason.value)
}

public func WriteFileContent(path: String, content: String): Bool {
    return FileUtil.WriteToFile(path, content)
}

public func FileExist(path: String): Bool {
    return FileUtil.FileExist(path)
}

public func IsDir(path: String): Bool {
    return FileUtil.IsDir(path)
}

public func RemoveDirectoryRecursively(path: String): Bool {
    return FileUtil.RemoveDirectoryRecursively(path)
}

public func CreateDirs(path: String): Bool {
    return FileUtil.CreateDirs(path) == 0
}

public func GetAllFilesUnderCurrentPath(path: String, extension: String, shouldSkipTestFiles!: Bool = true,
    shouldSkipRegularFiles!: Bool = false): ArrayList<String> {
    let out = ArrayList<String>()
    for (fileName in FileUtil.GetAllFilesUnderCurrentPath(path, extension, shouldSkipTestFiles: shouldSkipTestFiles,
        shouldSkipRegularFiles: shouldSkipRegularFiles)) {
        out.add(fileName)
    }
    return out
}

public func GetAbsPath(path: String): Option<String> {
    return FileUtil.GetAbsPath(path)
}

public func NormalizePath(input: String): String {
    return FileUtil.Normalize(input, toUnix: true)
}

public func JoinPath(base: String, append: String): String {
    return FileUtil.JoinPath(base, append)
}

public func GetDirPath(path: String): String {
    return FileUtil.GetDirPath(path)
}

public func GetFileName(path: String): String {
    return FileUtil.GetFileName(path)
}

public func GetFileBase(path: String): String {
    return FileUtil.GetFileBase(path)
}

public func GetFileExtension(path: String): String {
    return FileUtil.GetFileExtension(path)
}

public func SplitLines(text: String): ArrayList<String> {
    let out = ArrayList<String>()
    let bytes = text.toArray()
    var start: Int64 = 0
    var idx: Int64 = 0
    while (idx < bytes.size) {
        let len = GetLineTerminatorLength(bytes, idx)
        if (len == 0) {
            idx++
            continue
        }
        out.add(text[start..idx])
        idx += len
        start = idx
    }
    out.add(text[start..])
    return out
}

public func GetLineTerminatorLength(bytes: Array<UInt8>, idx: Int64): Int64 {
    if (idx >= bytes.size) {
        return 0
    }
    if (bytes[idx] == b'\n') {
        return 1
    }
    if (bytes[idx] == b'\r') {
        if (idx + 1 < bytes.size && bytes[idx + 1] == b'\n') {
            return 2
        }
        return 1
    }
    return 0
}

public func IsKeyword(value: String): Bool {
    return value == "Int8" || value == "Int16" || value == "Int32" || value == "Int64" ||
        value == "IntNative" || value == "UInt8" || value == "UInt16" || value == "UInt32" ||
        value == "UInt64" || value == "UIntNative" || value == "Float16" || value == "Float32" ||
        value == "Float64" || value == "Rune" || value == "Bool" || value == "Nothing" ||
        value == "Unit" || value == "struct" || value == "enum" || value == "VArray" ||
        value == "This" || value == "package" || value == "import" || value == "class" ||
        value == "interface" || value == "func" || value == "macro" || value == "quote" ||
        value == "let" || value == "var" || value == "const" || value == "type" ||
        value == "init" || value == "this" || value == "super" || value == "if" ||
        value == "else" || value == "case" || value == "try" || value == "catch" ||
        value == "finally" || value == "for" || value == "do" || value == "while" ||
        value == "throw" || value == "return" || value == "continue" || value == "break" ||
        value == "in" || value == "!in" || value == "match" || value == "where" ||
        value == "extend" || value == "with" || value == "prop" || value == "static" ||
        value == "public" || value == "private" || value == "internal" || value == "protected" ||
        value == "override" || value == "redef" || value == "abstract" || value == "sealed" ||
        value == "open" || value == "foreign" || value == "inout" || value == "mut" ||
        value == "unsafe" || value == "operator" || value == "spawn" || value == "synchronized" ||
        value == "main" || value == "common" || value == "specific" || value == "perform" ||
        value == "resume" || value == "throwing" || value == "handle" || value == "features" ||
        value == "as" || value == "is"
}

public func Tokenize(fileID: UInt64, input: String, diag: DiagnosticEngine, sm: SourceManager,
    attachComment!: Bool = false): ArrayList<FrontendToken> {
    let lexer = FrontendLexer(fileID, input, diag, sm)
    let out = ArrayList<FrontendToken>()
    while (true) {
        let tok = lexer.Next()
        out.add(tok)
        if (tok.kind == FrontendTokenKind.END) {
            break
        }
    }
    if (attachComment) {
        let commentsMap = HashMap<UInt64, Array<BasicToken>>()
        commentsMap.add(fileID, lexer.GetComments())
        sm.AddComments(commentsMap)
    }
    return out
}
