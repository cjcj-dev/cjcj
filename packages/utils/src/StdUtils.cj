package cangjie_compiler::utils

public let STOINT_BASE: Int64 = 10

private let INT64_POSITIVE_LIMIT: UInt64 = 9223372036854775807u64
private let INT64_NEGATIVE_LIMIT: UInt64 = 9223372036854775808u64
private let ERANGE_ERRNO: Int32 = 34

foreign {
    func strtod(nptr: CString, endptr: CPointer<CString>): Float64
}

@When[os == "Linux"]
private func errnoLocationForStdUtils(): CPointer<Int32> {
    unsafe {
        return __errno_location()
    }
}

@When[os == "macOS"]
private func errnoLocationForStdUtils(): CPointer<Int32> {
    unsafe {
        return __error()
    }
}

@When[os != "Linux" && os != "macOS"]
private func errnoLocationForStdUtils(): CPointer<Int32> {
    return CPointer<Int32>()
}

private func resetStdUtilsErrno(): Unit {
    unsafe {
        let errnoPtr = errnoLocationForStdUtils()
        if (!errnoPtr.isNull()) {
            errnoPtr.write(0)
        }
    }
}

private func stdUtilsErrno(): Int32 {
    unsafe {
        let errnoPtr = errnoLocationForStdUtils()
        if (errnoPtr.isNull()) {
            return 0
        }
        return errnoPtr.read()
    }
}

private func isAsciiSpace(byte: UInt8): Bool {
    return byte == b' ' || byte == b'\t' || byte == b'\n' || byte == b'\r' || byte == b'\v' || byte == b'\f'
}

private func digitValue(byte: UInt8): Int64 {
    if (byte >= b'0' && byte <= b'9') {
        return Int64(byte - b'0')
    }
    if (byte >= b'a' && byte <= b'z') {
        return Int64(byte - b'a') + 10
    }
    if (byte >= b'A' && byte <= b'Z') {
        return Int64(byte - b'A') + 10
    }
    return -1
}

private func asciiLower(byte: UInt8): UInt8 {
    if (byte >= b'A' && byte <= b'Z') {
        return byte + (b'a' - b'A')
    }
    return byte
}

private func isValidBase(base: Int64): Bool {
    return base == 0 || (base >= 2 && base <= 36)
}

private func hasHexPrefixWithDigit(s: String, idx: Int64): Bool {
    if (idx + 2 >= s.size || s[idx] != b'0' || (s[idx + 1] != b'x' && s[idx + 1] != b'X')) {
        return false
    }
    let digit = digitValue(s[idx + 2])
    return digit >= 0 && digit < 16
}

private func skipLeadingSpace(s: String): Int64 {
    var idx: Int64 = 0
    while (idx < s.size && isAsciiSpace(s[idx])) {
        idx++
    }
    return idx
}

private func parseMagnitude(s: String, base: Int64): Option<(Bool, UInt64)> {
    if (!isValidBase(base)) {
        return None
    }
    var idx = skipLeadingSpace(s)
    if (idx >= s.size) {
        return None
    }
    var negative = false
    if (s[idx] == b'+' || s[idx] == b'-') {
        negative = s[idx] == b'-'
        idx++
    }
    var actualBase = base
    if (actualBase == 0) {
        if (hasHexPrefixWithDigit(s, idx)) {
            actualBase = 16
            idx += 2
        } else if (idx < s.size && s[idx] == b'0') {
            actualBase = 8
        } else {
            actualBase = 10
        }
    } else if (actualBase == 16 && hasHexPrefixWithDigit(s, idx)) {
        idx += 2
    }
    var consumed = false
    var value: UInt64 = 0u64
    while (idx < s.size) {
        let digit = digitValue(s[idx])
        if (digit < 0 || digit >= actualBase) {
            break
        }
        let digit64 = UInt64(digit)
        let base64 = UInt64(actualBase)
        if (value > (UInt64.Max - digit64) / base64) {
            return None
        }
        value = value * base64 + digit64
        consumed = true
        idx++
    }
    if (!consumed) {
        return None
    }
    return (negative, value)
}

