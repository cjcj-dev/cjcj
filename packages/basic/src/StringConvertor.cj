package cangjie_compiler::basic

import std.collection.*

private let UTF8_1_MAX: UInt32 = 0x7fu32
private let UTF8_2_MAX: UInt32 = 0x7ffu32
private let UTF8_3_MAX: UInt32 = 0xffffu32
private let UTF8_4_MAX: UInt32 = 0x1fffffu32
private let UTF8_5_MAX: UInt32 = 0x3ffffffu32
private let UTF8_6_MAX: UInt32 = 0x7fffffffu32

private let BYTE_2_FLAG: UInt32 = 0xc0u32
private let BYTE_3_FLAG: UInt32 = 0xe0u32
private let BYTE_4_FLAG: UInt32 = 0xf0u32
private let BYTE_5_FLAG: UInt32 = 0xf8u32
private let BYTE_6_FLAG: UInt32 = 0xfcu32
private let BYTE_X_FLAG: UInt32 = 0x80u32

private let LOW_1_BIT_MASK: UInt32 = 0x01u32
private let LOW_2_BIT_MASK: UInt32 = 0x03u32
private let LOW_3_BIT_MASK: UInt32 = 0x07u32
private let LOW_4_BIT_MASK: UInt32 = 0x0fu32
private let LOW_5_BIT_MASK: UInt32 = 0x1fu32
private let LOW_6_BIT_MASK: UInt32 = 0x3fu32

private func singleByteString(value: UInt8): String {
    return String.fromUtf8([value])
}

private func isHexDigit(value: UInt8): Bool {
    return (value >= b'0' && value <= b'9') || (value >= b'a' && value <= b'f') ||
        (value >= b'A' && value <= b'F')
}

private func hexValue(value: UInt8): UInt32 {
    if (value >= b'0' && value <= b'9') {
        return UInt32(value - b'0')
    }
    if (value >= b'a' && value <= b'f') {
        return UInt32(value - b'a') + 10
    }
    return UInt32(value - b'A') + 10
}

private func escapedByte(value: UInt8): Option<String> {
    return match (value) {
        case b'0' => Some(singleByteString(0u8))
        case b'\\' => Some("\\")
        case b'b' => Some("\b")
        case b'f' => Some("\f")
        case b'n' => Some("\n")
        case b'r' => Some("\r")
        case b't' => Some("\t")
        case b'v' => Some("\v")
        case b'\'' => Some("'")
        case b'"' => Some("\"")
        case b'?' => Some("?")
        case _ => None
    }
}

private func escapeForRecover(value: UInt8): Option<String> {
    return match (value) {
        case 0u8 => Some("\\0")
        case b'\b' => Some("\\b")
        case b'\f' => Some("\\f")
        case b'\n' => Some("\\n")
        case b'\r' => Some("\\r")
        case b'\t' => Some("\\t")
        case b'\v' => Some("\\v")
        case b'\\' => Some("\\\\")
        case b'"' => Some("\\\"")
        case b'\'' => Some("\\'")
        case _ => None
    }
}

private func escapeForJson(value: UInt8): Option<String> {
    return match (value) {
        case b'\b' => Some("\\b")
        case b'\f' => Some("\\f")
        case b'\n' => Some("\\n")
        case b'\r' => Some("\\r")
        case b'\t' => Some("\\t")
        case b'\\' => Some("\\\\")
        case b'"' => Some("\\\"")
        case _ => None
    }
}

public enum StrEncoding {
    | UTF8
    | GBK
    | UNKNOWN
}

private func StrEncodingIndex(encoding: StrEncoding): Int64 {
    return match (encoding) {
        case StrEncoding.UTF8 => 0
        case StrEncoding.GBK => 1
        case StrEncoding.UNKNOWN => 2
    }
}

extend StrEncoding <: Equatable<StrEncoding> {
    public operator func ==(right: StrEncoding): Bool {
        return StrEncodingIndex(this) == StrEncodingIndex(right)
    }

    public operator func !=(right: StrEncoding): Bool {
        return !(this == right)
    }
}

private func preNum(byte: UInt8): Int64 {
    var mask: UInt8 = 0x80u8
    var num: Int64 = 0
    for (_ in 0..8) {
        if ((byte & mask) == mask) {
            mask = mask >> 1
            num++
        } else {
            break
        }
    }
    return num
}

private func isAscii(data: Array<UInt8>): Bool {
    for (byte in data) {
        if (byte > 0x7fu8) {
            return false
        }
    }
    return true
}

private func isGBK(data: Array<UInt8>): Bool {
    var idx: Int64 = 0
    while (idx < data.size) {
        let first = data[idx]
        if (first <= 0x7fu8) {
            idx++
            continue
        }
        if (idx + 1 >= data.size) {
            return false
        }
        let second = data[idx + 1]
        if (first >= 0x81u8 && first <= 0xfeu8 && second >= 0x40u8 && second <= 0xfeu8 && second != 0x7fu8) {
            idx += 2
        } else {
            return false
        }
    }
    return true
}

