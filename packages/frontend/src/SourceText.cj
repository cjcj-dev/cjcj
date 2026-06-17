package cangjie_compiler::frontend

import std.collection.*
import std.sort.*
import std.fs.File as FSFile
import std.fs.FileInfo
import std.fs.Directory as FSDirectory
import std.fs.canonicalize
import std.fs.exists
import std.fs.remove

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
    private let fileID: UInt64
    private let input: String
    private let bytes: Array<UInt8>
    private var idx: Int64 = 0
    private var line: Int64 = 1
    private var column: Int64 = 1

    public init(fileID: UInt64, input: String) {
        this.fileID = fileID
        this.input = input
        bytes = input.toArray()
    }

    public func Next(): FrontendToken {
        while (idx < bytes.size) {
            let current = bytes[idx]
            if (current == b' ' || current == b'\t' || current == b'\f') {
                advanceOne()
                continue
            }
            let newlineLen = GetLineTerminatorLength(bytes, idx)
            if (newlineLen != 0) {
                let begin = Position(fileID, line, column)
                let value = if (newlineLen == 2) { "\r\n" } else { "\n" }
                advanceNewline(newlineLen)
                return FrontendToken(FrontendTokenKind.NL, value, begin, Position(fileID, line, column))
            }
            break
        }
        if (idx >= bytes.size) {
            let endPos = Position(fileID, line, column)
            return FrontendToken(FrontendTokenKind.END, "", endPos, endPos)
        }
        let beginPos = Position(fileID, line, column)
        let start = idx
        if (isIdentifierStart(bytes[idx])) {
            advanceOne()
            while (idx < bytes.size && isIdentifierContinue(bytes[idx])) {
                advanceOne()
            }
            let value = input[start..idx]
            let kind = if (value == "true" || value == "false") {
                FrontendTokenKind.BOOL_LITERAL
            } else if (IsKeyword(value)) {
                FrontendTokenKind.KEYWORD
            } else {
                FrontendTokenKind.IDENTIFIER
            }
            return FrontendToken(kind, value, beginPos, Position(fileID, line, column))
        }
        if (isDigit(bytes[idx])) {
            advanceOne()
            var seenDot = false
            while (idx < bytes.size) {
                if (isDigit(bytes[idx]) || bytes[idx] == b'_') {
                    advanceOne()
                } else if (!seenDot && bytes[idx] == b'.' && idx + 1 < bytes.size && isDigit(bytes[idx + 1])) {
                    seenDot = true
                    advanceOne()
                } else {
                    break
                }
            }
            return FrontendToken(if (seenDot) { FrontendTokenKind.FLOAT_LITERAL } else { FrontendTokenKind.INTEGER_LITERAL },
                input[start..idx], beginPos, Position(fileID, line, column))
        }
        if (bytes[idx] == b'"') {
            scanStringLiteral()
            return FrontendToken(FrontendTokenKind.STRING_LITERAL, input[start..idx], beginPos, Position(fileID, line, column))
        }
        if (idx + 1 < bytes.size && bytes[idx] == b'/' && bytes[idx + 1] == b'/') {
            scanLineComment()
            return FrontendToken(FrontendTokenKind.COMMENT, input[start..idx], beginPos, Position(fileID, line, column))
        }
        if (idx + 1 < bytes.size && bytes[idx] == b'/' && bytes[idx + 1] == b'*') {
            scanBlockComment()
            return FrontendToken(FrontendTokenKind.COMMENT, input[start..idx], beginPos, Position(fileID, line, column))
        }
        scanOperator()
        return FrontendToken(FrontendTokenKind.OPERATOR, input[start..idx], beginPos, Position(fileID, line, column))
    }

    private func advanceOne(): Unit {
        idx++
        column++
    }

    private func advanceNewline(len: Int64): Unit {
        idx += len
        line++
        column = 1
    }

    private func scanStringLiteral(): Unit {
        advanceOne()
        var escaped = false
        while (idx < bytes.size) {
            let newlineLen = GetLineTerminatorLength(bytes, idx)
            if (newlineLen != 0) {
                advanceNewline(newlineLen)
                escaped = false
                continue
            }
            let current = bytes[idx]
            advanceOne()
            if (escaped) {
                escaped = false
            } else if (current == b'\\') {
                escaped = true
            } else if (current == b'"') {
                return
            }
        }
    }

    private func scanLineComment(): Unit {
        advanceOne()
        advanceOne()
        while (idx < bytes.size && GetLineTerminatorLength(bytes, idx) == 0) {
            advanceOne()
        }
    }

    private func scanBlockComment(): Unit {
        advanceOne()
        advanceOne()
        var depth: Int64 = 1
        while (idx < bytes.size && depth > 0) {
            let newlineLen = GetLineTerminatorLength(bytes, idx)
            if (newlineLen != 0) {
                advanceNewline(newlineLen)
            } else if (idx + 1 < bytes.size && bytes[idx] == b'/' && bytes[idx + 1] == b'*') {
                depth++
                advanceOne()
                advanceOne()
            } else if (idx + 1 < bytes.size && bytes[idx] == b'*' && bytes[idx + 1] == b'/') {
                depth--
                advanceOne()
                advanceOne()
            } else {
                advanceOne()
            }
        }
    }

    private func scanOperator(): Unit {
        let maxLen = if (idx + 3 <= bytes.size) { 3 } else { bytes.size - idx }
        if (maxLen >= 3) {
            let three = input[idx..idx + 3]
            if (three == "..." || three == ">>=" || three == "<<=") {
                advanceOne()
                advanceOne()
                advanceOne()
                return
            }
        }
        if (idx + 2 <= bytes.size) {
            let two = input[idx..idx + 2]
            if (two == "==" || two == "!=" || two == "<=" || two == ">=" || two == "&&" || two == "||" ||
                two == "->" || two == "=>" || two == "<-" || two == ".." || two == "**" || two == "+=" ||
                two == "-=" || two == "*=" || two == "/=" || two == "%=" || two == "++" || two == "--" ||
                two == "<<" || two == ">>" || two == "?.") {
                advanceOne()
                advanceOne()
                return
            }
        }
        advanceOne()
    }
}