private func parseInt64Value(s: String, base: Int64): Option<Int64> {
    let parsed = parseMagnitude(s, base)
    if (let None <- parsed) {
        return None
    }
    let (negative, value) = parsed.getOrThrow()
    if (negative) {
        if (value > INT64_NEGATIVE_LIMIT) {
            return None
        }
        if (value == INT64_NEGATIVE_LIMIT) {
            return Int64.Min
        }
        return -Int64(value)
    }
    if (value > INT64_POSITIVE_LIMIT) {
        return None
    }
    return Int64(value)
}

private func parseUInt64Value(s: String, base: Int64): Option<UInt64> {
    let parsed = parseMagnitude(s, base)
    if (let None <- parsed) {
        return None
    }
    let (negative, value) = parsed.getOrThrow()
    if (!negative) {
        return value
    }
    if (value == 0u64) {
        return 0u64
    }
    return UInt64.Max - value + 1u64
}

private func hasPrefixIgnoreAsciiCase(s: String, start: Int64, prefix: String): Bool {
    if (start + prefix.size > s.size) {
        return false
    }
    var idx: Int64 = 0
    while (idx < prefix.size) {
        if (asciiLower(s[start + idx]) != asciiLower(prefix[idx])) {
            return false
        }
        idx++
    }
    return true
}

private func hasStrtodSubject(s: String): Bool {
    var idx = skipLeadingSpace(s)
    if (idx >= s.size) {
        return false
    }
    if (s[idx] == b'+' || s[idx] == b'-') {
        idx++
    }
    if (idx >= s.size) {
        return false
    }
    if (hasPrefixIgnoreAsciiCase(s, idx, "inf") || hasPrefixIgnoreAsciiCase(s, idx, "nan")) {
        return true
    }
    var consumedDigit = false
    while (idx < s.size && digitValue(s[idx]) >= 0 && digitValue(s[idx]) < 10) {
        consumedDigit = true
        idx++
    }
    if (idx < s.size && s[idx] == b'.') {
        idx++
        while (idx < s.size && digitValue(s[idx]) >= 0 && digitValue(s[idx]) < 10) {
            consumedDigit = true
            idx++
        }
    }
    return consumedDigit
}

private func parseFloat64Value(s: String): Option<Float64> {
    if (!hasStrtodSubject(s)) {
        return None
    }
    var result: Option<Float64> = None
    try (cInput = unsafe { LibC.mallocCString(s) }.asResource()) {
        if (!cInput.value.isNull()) {
            resetStdUtilsErrno()
            let parsed = unsafe { strtod(cInput.value, CPointer<CString>()) }
            result = if (stdUtilsErrno() == ERANGE_ERRNO) {
                None
            } else {
                parsed
            }
        }
    } catch (e: Exception) {
        result = None
    }
    return result
}

public func Stoi(s: String, base!: Int64 = STOINT_BASE): Option<Int64> {
    let parsed = parseInt64Value(s, base)
    if (let Some(v) <- parsed) {
        if (v >= Int64(Int32.Min) && v <= Int64(Int32.Max)) {
            return v
        }
    }
    return None
}

public func Stoui(s: String, base!: Int64 = STOINT_BASE): Option<UInt64> {
    let parsed = parseUInt64Value(s, base)
    if (let Some(v) <- parsed) {
        if (v <= UInt64(UInt32.Max)) {
            return v
        }
    }
    return None
}

public func Stol(s: String, base!: Int64 = STOINT_BASE): Option<Int64> {
    return parseInt64Value(s, base)
}

public func Stoul(s: String, base!: Int64 = STOINT_BASE): Option<UInt64> {
    return parseUInt64Value(s, base)
}

public func Stoll(s: String, base!: Int64 = STOINT_BASE): Option<Int64> {
    return parseInt64Value(s, base)
}

public func Stoull(s: String, base!: Int64 = STOINT_BASE): Option<UInt64> {
    return parseUInt64Value(s, base)
}

public func Stod(s: String): Option<Float64> {
    return parseFloat64Value(s)
}

public func Stold(s: String): Option<Float64> {
    return parseFloat64Value(s)
}