private func isUTF8(data: Array<UInt8>): Bool {
    var idx: Int64 = 0
    while (idx < data.size) {
        let first = data[idx]
        if ((first & 0x80u8) == 0x00u8) {
            idx++
            continue
        }
        let num = preNum(first)
        if (num < 3) {
            return false
        }
        idx++
        for (_ in 1..num) {
            if (idx >= data.size) {
                return false
            }
            if ((data[idx] & 0xc0u8) != 0x80u8) {
                return false
            }
            idx++
        }
    }
    return true
}

public class StringConvertor {
    public static func Normalize(str: String, isRawString!: Bool = false): String {
        let bytes = str.toArray()
        let builder = StringBuilder()
        var idx: Int64 = 0
        while (idx < bytes.size) {
            let current = bytes[idx]
            if (current == b'\\' && idx + 1 < bytes.size && !isRawString) {
                if (idx + 2 < bytes.size && bytes[idx + 1] == b'u' && bytes[idx + 2] == b'{') {
                    idx += 3
                    var point: UInt32 = 0u32
                    while (idx < bytes.size && isHexDigit(bytes[idx])) {
                        point = point * 16u32 + hexValue(bytes[idx])
                        idx++
                    }
                    builder.append(CodepointToUTF8(point))
                    if (idx < bytes.size) {
                        idx++
                    }
                    continue
                }
                if (let Some(escaped) <- escapedByte(bytes[idx + 1])) {
                    builder.append(escaped)
                    idx += 2
                    continue
                }
                idx++
                continue
            }
            if (current == b'\r') {
                if (idx + 1 < bytes.size && bytes[idx + 1] == b'\n') {
                    builder.append("\n")
                    idx += 2
                } else {
                    builder.append("\n")
                    idx++
                }
            } else {
                builder.append(singleByteString(current))
                idx++
            }
        }
        return builder.toString()
    }

    public static func Recover(str: String): String {
        let builder = StringBuilder()
        for (byte in str.toArray()) {
            if (let Some(escaped) <- escapeForRecover(byte)) {
                builder.append(escaped)
            } else {
                builder.append(singleByteString(byte))
            }
        }
        return builder.toString()
    }

    public static func EscapeToJsonString(str: String): String {
        let builder = StringBuilder()
        for (byte in str.toArray()) {
            if (let Some(escaped) <- escapeForJson(byte)) {
                builder.append(escaped)
            } else {
                builder.append(singleByteString(byte))
            }
        }
        return builder.toString()
    }

    public static func UTF8ToCodepoint(str: String): Array<UInt32> {
        let ret = ArrayList<UInt32>()
        let bytes = str.toArray()
        var idx: Int64 = 0
        while (idx < bytes.size) {
            var ch = UInt32(bytes[idx])
            if (ch >= BYTE_2_FLAG && idx + 1 < bytes.size) {
                let byte1 = ch
                let byte2 = UInt32(bytes[idx + 1])
                if (ch >= BYTE_6_FLAG && idx + 5 < bytes.size) {
                    let byte3 = UInt32(bytes[idx + 2])
                    let byte4 = UInt32(bytes[idx + 3])
                    let byte5 = UInt32(bytes[idx + 4])
                    let byte6 = UInt32(bytes[idx + 5])
                    ch = ((byte1 & LOW_1_BIT_MASK) << 30) | ((byte2 & LOW_6_BIT_MASK) << 24) |
                        ((byte3 & LOW_6_BIT_MASK) << 18) | ((byte4 & LOW_6_BIT_MASK) << 12) |
                        ((byte5 & LOW_6_BIT_MASK) << 6) | (byte6 & LOW_6_BIT_MASK)
                    idx += 6
                } else if (ch >= BYTE_5_FLAG && idx + 4 < bytes.size) {
                    let byte3 = UInt32(bytes[idx + 2])
                    let byte4 = UInt32(bytes[idx + 3])
                    let byte5 = UInt32(bytes[idx + 4])
                    ch = ((byte1 & LOW_2_BIT_MASK) << 24) | ((byte2 & LOW_6_BIT_MASK) << 18) |
                        ((byte3 & LOW_6_BIT_MASK) << 12) | ((byte4 & LOW_6_BIT_MASK) << 6) |
                        (byte5 & LOW_6_BIT_MASK)
                    idx += 5
                } else if (ch >= BYTE_4_FLAG && idx + 3 < bytes.size) {
                    let byte3 = UInt32(bytes[idx + 2])
                    let byte4 = UInt32(bytes[idx + 3])
                    ch = ((byte1 & LOW_3_BIT_MASK) << 18) | ((byte2 & LOW_6_BIT_MASK) << 12) |
                        ((byte3 & LOW_6_BIT_MASK) << 6) | (byte4 & LOW_6_BIT_MASK)
                    idx += 4
                } else if (ch >= BYTE_3_FLAG && idx + 2 < bytes.size) {
                    let byte3 = UInt32(bytes[idx + 2])
                    ch = ((byte1 & LOW_4_BIT_MASK) << 12) | ((byte2 & LOW_6_BIT_MASK) << 6) |
                        (byte3 & LOW_6_BIT_MASK)
                    idx += 3
                } else {
                    ch = ((byte1 & LOW_5_BIT_MASK) << 6) | (byte2 & LOW_6_BIT_MASK)
                    idx += 2
                }
            } else {
                idx++
            }
            ret.add(ch)
        }
        return ret.toArray()
    }