public func ReadFileContent(path: String): (Bool, String, String) {
    if (!exists(path)) {
        return (false, "", "file not exist")
    }
    let absPath = GetAbsPath(path)
    if (let None <- absPath) {
        return (false, "", "file path illegal")
    }
    try {
        var bytes = FSFile.readFrom(absPath.getOrThrow())
        if (bytes.size >= 3 && bytes[0] == 0xefu8 && bytes[1] == 0xbbu8 && bytes[2] == 0xbfu8) {
            bytes = bytes[3..]
        }
        return (true, String.fromUtf8(bytes), "")
    } catch (e: Exception) {
        return (false, "", "open file failed")
    }
}

public func WriteFileContent(path: String, content: String): Bool {
    try {
        FSFile.writeTo(path, content.toArray())
        return true
    } catch (e: Exception) {
        return false
    }
}

public func FileExist(path: String): Bool {
    return exists(path)
}

public func IsDir(path: String): Bool {
    try {
        return FileInfo(path).isDirectory()
    } catch (e: Exception) {
        return false
    }
}

public func RemoveDirectoryRecursively(path: String): Bool {
    try {
        remove(path, recursive: true)
        return true
    } catch (e: Exception) {
        return false
    }
}

public func CreateDirs(path: String): Bool {
    if (path.isEmpty()) {
        return false
    }
    try {
        FSDirectory.create(path, recursive: true)
        return true
    } catch (e: Exception) {
        return IsDir(path)
    }
}

