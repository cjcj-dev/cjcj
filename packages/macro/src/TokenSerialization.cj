package cjcj::macro_pkg

import cjcj::basic.Errorln
import std.collection.*

private func appendUInt16(out: ArrayList<UInt8>, value: UInt16): Unit {
    out.add(UInt8(UInt64(value) & 0xff))
    out.add(UInt8((UInt64(value) >> 8) & 0xff))
}

private func appendUInt32(out: ArrayList<UInt8>, value: UInt32): Unit {
    out.add(UInt8(UInt64(value) & 0xff))
    out.add(UInt8((UInt64(value) >> 8) & 0xff))
    out.add(UInt8((UInt64(value) >> 16) & 0xff))
    out.add(UInt8((UInt64(value) >> 24) & 0xff))
}

@OverflowWrapping
private func appendInt32(out: ArrayList<UInt8>, value: Int64): Unit {
    appendUInt32(out, UInt32(value))
}

private func readUInt16(bytes: ArrayList<UInt8>, cursor: Box<Int64>): UInt16 {
    let raw = UInt16(bytes[cursor.value]) | (UInt16(bytes[cursor.value + 1]) << 8)
    cursor.value += 2
    return raw
}

private func readUInt32(bytes: ArrayList<UInt8>, cursor: Box<Int64>): UInt32 {
    let b0 = UInt32(bytes[cursor.value])
    let b1 = UInt32(bytes[cursor.value + 1]) << 8
    let b2 = UInt32(bytes[cursor.value + 2]) << 16
    let b3 = UInt32(bytes[cursor.value + 3]) << 24
    cursor.value += 4
    return b0 | b1 | b2 | b3
}

private func readNativeByte(ptr: CPointer<UInt8>, cursor: Box<Int64>): UInt8 {
    let value = unsafe { (ptr + cursor.value).read() }
    cursor.value++
    return value
}

private func readNativeUInt16(ptr: CPointer<UInt8>, cursor: Box<Int64>): UInt16 {
    let b0 = UInt16(readNativeByte(ptr, cursor))
    let b1 = UInt16(readNativeByte(ptr, cursor)) << 8
    return b0 | b1
}

private func readNativeUInt32(ptr: CPointer<UInt8>, cursor: Box<Int64>): UInt32 {
    let b0 = UInt32(readNativeByte(ptr, cursor))
    let b1 = UInt32(readNativeByte(ptr, cursor)) << 8
    let b2 = UInt32(readNativeByte(ptr, cursor)) << 16
    let b3 = UInt32(readNativeByte(ptr, cursor)) << 24
    return b0 | b1 | b2 | b3
}

@OverflowWrapping
private func readNativeInt32(ptr: CPointer<UInt8>, cursor: Box<Int64>): Int64 {
    return Int64(Int32(readNativeUInt32(ptr, cursor)))
}

private func readNativeString(ptr: CPointer<UInt8>, cursor: Box<Int64>, len: Int64): String {
    let value = ArrayList<UInt8>()
    var idx: Int64 = 0
    while (idx < len) {
        let byte = readNativeByte(ptr, cursor)
        if (byte == 0u8) {
            value.add(b'\\')
            value.add(b'0')
        } else {
            value.add(byte)
        }
        idx++
    }
    return String.fromUtf8(value.toArray())
}

@OverflowWrapping
private func readInt32(bytes: ArrayList<UInt8>, cursor: Box<Int64>): Int64 {
    return Int64(Int32(readUInt32(bytes, cursor)))
}

private func readString(bytes: ArrayList<UInt8>, cursor: Box<Int64>, len: Int64): String {
    let value = ArrayList<UInt8>()
    var idx: Int64 = 0
    while (idx < len) {
        let byte = bytes[cursor.value]
        if (byte == 0u8) {
            value.add(b'\\')
            value.add(b'0')
        } else {
            value.add(byte)
        }
        cursor.value++
        idx++
    }
    return String.fromUtf8(value.toArray())
}

