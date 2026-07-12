package cjcj::mangle

import std.collection.*
import cjcj::ast.*
import cjcj::utils.Stoi

public let MANGLE_CANGJIE_PREFIX: String = "_C"
public let MANGLE_NESTED_PREFIX: String = "N"
public let MANGLE_SUFFIX: String = "E"
public let MANGLE_GLOBAL_VARIABLE_INIT_PREFIX: String = "GV"
public let MANGLE_GLOBAL_PACKAGE_INIT_PREFIX: String = "GP"
public let MANGLE_GLOBAL_FILE_INIT_PREFIX: String = "GF"
public let MANGLE_FUNC_PARA_INIT_PREFIX: String = "PI"
public let SPECIAL_NAME_FOR_INIT_FUNCTION: String = "ii"
public let SPECIAL_NAME_FOR_INIT_RESET_FUNCTION: String = "ir"
public let SPECIAL_NAME_FOR_INIT_LITERAL_FUNCTION: String = "il"
public let SPECIAL_NAME_FOR_IMPORTS_INIT_FUNCTION: String = "fi"
public let SPECIAL_NAME_FOR_LITERAL_IMPORTS_INIT_FUNCTION: String = "fl"
public let SPECIAL_NAME_FOR_INIT_FLAG_RESET_FUNCTION: String = "if"
public let SPECIAL_NAME_FOR_GET: String = "get"
public let SPECIAL_NAME_FOR_SET: String = "set"
public let MANGLE_CFUNC_PREFIX: String = "FC"
public let MANGLE_GENERAL_FUNC_PREFIX: String = "F0"
public let MANGLE_FILE_ID_PREFIX: String = "U"
public let MANGLE_TYPE_STRUCT_PREFIX: String = "R"
public let MANGLE_TYPE_CLASS_PREFIX: String = "C"
public let MANGLE_TYPE_ENUM_PREFIX: String = "N"
public let MANGLE_TYPE_ARRAY_PREFIX: String = "A"
public let MANGLE_FUNC_PARAM_TYPE_PREFIX: String = "H"
public let MANGLE_VOID_TY_SUFFIX: String = "v"
public let MANGLE_COUNT_PREFIX: String = "K"
public let MANGLE_LAMBDA_PREFIX: String = "L"
public let MANGLE_EXTEND_PREFIX: String = "X"
public let USER_MAIN_MANGLED_NAME: String = "user.main"
public let MANGLE_GENERIC_PREFIX: String = "I"
public let MANGLE_ANONYMOUS_VARIABLE_PREFIX: String = "0"
public let MANGLE_COMPRESSED_PREFIX: String = "Y"
public let MANGLE_POINTER_PREFIX: String = "P"
public let MANGLE_VARRAY_PREFIX: String = "V"
public let MANGLE_TUPLE_PREFIX: String = "T"
public let MANGLE_GENERIC_TYPE_PREFIX: String = "G"
public let MANGLE_AT_PREFIX: String = "@"
public let MANGLE_DOLLAR_PREFIX: String = "$"
public let MANGLE_WILDCARD_PREFIX: String = "_"
public let MANGLE_DOT_PREFIX: String = "."
public let MANGLE_LT_PREFIX: String = "<"
public let MANGLE_GT_PREFIX: String = ">"
public let MANGLE_LT_COLON_PREFIX: String = "<:"
public let MANGLE_PREFIX_LEN: Int64 = 2
public let MANGLE_CHAR_LEN: Int64 = 1
public let MANGLE_SPECIAL_NAME_LEN: Int64 = 2
public let MANGLE_PROP_LEN: Int64 = 3
public let FILE_HASH_LEN: Int64 = 13

public let MAIN_INVOKE: String = "$mainInvoke"
public let TEST_ENTRY_NAME: String = "$test.entry"
public let STATIC_INIT_FUNC: String = "<clinit>"
public let CORE_PACKAGE_NAME: String = "std.core"