public func GetAllFilesUnderCurrentPath(path: String, extension: String, shouldSkipTestFiles!: Bool = true,
    shouldSkipRegularFiles!: Bool = false): ArrayList<String> {
    let out = ArrayList<String>()
    try {
        for (info in FSDirectory.readFrom(path)) {
            let name = info.name
            if (!info.isRegular() || name.isEmpty() || name[0] == b'.' || GetFileExtension(name) != extension) {
                continue
            }
            let isTest = name.endsWith("_test.cj")
            if (shouldSkipTestFiles && isTest) {
                continue
            }
            if (shouldSkipRegularFiles && !isTest) {
                continue
            }
            out.add(name)
        }
    } catch (e: Exception) {
        ()
    }
    sort(out, by: { left: String, right: String =>
        if (left < right) {
            Ordering.LT
        } else if (left > right) {
            Ordering.GT
        } else {
            Ordering.EQ
        }
    })
    return out
}

public func GetAbsPath(path: String): Option<String> {
    try {
        return Some(canonicalize(path).toString())
    } catch (e: Exception) {
        return None
    }
}

public func NormalizePath(input: String): String {
    let builder = StringBuilder()
    var previousIsSlash = false
    for (byte in input.toArray()) {
        let slash = byte == b'/' || byte == b'\\'
        if (slash) {
            if (!previousIsSlash) {
                builder.append("/")
            }
            previousIsSlash = true
        } else {
            builder.append(String.fromUtf8([byte]))
            previousIsSlash = false
        }
    }
    return builder.toString()
}

public func JoinPath(base: String, append: String): String {
    if (base.isEmpty()) {
        return NormalizePath(append)
    }
    if (base[base.size - 1] == b'/') {
        return NormalizePath(base + append)
    }
    return NormalizePath(base + "/" + append)
}

public func GetDirPath(path: String): String {
    let normalized = NormalizePath(path)
    if (let Some(pos) <- normalized.lastIndexOf("/")) {
        if (pos == 0) {
            return "/"
        }
        return normalized[0..pos]
    }
    return "."
}

public func GetFileName(path: String): String {
    let normalized = NormalizePath(path)
    if (let Some(pos) <- normalized.lastIndexOf("/")) {
        return normalized[pos + 1..]
    }
    return normalized
}

public func GetFileBase(path: String): String {
    let dotPos = path.lastIndexOf(".") ?? path.size
    return path[0..dotPos]
}

public func GetFileExtension(path: String): String {
    if (let Some(dotPos) <- path.lastIndexOf(".")) {
        if (dotPos + 1 < path.size) {
            return path[dotPos + 1..]
        }
    }
    return ""
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

private func isIdentifierStart(byte: UInt8): Bool {
    return (byte >= b'a' && byte <= b'z') || (byte >= b'A' && byte <= b'Z') || byte == b'_'
}

private func isIdentifierContinue(byte: UInt8): Bool {
    return isIdentifierStart(byte) || isDigit(byte)
}

private func isDigit(byte: UInt8): Bool {
    return byte >= b'0' && byte <= b'9'
}

public func IsKeyword(value: String): Bool {
    return value == "package" || value == "import" || value == "from" || value == "as" ||
        value == "macro" || value == "public" || value == "protected" || value == "internal" ||
        value == "private" || value == "func" || value == "main" || value == "var" ||
        value == "let" || value == "const" || value == "class" || value == "interface" ||
        value == "struct" || value == "enum" || value == "extend" || value == "type" ||
        value == "prop" || value == "init" || value == "where" || value == "if" ||
        value == "else" || value == "match" || value == "try" || value == "catch" ||
        value == "finally" || value == "for" || value == "while" || value == "do" ||
        value == "return" || value == "throw" || value == "break" || value == "continue"
}

public func Tokenize(fileID: UInt64, input: String): ArrayList<FrontendToken> {
    let lexer = FrontendLexer(fileID, input)
    let out = ArrayList<FrontendToken>()
    while (true) {
        let tok = lexer.Next()
        out.add(tok)
        if (tok.kind == FrontendTokenKind.END) {
            break
        }
    }
    return out
}