private let ALL_TOKEN_KINDS: Array<TokenKind> = [
    TokenKind.DOT, TokenKind.COMMA, TokenKind.LPAREN, TokenKind.RPAREN, TokenKind.LSQUARE, TokenKind.RSQUARE,
    TokenKind.LCURL, TokenKind.RCURL, TokenKind.EXP, TokenKind.MUL, TokenKind.MOD, TokenKind.DIV, TokenKind.ADD,
    TokenKind.SUB, TokenKind.INCR, TokenKind.DECR, TokenKind.AND, TokenKind.OR, TokenKind.COALESCING,
    TokenKind.PIPELINE, TokenKind.COMPOSITION, TokenKind.NOT, TokenKind.BITAND, TokenKind.BITOR, TokenKind.BITXOR,
    TokenKind.BITNOT, TokenKind.LSHIFT, TokenKind.RSHIFT, TokenKind.COLON, TokenKind.SEMI, TokenKind.ASSIGN,
    TokenKind.ADD_ASSIGN, TokenKind.SUB_ASSIGN, TokenKind.MUL_ASSIGN, TokenKind.EXP_ASSIGN, TokenKind.DIV_ASSIGN,
    TokenKind.MOD_ASSIGN, TokenKind.AND_ASSIGN, TokenKind.OR_ASSIGN, TokenKind.BITAND_ASSIGN,
    TokenKind.BITOR_ASSIGN, TokenKind.BITXOR_ASSIGN, TokenKind.LSHIFT_ASSIGN, TokenKind.RSHIFT_ASSIGN,
    TokenKind.ARROW, TokenKind.BACKARROW, TokenKind.DOUBLE_ARROW, TokenKind.RANGEOP, TokenKind.CLOSEDRANGEOP,
    TokenKind.ELLIPSIS, TokenKind.HASH, TokenKind.AT, TokenKind.QUEST, TokenKind.LT, TokenKind.GT, TokenKind.LE,
    TokenKind.GE, TokenKind.IS, TokenKind.AS, TokenKind.NOTEQ, TokenKind.EQUAL, TokenKind.WILDCARD,
    TokenKind.INT8, TokenKind.INT16, TokenKind.INT32, TokenKind.INT64, TokenKind.INTNATIVE, TokenKind.UINT8,
    TokenKind.UINT16, TokenKind.UINT32, TokenKind.UINT64, TokenKind.UINTNATIVE, TokenKind.FLOAT16,
    TokenKind.FLOAT32, TokenKind.FLOAT64, TokenKind.RUNE, TokenKind.BOOLEAN, TokenKind.NOTHING, TokenKind.UNIT,
    TokenKind.STRUCT, TokenKind.ENUM, TokenKind.VARRAY, TokenKind.THISTYPE, TokenKind.PACKAGE, TokenKind.IMPORT,
    TokenKind.CLASS, TokenKind.INTERFACE, TokenKind.FUNC, TokenKind.MACRO, TokenKind.QUOTE, TokenKind.DOLLAR,
    TokenKind.LET, TokenKind.VAR, TokenKind.CONST, TokenKind.TYPE, TokenKind.INIT, TokenKind.THIS, TokenKind.SUPER,
    TokenKind.IF, TokenKind.ELSE, TokenKind.CASE, TokenKind.TRY, TokenKind.CATCH, TokenKind.FINALLY, TokenKind.FOR,
    TokenKind.DO, TokenKind.WHILE, TokenKind.THROW, TokenKind.RETURN, TokenKind.CONTINUE, TokenKind.BREAK,
    TokenKind.IN, TokenKind.NOT_IN, TokenKind.MATCH, TokenKind.WHERE, TokenKind.EXTEND, TokenKind.WITH,
    TokenKind.PROP, TokenKind.STATIC, TokenKind.PUBLIC, TokenKind.PRIVATE, TokenKind.INTERNAL, TokenKind.PROTECTED,
    TokenKind.OVERRIDE, TokenKind.REDEF, TokenKind.ABSTRACT, TokenKind.SEALED, TokenKind.OPEN, TokenKind.FOREIGN,
    TokenKind.INOUT, TokenKind.MUT, TokenKind.UNSAFE, TokenKind.OPERATOR, TokenKind.SPAWN, TokenKind.SYNCHRONIZED,
    TokenKind.UPPERBOUND, TokenKind.MAIN, TokenKind.IDENTIFIER, TokenKind.PACKAGE_IDENTIFIER,
    TokenKind.INTEGER_LITERAL, TokenKind.RUNE_BYTE_LITERAL, TokenKind.FLOAT_LITERAL, TokenKind.COMMENT, TokenKind.NL,
    TokenKind.END, TokenKind.SENTINEL, TokenKind.RUNE_LITERAL, TokenKind.STRING_LITERAL, TokenKind.JSTRING_LITERAL,
    TokenKind.MULTILINE_STRING, TokenKind.MULTILINE_RAW_STRING, TokenKind.BOOL_LITERAL, TokenKind.UNIT_LITERAL,
    TokenKind.DOLLAR_IDENTIFIER, TokenKind.ANNOTATION, TokenKind.AT_EXCL, TokenKind.COMMON, TokenKind.SPECIFIC,
    TokenKind.PERFORM, TokenKind.RESUME, TokenKind.THROWING, TokenKind.HANDLE, TokenKind.ILLEGAL,
    TokenKind.DOUBLE_COLON, TokenKind.FEATURES
]

private func tokenKindFromIndex(index: UInt16): TokenKind {
    let raw = Int64(index)
    for (kind in ALL_TOKEN_KINDS) {
        if (TokenKindIndex(kind) == raw) {
            return kind
        }
    }
    return TokenKind.ILLEGAL
}