public func StartsWith(value: String, prefix: String): Bool {
    return value.size >= prefix.size && value[0..prefix.size] == prefix
}

public func EndsWith(value: String, suffix: String): Bool {
    return value.size >= suffix.size && value[value.size - suffix.size..] == suffix
}

public func MangleName(str: String): String {
    return "${str.size}${str}"
}

public func ReplaceSubstring(str: String, from: String, to: String): String {
    var out = str
    var found = out.indexOf(from)
    while (let Some(pos) <- found) {
        out = out[0..pos] + to + out[pos + from.size..]
        found = out.indexOf(from)
    }
    return out
}

public func PrimitiveTypeMangle(kind: TypeKind): Option<String> {
    return match (kind) {
        case TypeKind.TYPE_NOTHING => "n"
        case TypeKind.TYPE_UNIT => "u"
        case TypeKind.TYPE_RUNE => "c"
        case TypeKind.TYPE_BOOLEAN => "b"
        case TypeKind.TYPE_FLOAT16 => "Dh"
        case TypeKind.TYPE_FLOAT32 => "f"
        case TypeKind.TYPE_FLOAT64 => "d"
        case TypeKind.TYPE_INT8 => "a"
        case TypeKind.TYPE_INT16 => "s"
        case TypeKind.TYPE_INT32 => "i"
        case TypeKind.TYPE_INT64 => "l"
        case TypeKind.TYPE_INT_NATIVE => "q"
        case TypeKind.TYPE_UINT8 => "h"
        case TypeKind.TYPE_UINT16 => "t"
        case TypeKind.TYPE_UINT32 => "j"
        case TypeKind.TYPE_UINT64 => "m"
        case TypeKind.TYPE_UINT_NATIVE => "r"
        case _ => None
    }
}

public func OperatorTypeMangle(name: String): Option<String> {
    return match (name) {
        case "[]" => "ix"
        case "!" => "nt"
        case "-" => "ng"
        case "**" => "pw"
        case "*" => "ml"
        case "/" => "dv"
        case "%" => "rm"
        case "+" => "pl"
        case "<<" => "ls"
        case ">>" => "rs"
        case "<" => "lt"
        case ">" => "gt"
        case "<=" => "le"
        case ">=" => "ge"
        case "==" => "eq"
        case "!=" => "ne"
        case "&" => "an"
        case "^" => "eo"
        case "|" => "or"
        case "()" => "cl"
        case _ => None
    }
}

public func IsOperatorMangleCode(code: String): Bool {
    return code == "ix" || code == "nt" || code == "ng" || code == "pw" || code == "ml" || code == "dv" ||
        code == "rm" || code == "pl" || code == "ls" || code == "rs" || code == "lt" || code == "gt" ||
        code == "le" || code == "ge" || code == "eq" || code == "ne" || code == "an" || code == "eo" ||
        code == "or" || code == "cl"
}

public func IsAutoBoxedBaseDecl(decl: MangleDecl): Bool {
    return decl.TestAttr(Attribute.NO_MANGLE) && decl.astKind == ASTKind.CLASS_DECL
}

public func IsAutoBoxedBaseDecl(decl: Decl): Bool {
    return IsAutoBoxedBaseDecl(ConvertAstDeclToMangle(decl))
}

public func MangleEnumElement(enumDeclMangledName: String, decl: MangleDecl): String {
    var elementClassName = enumDeclMangledName + MANGLE_DOLLAR_PREFIX + decl.identifier
    if (let Some(ty) <- decl.semaTy()) {
        if (ty.kind == TypeKind.TYPE_FUNC) {
            elementClassName += MANGLE_DOLLAR_PREFIX + "${ty.paramTys.size}"
        }
    }
    return elementClassName
}

public func MangleEnumElement(enumDeclMangledName: String, decl: Decl): String {
    return MangleEnumElement(enumDeclMangledName, ConvertAstDeclToMangle(decl))
}