    public static func CodepointToUTF8(pointValue: UInt32): String {
        let bytes = ArrayList<UInt8>()
        if (pointValue <= UTF8_1_MAX) {
            bytes.add(UInt8(pointValue))
        } else if (pointValue <= UTF8_2_MAX) {
            bytes.add(UInt8(((pointValue >> 6) & LOW_5_BIT_MASK) | BYTE_2_FLAG))
            bytes.add(UInt8((pointValue & LOW_6_BIT_MASK) | BYTE_X_FLAG))
        } else if (pointValue <= UTF8_3_MAX) {
            bytes.add(UInt8(((pointValue >> 12) & LOW_4_BIT_MASK) | BYTE_3_FLAG))
            bytes.add(UInt8(((pointValue >> 6) & LOW_6_BIT_MASK) | BYTE_X_FLAG))
            bytes.add(UInt8((pointValue & LOW_6_BIT_MASK) | BYTE_X_FLAG))
        } else if (pointValue <= UTF8_4_MAX) {
            bytes.add(UInt8(((pointValue >> 18) & LOW_3_BIT_MASK) | BYTE_4_FLAG))
            bytes.add(UInt8(((pointValue >> 12) & LOW_6_BIT_MASK) | BYTE_X_FLAG))
            bytes.add(UInt8(((pointValue >> 6) & LOW_6_BIT_MASK) | BYTE_X_FLAG))
            bytes.add(UInt8((pointValue & LOW_6_BIT_MASK) | BYTE_X_FLAG))
        } else if (pointValue <= UTF8_5_MAX) {
            bytes.add(UInt8(((pointValue >> 24) & LOW_2_BIT_MASK) | BYTE_5_FLAG))
            bytes.add(UInt8(((pointValue >> 18) & LOW_6_BIT_MASK) | BYTE_X_FLAG))
            bytes.add(UInt8(((pointValue >> 12) & LOW_6_BIT_MASK) | BYTE_X_FLAG))
            bytes.add(UInt8(((pointValue >> 6) & LOW_6_BIT_MASK) | BYTE_X_FLAG))
            bytes.add(UInt8((pointValue & LOW_6_BIT_MASK) | BYTE_X_FLAG))
        } else if (pointValue <= UTF8_6_MAX) {
            bytes.add(UInt8(((pointValue >> 30) & LOW_1_BIT_MASK) | BYTE_6_FLAG))
            bytes.add(UInt8(((pointValue >> 24) & LOW_6_BIT_MASK) | BYTE_X_FLAG))
            bytes.add(UInt8(((pointValue >> 18) & LOW_6_BIT_MASK) | BYTE_X_FLAG))
            bytes.add(UInt8(((pointValue >> 12) & LOW_6_BIT_MASK) | BYTE_X_FLAG))
            bytes.add(UInt8(((pointValue >> 6) & LOW_6_BIT_MASK) | BYTE_X_FLAG))
            bytes.add(UInt8((pointValue & LOW_6_BIT_MASK) | BYTE_X_FLAG))
        }
        return String.fromUtf8(bytes.toArray())
    }

    public static func GetUnicodeAndToUTF8(hex: String): String {
        var point: UInt32 = 0u32
        for (byte in hex.toArray()) {
            if (!isHexDigit(byte)) {
                break
            }
            point = point * 16u32 + hexValue(byte)
        }
        return CodepointToUTF8(point)
    }

    public static func GetStringEncoding(data: String): StrEncoding {
        let bytes = data.toArray()
        if (isUTF8(bytes)) {
            return StrEncoding.UTF8
        }
        if (isGBK(bytes)) {
            return StrEncoding.GBK
        }
        return StrEncoding.UNKNOWN
    }

    public static func GBKToUTF8(gbkStr: String): Option<String> {
        let bytes = gbkStr.toArray()
        if (isAscii(bytes)) {
            return gbkStr
        }
        return None
    }

    public static func UTF8ToGBK(utf8Str: String): Option<String> {
        let bytes = utf8Str.toArray()
        if (isAscii(bytes)) {
            return utf8Str
        }
        return None
    }

    public static func NormalizeStringToUTF8(data: String): Option<String> {
        let encoding = GetStringEncoding(data)
        if (encoding == StrEncoding.UTF8) {
            return data
        }
        if (encoding == StrEncoding.GBK) {
            return GBKToUTF8(data)
        }
        return None
    }

    public static func NormalizeStringToGBK(data: String): Option<String> {
        let encoding = GetStringEncoding(data)
        if (encoding == StrEncoding.UTF8) {
            return UTF8ToGBK(data)
        }
        if (encoding == StrEncoding.GBK) {
            return data
        }
        return None
    }
}