public class TokenSerialization {
    public static func GetTokensBytes(tokens: ArrayList<Token>): ArrayList<UInt8> {
        let out = ArrayList<UInt8>()
        if (tokens.isEmpty()) {
            return out
        }
        appendUInt32(out, UInt32(tokens.size))
        for (token in tokens) {
            appendUInt16(out, UInt16(TokenKindIndex(token.kind)))
            let valueBytes = token.Value().toArray()
            appendUInt32(out, UInt32(valueBytes.size))
            for (byte in valueBytes) {
                out.add(byte)
            }
            let begin = token.Begin()
            appendUInt32(out, UInt32(begin.fileID))
            appendInt32(out, begin.line)
            var column = begin.column
            let escapes = GetEscapeTokenKinds()
            if (ContainsTokenKind(escapes, token.kind) && column + 1 + token.Value().size == token.End().column) {
                column++
            }
            appendInt32(out, column)
            appendUInt16(out, if (token.isSingleQuote) { 1u16 } else { 0u16 })
            if (token.kind == TokenKind.MULTILINE_RAW_STRING) {
                appendUInt16(out, UInt16(token.delimiterNum))
            }
        }
        return out
    }

    public static func GetTokensFromBytes(bytes: ArrayList<UInt8>): ArrayList<Token> {
        let out = ArrayList<Token>()
        let cursor = Box<Int64>(0)
        let count = readUInt32(bytes, cursor)
        var idx: UInt32 = 0u32
        while (idx < count) {
            let kind = tokenKindFromIndex(readUInt16(bytes, cursor))
            let strLen = Int64(readUInt32(bytes, cursor))
            let value = readString(bytes, cursor, strLen)
            let fileID = UInt64(readUInt32(bytes, cursor))
            let line = readInt32(bytes, cursor)
            let column = readInt32(bytes, cursor)
            let begin = Position(fileID, line, column)
            let isSingle = readUInt16(bytes, cursor)
            var delimiterNum: UInt32 = 1u32
            if (kind == TokenKind.MULTILINE_RAW_STRING) {
                delimiterNum = UInt32(readUInt16(bytes, cursor))
            }
            let end = if (begin == INVALID_POSITION) {
                INVALID_POSITION
            } else {
                begin + GetTokenLength(value.size, kind, delimiterNum)
            }
            var token = Token(kind, value, begin, end)
            token.delimiterNum = delimiterNum
            token.isSingleQuote = isSingle == 1u16
            out.add(token)
            idx++
        }
        return out
    }

    public static func GetTokensFromNativeBuffer(ptr: CPointer<UInt8>): ArrayList<Token> {
        let out = ArrayList<Token>()
        if (ptr.isNull()) {
            return out
        }
        let cursor = Box<Int64>(0)
        let count = readNativeUInt32(ptr, cursor)
        var idx: UInt32 = 0u32
        while (idx < count) {
            let kind = tokenKindFromIndex(readNativeUInt16(ptr, cursor))
            let strLen = Int64(readNativeUInt32(ptr, cursor))
            let value = readNativeString(ptr, cursor, strLen)
            let fileID = UInt64(readNativeUInt32(ptr, cursor))
            let line = readNativeInt32(ptr, cursor)
            let column = readNativeInt32(ptr, cursor)
            let isSingleQuote = readNativeUInt16(ptr, cursor) == 1u16
            var delimiterNum: UInt32 = 1u32
            if (kind == TokenKind.MULTILINE_RAW_STRING) {
                delimiterNum = UInt32(readNativeUInt16(ptr, cursor))
            }
            let begin = Position(fileID, line, column)
            let end = if (begin == INVALID_POSITION) {
                INVALID_POSITION
            } else {
                begin + GetTokenLength(value.size, kind, delimiterNum)
            }
            var token = Token(kind, value, begin, end)
            token.delimiterNum = delimiterNum
            token.isSingleQuote = isSingleQuote
            out.add(token)
            idx++
        }
        return out
    }

    public static func GetTokensBytesWithHead(tokens: ArrayList<Token>): CPointer<UInt8> {
        if (tokens.isEmpty()) {
            return CPointer<UInt8>()
        }
        let tokensBytes = GetTokensBytes(tokens)
        let bufferSize = tokensBytes.size + 4
        if (bufferSize == 0 || bufferSize > 4294967295) {
            Errorln("Memory Allocated Size is Not Valid.")
            return CPointer<UInt8>()
        }
        let rawPtr = LibC.malloc<UInt8>(count: bufferSize)
        if (rawPtr.isNull()) {
            Errorln("Memory Allocation Failed.")
            return rawPtr
        }
        let head = UInt32(bufferSize)
        unsafe {
            (rawPtr + 0).write(UInt8(UInt64(head) & 0xff))
            (rawPtr + 1).write(UInt8((UInt64(head) >> 8) & 0xff))
            (rawPtr + 2).write(UInt8((UInt64(head) >> 16) & 0xff))
            (rawPtr + 3).write(UInt8((UInt64(head) >> 24) & 0xff))
            var idx: Int64 = 0
            while (idx < tokensBytes.size) {
                (rawPtr + 4 + idx).write(tokensBytes[idx])
                idx++
            }
        }
        return rawPtr
    }
}