public func GetMangledNameOfCompilerAddedClass(className: String): String {
    return MANGLE_NESTED_PREFIX + MangleName(className) + MANGLE_SUFFIX
}

public func ComputeMangledNameWithCustomIdentifier(decl: Decl, customIdentifier: String): String {
    let originalIdentifier = decl.identifier
    let originalMangledName = decl.mangledName
    decl.identifier = SrcIdentifier(customIdentifier)
    decl.mangledName = ""
    let mangledName = BaseMangler().Mangle(decl)
    decl.identifier = originalIdentifier
    decl.mangledName = originalMangledName
    return mangledName
}

public func ComputeMangledNameWithCustomIdentifier(decl: MangleDecl, customIdentifier: String): String {
    let originalIdentifier = decl.identifier
    let originalMangledName = decl.mangledName
    decl.identifier = customIdentifier
    decl.mangledName = ""
    let mangledName = BaseMangler().Mangle(decl)
    decl.identifier = originalIdentifier
    decl.mangledName = originalMangledName
    return mangledName
}

public func GetOptPkgName(pkgName: String): String {
    if (let Some(shortName) <- StdPackageMangle(pkgName)) {
        return shortName
    }
    return MangleName(pkgName)
}

public func DecimalToManglingNumber(decimal: String): String {
    let base62Chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    for (ch in decimal.toArray()) {
        if (!IsDigit(ch)) {
            return ""
        }
    }
    if (let Some(parsed) <- Stoi(decimal)) {
        var num = parsed - 1
        if (num < 0) {
            return MANGLE_WILDCARD_PREFIX
        }
        var base62 = if (num > 0) { "" } else { "0" }
        while (num > 0) {
            let idx = num % base62Chars.size
            base62 += base62Chars[idx..idx + 1]
            num /= base62Chars.size
        }
        return base62 + MANGLE_WILDCARD_PREFIX
    }
    return ""
}

public func IsDigit(ch: Byte): Bool {
    return ch >= b'0' && ch <= b'9'
}

public func IsAlpha(ch: Byte): Bool {
    return (ch >= b'a' && ch <= b'z') || (ch >= b'A' && ch <= b'Z')
}

public func IsAlnum(ch: Byte): Bool {
    return IsDigit(ch) || IsAlpha(ch)
}

public func IsPrimitivePrefix(ch: Byte): Bool {
    return ch == b'n' || ch == b'u' || ch == b'c' || ch == b'b' || ch == b'f' || ch == b'd' ||
        ch == b'a' || ch == b's' || ch == b'i' || ch == b'l' || ch == b'q' || ch == b'h' ||
        ch == b't' || ch == b'j' || ch == b'm' || ch == b'r' || ch == b'D' || ch == b'v'
}

public func MangleFilePrivate(decl: MangleDecl): String {
    if (let Some(file) <- decl.curFile) {
        let filenameLen = file.fileName.size
        let cjExtLen: Int64 = 3
        let maxLen: Int64 = 16
        if (filenameLen <= maxLen + cjExtLen) {
            let nameWithoutExt = if (filenameLen >= cjExtLen) {
                file.fileName[0..filenameLen - cjExtLen]
            } else {
                file.fileName
            }
            return MangleName(MANGLE_DOLLAR_PREFIX + nameWithoutExt)
        }
        return MangleName(ToHex(file.fileHash))
    }
    throw IllegalArgumentException("Private declaration has no current file.")
}

public func MangleFilePrivate(decl: Decl): String {
    return MangleFilePrivate(ConvertAstDeclToMangle(decl))
}

public func ToHex(value: UInt64): String {
    let hexChars = "0123456789ABCDEF"
    var current = value
    var out = ""
    if (current == 0u64) {
        out = "00"
    } else {
        while (current > 0u64) {
            let idx = Int64(current % 16u64)
            out = hexChars[idx..idx + 1] + out
            current /= 16u64
        }
        if (out.size < 2) {
            out = "0" + out
        }
    }
    return MANGLE_DOLLAR_PREFIX + out
}
