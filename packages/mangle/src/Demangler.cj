package cangjie_compiler::mangle

// C++ source mapping:
// - demangler/Demangler.h and demangler/Demangler.cpp define template Demangler<T> and DemangleInfo<T>.
// - demangler/StdString.h adapts std::string to the CString-like API.
// In selfhost packages/mangle the only string carrier is Cangjie String, so the C++ template-over-string-type is
// collapsed once here: every C++ T/StdString/CString operation maps to String indexing, slicing, and concatenation.

private let ARGS_DELIMITER: String = ", "
private let ARGS_DELIMITER_TYPE: String = ","
private let LEFT_BRACKET: String = "("
private let RIGHT_BRACKET: String = ")"
private let MODULE_SPLIT: String = "/"
private let MANGLE_MODULE_SPLIT: String = "$"
private let MANGLE_FUNCTY_PREFIX: String = "F0"
private let MANGLE_C_FUNCTY_PREFIX: String = "FC"
private let MANGLE_FLOAT16_PREFIX: String = "Dh"
private let MANGLE_SET_PREFIX: String = "ps"
private let MANGLE_GET_PREFIX: String = "pg"
private let GLOBAL_VARIABLE_INIT_PREFIX: String = "GV"
private let MANGLE_GLOBAL_PACKAGE_INIT_PREFIX_DEMANGLER: String = "_CGP"
private let MANGLE_GLOBAL_FILE_INIT_PREFIX_DEMANGLER: String = "_CGF"
private let MANGLE_FUNC_PARA_INIT_PREFIX_DEMANGLER: String = "_CPI"
private let MANGLE_GLOBAL_INIT_SUFFIX: String = "iiHv"
private let MANGLE_GLOBAL_INIT_RESET_SUFFIX: String = "irHv"
private let MANGLE_GLOBAL_INIT_FLAG_RESET_SUFFIX: String = "ifHv"
private let MANGLE_GLOBAL_INIT_LITERAL_RESET_SUFFIX: String = "ilHv"
private let MANGLE_GLOBAL_INIT_IMPORTS_INIT: String = "fiHv"
private let MANGLE_GLOBAL_LITERAL_IMPORTS_INIT: String = "flHv"
private let MANGLE_INNER_FUNCTION_PREFIX: String = "$lambda."
private let MANGLE_CFUNCTION_WRAPPER: String = "$real"
private let MANGLE_WRAPPED_FUNCTION_PREFIX: String = "_CV"
private let BOX_DECL_PREFIX: String = "$BOX_"
private let CJ_FILE_EXT: String = ".cj"
private let ERROR_EXCEED_THE_INPUT_STRING_LENGTH: String = "exceed the input string length"
private let MANGLE_TUPLE_STR: String = "Tuple"
private let MANGLE_ARRAY_STR: String = "RawArray"
private let MANGLE_VARRAY_STR: String = "VArray"
private let MANGLE_PTR_STR: String = "CPointer"
private let MANGLE_CSTRING_STR: String = "CString"
private let BASE62_CHARS: String = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
private let DECIMAL_CHARS: String = "0123456789"
private let WRAPPED_FUNCTION_SUFFIX_INFO: String = "<compiler generated>"
private let BASE62_CHARS_SIZE: Int64 = 62
private let MAX_ARGS_SIZE: Int64 = 16
private let UINT32_MAX_AS_INT64: Int64 = 4294967295

enum DemanglerTypeKind {
    | NAME
    | PRIMITIVE
    | CSTRING
    | CLASS
    | STRUCT
    | INTERFACE
    | ENUM
    | RAW_ARRAY
    | VARRAY
    | TUPLE
    | CPOINTER
    | FUNCTION
    | COMMON_DECL
    | FUNCTION_DECL
    | FUNCTION_PARAMETER_TYPES
    | LAMBDA_FUNCTION
    | GENERIC_TYPES
    | GENERIC_CONSTRAINTS
    | WRAPPED_FUNCTION
}

extend DemanglerTypeKind <: Equatable<DemanglerTypeKind> {
    public operator func ==(right: DemanglerTypeKind): Bool {
        return match (this) {
            case DemanglerTypeKind.NAME => match (right) { case DemanglerTypeKind.NAME => true case _ => false }
            case DemanglerTypeKind.PRIMITIVE => match (right) { case DemanglerTypeKind.PRIMITIVE => true case _ => false }
            case DemanglerTypeKind.CSTRING => match (right) { case DemanglerTypeKind.CSTRING => true case _ => false }
            case DemanglerTypeKind.CLASS => match (right) { case DemanglerTypeKind.CLASS => true case _ => false }
            case DemanglerTypeKind.STRUCT => match (right) { case DemanglerTypeKind.STRUCT => true case _ => false }
            case DemanglerTypeKind.INTERFACE => match (right) { case DemanglerTypeKind.INTERFACE => true case _ => false }
            case DemanglerTypeKind.ENUM => match (right) { case DemanglerTypeKind.ENUM => true case _ => false }
            case DemanglerTypeKind.RAW_ARRAY => match (right) { case DemanglerTypeKind.RAW_ARRAY => true case _ => false }
            case DemanglerTypeKind.VARRAY => match (right) { case DemanglerTypeKind.VARRAY => true case _ => false }
            case DemanglerTypeKind.TUPLE => match (right) { case DemanglerTypeKind.TUPLE => true case _ => false }
            case DemanglerTypeKind.CPOINTER => match (right) { case DemanglerTypeKind.CPOINTER => true case _ => false }
            case DemanglerTypeKind.FUNCTION => match (right) { case DemanglerTypeKind.FUNCTION => true case _ => false }
            case DemanglerTypeKind.COMMON_DECL => match (right) { case DemanglerTypeKind.COMMON_DECL => true case _ => false }
            case DemanglerTypeKind.FUNCTION_DECL => match (right) { case DemanglerTypeKind.FUNCTION_DECL => true case _ => false }
            case DemanglerTypeKind.FUNCTION_PARAMETER_TYPES => match (right) {
                case DemanglerTypeKind.FUNCTION_PARAMETER_TYPES => true
                case _ => false
            }
            case DemanglerTypeKind.LAMBDA_FUNCTION => match (right) { case DemanglerTypeKind.LAMBDA_FUNCTION => true case _ => false }
            case DemanglerTypeKind.GENERIC_TYPES => match (right) { case DemanglerTypeKind.GENERIC_TYPES => true case _ => false }
            case DemanglerTypeKind.GENERIC_CONSTRAINTS => match (right) {
                case DemanglerTypeKind.GENERIC_CONSTRAINTS => true
                case _ => false
            }
            case DemanglerTypeKind.WRAPPED_FUNCTION => match (right) { case DemanglerTypeKind.WRAPPED_FUNCTION => true case _ => false }
        }
    }

    public operator func !=(right: DemanglerTypeKind): Bool {
        return !(this == right)
    }
}

private func ByteToString(ch: Byte): String {
    return String.fromUtf8([ch])
}

private func GetPrimitiveDemangleMap(t: Byte): String {
    return match (t) {
        case b'u' => "Unit"
        case b'n' => "Nothing"
        case b'b' => "Bool"
        case b'D' => "Float16"
        case b'f' => "Float32"
        case b'd' => "Float64"
        case b'c' => "Rune"
        case b'a' => "Int8"
        case b's' => "Int16"
        case b'i' => "Int32"
        case b'l' => "Int64"
        case b'h' => "UInt8"
        case b't' => "UInt16"
        case b'j' => "UInt32"
        case b'm' => "UInt64"
        case b'q' => "IntNative"
        case b'r' => "UIntNative"
        case _ => ""
    }
}

private func GetOperatorNameMap(replaced: String): String {
    let chBase: Int64 = 97
    if (!((replaced[0] >= b'a' && replaced[0] <= b'z') && (replaced[1] >= b'a' && replaced[1] <= b'z'))) {
        return ""
    }
    let operatorIndex = ((Int64(replaced[0]) - chBase) << 5) + Int64(replaced[1]) - chBase
    return match (operatorIndex) {
        case 279 => "[]"
        case 435 => "!"
        case 422 => "-"
        case 502 => "**"
        case 395 => "*"
        case 117 => "/"
        case 556 => "%"
        case 491 => "+"
        case 370 => "<<"
        case 562 => ">>"
        case 371 => "<"
        case 211 => ">"
        case 356 => "<="
        case 196 => ">="
        case 144 => "=="
        case 420 => "!="
        case 13 => "&"
        case 142 => "^"
        case 465 => "|"
        case 75 => "()"
        case _ => ""
    }
}

private func ReplaceString(str: String, pattern: String, replacement: String): String {
    if (str.isEmpty()) {
        return str
    }
    var out = str
    var posOpt = out.indexOf(pattern)
    while (let Some(pos) <- posOpt) {
        let currentLen = out.size
        if (currentLen - pos - pattern.size <= 0) {
            break
        }
        out = out[0..pos] + replacement + out[pos + pattern.size..currentLen]
        posOpt = out.indexOf(pattern)
    }
    return out
}

private func IsPrimitive(ch: Byte): Bool {
    return GetPrimitiveDemangleMap(ch) != ""
}

private func IsCurrentCharDigit(ch: Byte): Bool {
    return ch >= b'0' && ch <= b'9'
}

private func IsGeneric(ch: Byte): Bool {
    return ch == b'I'
}

private func IsFunction(ch: Byte): Bool {
    return ch == b'H'
}

class DemangleInfo {
    var `type`: DemanglerTypeKind = DemanglerTypeKind.NAME
    var pkgName: String = ""
    var args: String = ""
    var genericConstraints: String = ""
    var genericTypes: String = ""
    var functionParameterTypes: String = ""
    var demangled: String = ""
    var isPrivateDeclaration: Bool = false
    private var isValid: Bool = true

    init() {}

    init(name: String, kind: DemanglerTypeKind) {
        this.`type` = kind
        this.demangled = name
    }

    init(name: String, kind: DemanglerTypeKind, pIsValid: Bool) {
        this.`type` = kind
        this.demangled = name
        this.isValid = pIsValid
    }

    private func MatchSuffix(pattern: String, len: Int64): Bool {
        let index = if (demangled.size > len) { demangled.size - len } else { 0 }
        let suffix = demangled[index..demangled.size]
        return suffix == pattern
    }

    func GetFullName(scopeRes: String): String {
        return GetFullName(scopeRes, 0)
    }

    func GetFullName(scopeRes: String, argsNum: Int64): String {
        var fullDemangledName = ""
        match (this.`type`) {
            case DemanglerTypeKind.FUNCTION => return GetFunctionName()
            case DemanglerTypeKind.GENERIC_CONSTRAINTS => return GetGenericConstraintsName()
            case _ =>
                let pkg = GetPkgName()
                let identifier = GetIdentifier()
                if (!IsFunctionLike() && this.`type` != DemanglerTypeKind.COMMON_DECL) {
                    if (!pkg.isEmpty() && !identifier.isEmpty()) {
                        fullDemangledName += pkg
                        fullDemangledName += scopeRes
                        fullDemangledName += identifier
                    } else {
                        fullDemangledName += pkg
                        fullDemangledName += identifier
                    }
                } else {
                    fullDemangledName += identifier
                }
                fullDemangledName += GetGenericTypes()
                fullDemangledName += GetArgTypesName(argsNum)
                fullDemangledName += GetGenericConstraints()
        }
        return fullDemangledName
    }

    func GetPkgName(): String {
        return pkgName
    }

    func GetReturnType(): String {
        return demangled
    }

    private func GetGenericConstraints(): String {
        return genericConstraints
    }

    private func GetGenericTypes(): String {
        return genericTypes
    }

    private func GetGenericConstraintsName(): String {
        let separatorFromDecl = ", "
        var gcName = separatorFromDecl + demangled
        gcName += " <: "
        gcName += ReplaceString(args, ",", " &")
        return gcName
    }

    func GetArgTypesName(): String {
        return GetArgTypesName(0)
    }

    func GetArgTypesName(argsNum: Int64): String {
        if (args.isEmpty()) {
            return if (IsFunctionLike()) { "()" } else { "" }
        }
        if (IsFunctionLike()) {
            return "(" + args + ")"
        }
        if (argsNum != 0) {
            let numStr = argsNum.toString()
            return "<" + args + ",$" + numStr + ">"
        }
        return "<" + args + ">"
    }

    func IsFunctionLike(): Bool {
        return `type` == DemanglerTypeKind.FUNCTION_DECL || `type` == DemanglerTypeKind.LAMBDA_FUNCTION ||
            `type` == DemanglerTypeKind.FUNCTION || `type` == DemanglerTypeKind.WRAPPED_FUNCTION
    }

    func IsValid(): Bool {
        return isValid
    }

    private func GetFunctionName(): String {
        return GetArgTypesName() + " -> " + GetReturnType()
    }

    func GetIdentifier(): String {
        if (!demangled.isEmpty() && demangled[0] == b'<' && EndsWith(demangled, ">")) {
            return demangled[1..demangled.size - 1]
        }
        return demangled
    }
}

private func GetArgTypesFullName(args: Array<String>, argSize: Int64, delimiter: String): String {
    if (argSize == 0) {
        return ""
    }
    var argTypesFullName = args[0]
    var i: Int64 = 1
    while (i < argSize) {
        argTypesFullName += delimiter + args[i]
        i++
    }
    return argTypesFullName
}

class Demangler {
    private var isValid: Bool = true
    private var curType: DemanglerTypeKind = DemanglerTypeKind.NAME
    private var currentIndex: Int64 = 0
    private var genericTypefilter: (String) -> String = { str: String => str }
    private var mangledName: String
    private var scopeResolution: String
    private var dumpDi: DemangleInfo
    private var genericVec: Array<String>

    init(mangled: String, stripUnderscore!: Bool = false, scopeRes!: String = "::",
        genericParamFilter!: (String) -> String = { str: String => str }, genericVec!: Array<String> = Array<String>()) {
        this.genericTypefilter = genericParamFilter
        this.scopeResolution = scopeRes
        this.mangledName = mangled
        if (stripUnderscore && !mangled.isEmpty() && mangled[0] == b'_') {
            this.mangledName = this.mangledName[1..]
        }
        this.dumpDi = DemangleInfo(this.mangledName, DemanglerTypeKind.NAME, false)
        this.genericVec = genericVec
    }

    func ScopeResolution(): String {
        return scopeResolution
    }

    func setGenericVec(vec: Array<String>): Unit {
        genericVec = vec
    }

    private func IsProp(): Bool {
        if (currentIndex + MANGLE_CHAR_LEN < mangledName.size) {
            let str = mangledName[currentIndex..currentIndex + MANGLE_SPECIAL_NAME_LEN]
            return str == MANGLE_SET_PREFIX || str == MANGLE_GET_PREFIX
        }
        return false
    }

    private func IsInnerFunction(): Bool {
        if (mangledName.size - MANGLE_CHAR_LEN > MANGLE_INNER_FUNCTION_PREFIX.size) {
            return mangledName.indexOf(MANGLE_INNER_FUNCTION_PREFIX).isSome()
        }
        return false
    }

    private func IsOperatorName(): Bool {
        let id = currentIndex + MANGLE_SPECIAL_NAME_LEN
        if (id < mangledName.size &&
            GetOperatorNameMap(mangledName[currentIndex..currentIndex + MANGLE_SPECIAL_NAME_LEN]) != "" &&
            (mangledName[id] == b'I' || mangledName[id] == b'H' || mangledName[id] == b'K')) {
            return true
        }
        return false
    }

    private func IsMaybeDefaultFuncParamFunction(): Bool {
        return currentIndex < mangledName.size && mangledName[currentIndex] == b'$'
    }

    private func IsNotEndOfMangledName(): Bool {
        return currentIndex < mangledName.size && mangledName[currentIndex] != b'E'
    }

    private func DemangleLength(): Int64 {
        if (currentIndex >= mangledName.size) {
            Reject(ERROR_EXCEED_THE_INPUT_STRING_LENGTH)
            return 0
        }
        if (mangledName[currentIndex] == b'0') {
            currentIndex++
            return 0
        }

        var numStr = ""
        isValid = false
        while (currentIndex < mangledName.size && IsCurrentCharDigit(mangledName[currentIndex])) {
            numStr += ByteToString(mangledName[currentIndex])
            currentIndex++
            isValid = true
        }
        if (numStr.isEmpty()) {
            return 0
        }
        var num: Int64 = 0
        for (ch in numStr.toArray()) {
            num = num * 10 + Int64(ch - b'0')
            if (num > UINT32_MAX_AS_INT64) {
                return 0
            }
        }
        return num
    }

    private func UIntToString(value: Int64): String {
        var currentValue = value
        var result = ""
        if (currentValue == 0) {
            return "0"
        }
        while (currentValue != 0) {
            let current = DECIMAL_CHARS[currentValue % 10]
            currentValue /= 10
            result = ByteToString(current) + result
        }
        return result
    }

    private func IsGlobalInit(): Bool {
        let isPkgInit = MatchForward(MANGLE_GLOBAL_PACKAGE_INIT_PREFIX_DEMANGLER,
            MANGLE_GLOBAL_PACKAGE_INIT_PREFIX_DEMANGLER.size)
        let isFileInit = MatchForward(MANGLE_GLOBAL_FILE_INIT_PREFIX_DEMANGLER,
            MANGLE_GLOBAL_FILE_INIT_PREFIX_DEMANGLER.size)
        return isPkgInit || isFileInit
    }

    private func IsParamInit(): Bool {
        return MatchForward(MANGLE_FUNC_PARA_INIT_PREFIX_DEMANGLER, MANGLE_FUNC_PARA_INIT_PREFIX_DEMANGLER.size)
    }

    private func IsCFunctionWrapper(): Bool {
        if (mangledName.size > MANGLE_CFUNCTION_WRAPPER.size) {
            return mangledName.indexOf(MANGLE_CFUNCTION_WRAPPER, 0).isSome()
        }
        return false
    }

    private func IsWrappedFunction(): Bool {
        return (mangledName.indexOf(MANGLE_WRAPPED_FUNCTION_PREFIX, 0) ?? -1) == 0
    }

    private func IsQualifiedType(): Bool {
        if (currentIndex >= mangledName.size) {
            return false
        }
        if (currentIndex + MANGLE_CHAR_LEN < mangledName.size) {
            if ((mangledName[currentIndex] == b'D' && mangledName[currentIndex + MANGLE_CHAR_LEN] == b'h') ||
                (mangledName[currentIndex] == b'F' && mangledName[currentIndex + MANGLE_CHAR_LEN] == b'0') ||
                (mangledName[currentIndex] == b'F' && mangledName[currentIndex + MANGLE_CHAR_LEN] == b'C')) {
                return true
            }
        }
        if (IsPrimitive(mangledName[currentIndex])) {
            return true
        }
        for (prefix in [b'C', b'R', b'F', b'N', b'T', b'P', b'A', b'k', b'V', b'G']) {
            if (mangledName[currentIndex] == prefix) {
                return true
            }
        }
        return false
    }

    private func IsDecl(): Bool {
        return MatchForward(MANGLE_NESTED_PREFIX, MANGLE_NESTED_PREFIX.size)
    }

    private func ErrorLog(msg: String): Unit {}

    private func MatchForward(pattern: String, len: Int64): Bool {
        if (currentIndex >= mangledName.size) {
            return len == 0
        }
        let maxLen = mangledName.size - currentIndex
        let realLen = if (len > maxLen) { maxLen } else { len }
        let prefix = mangledName[currentIndex..currentIndex + realLen]
        return prefix == pattern
    }

    private func PeekChar(): Option<Byte> {
        if (currentIndex >= mangledName.size) {
            return None
        }
        return mangledName[currentIndex]
    }

    private func GetChar(): Option<Byte> {
        if (let Some(ch) <- PeekChar()) {
            currentIndex++
            return ch
        }
        return None
    }

    private func SkipChar(ch: Byte): Unit {
        if (currentIndex >= mangledName.size) {
            Reject(ERROR_EXCEED_THE_INPUT_STRING_LENGTH)
            return
        }
        if (mangledName[currentIndex] != ch) {
            Reject("should be the character: " + ByteToString(ch))
            return
        }
        currentIndex++
    }

    private func SkipOptionalChar(ch: Byte): Unit {
        if (currentIndex >= mangledName.size) {
            return
        }
        if (mangledName[currentIndex] == ch) {
            currentIndex++
        }
    }

    private func SkipString(pattern: String): Unit {
        var i: Int64 = 0
        while (i < pattern.size) {
            SkipChar(pattern[i])
            if (!isValid) {
                return
            }
            i++
        }
    }

    func DemangleGlobalInit(): DemangleInfo {
        var prefix = ""
        if (MatchForward(MANGLE_GLOBAL_PACKAGE_INIT_PREFIX_DEMANGLER, MANGLE_GLOBAL_PACKAGE_INIT_PREFIX_DEMANGLER.size)) {
            SkipString(MANGLE_GLOBAL_PACKAGE_INIT_PREFIX_DEMANGLER)
            let pkgDi = DemanglePackageName()
            prefix = pkgDi.pkgName + "::package"
        } else if (MatchForward(MANGLE_GLOBAL_FILE_INIT_PREFIX_DEMANGLER, MANGLE_GLOBAL_FILE_INIT_PREFIX_DEMANGLER.size)) {
            SkipString(MANGLE_GLOBAL_FILE_INIT_PREFIX_DEMANGLER)
            let pkgDi = DemanglePackageName()
            prefix = pkgDi.pkgName + "::file"
        } else {
            return Reject("invalid global init function")
        }
        if (EndsWith(mangledName, MANGLE_GLOBAL_INIT_RESET_SUFFIX)) {
            return DemangleInfo(prefix + "_global_reset", DemanglerTypeKind.NAME, isValid)
        } else if (EndsWith(mangledName, MANGLE_GLOBAL_INIT_FLAG_RESET_SUFFIX)) {
            return DemangleInfo(prefix + "_global_flag_reset", DemanglerTypeKind.NAME, isValid)
        } else if (EndsWith(mangledName, MANGLE_GLOBAL_INIT_LITERAL_RESET_SUFFIX)) {
            return DemangleInfo(prefix + "_global_init_literal", DemanglerTypeKind.NAME, isValid)
        } else if (EndsWith(mangledName, MANGLE_GLOBAL_INIT_IMPORTS_INIT)) {
            return DemangleInfo(prefix + "_global_init_imports", DemanglerTypeKind.NAME, isValid)
        } else if (EndsWith(mangledName, MANGLE_GLOBAL_LITERAL_IMPORTS_INIT)) {
            return DemangleInfo(prefix + "_global_init_import_literal", DemanglerTypeKind.NAME, isValid)
        } else if (!EndsWith(mangledName, MANGLE_GLOBAL_INIT_SUFFIX)) {
            return Reject("global init function should end with iiHv")
        }
        return DemangleInfo(prefix + "_global_init", DemanglerTypeKind.NAME, isValid)
    }

    func DemangleParamInit(): DemangleInfo {
        SkipString(MANGLE_FUNC_PARA_INIT_PREFIX_DEMANGLER)
        let di = DemangleInfo("", DemanglerTypeKind.COMMON_DECL)
        let pkgDi = DemanglePackageName()
        di.pkgName = pkgDi.pkgName
        di.isPrivateDeclaration = pkgDi.isPrivateDeclaration
        let nestedDi = DemangleNestedDecls(isParamInit: true)
        di.demangled = nestedDi.demangled
        di.`type` = nestedDi.`type`
        di.args = nestedDi.args
        if (!isValid || di.demangled.isEmpty()) {
            return Reject()
        }
        if (di.`type` == DemanglerTypeKind.FUNCTION_DECL) {
            di.args = nestedDi.functionParameterTypes
        }
        return di
    }

    func DemangleClassType(): String {
        return DemangleClass(DemanglerTypeKind.CLASS).GetIdentifier()
    }

    func DemangleQualifiedName(): String {
        let info = Demangle(isType: true)
        let pkgName = info.GetPkgName()
        let clsName = info.GetIdentifier()
        if (pkgName.isEmpty()) {
            return clsName
        }
        return pkgName + "." + clsName
    }

    func Demangle(isType!: Bool = false): DemangleInfo {
        if (isType) {
            if (!IsQualifiedType()) {
                return Reject("invalid mangling name")
            }
            return DemangleNextUnit("invalid mangling name")
        }
        if (mangledName.isEmpty()) {
            return Reject("invalid mangling name")
        }
        mangledName = DeCompression(mangledName[0..]).CJMangledDeCompression()
        if (IsGlobalInit()) {
            return DemangleGlobalInit()
        }
        if (IsParamInit()) {
            return DemangleParamInit()
        }
        if (IsInnerFunction()) {
            return DemangleInnerFunction()
        }
        if (IsCFunctionWrapper()) {
            return DemangleInfo(mangledName[0..mangledName.size - MANGLE_CFUNCTION_WRAPPER.size], DemanglerTypeKind.NAME, isValid)
        }
        if (IsWrappedFunction()) {
            return DemangleWrappedFunction()
        }
        return DemangleDecl()
    }

    func DemanglePackageName(): DemangleInfo {
        if (currentIndex >= mangledName.size) {
            Reject(ERROR_EXCEED_THE_INPUT_STRING_LENGTH)
            return DemangleInfo("", DemanglerTypeKind.COMMON_DECL)
        }
        var pkg = ""
        if (currentIndex + MANGLE_SPECIAL_NAME_LEN <= mangledName.size) {
            if (let Some(stdPkg) <- MANGLE_STDPKG_MAP(mangledName[currentIndex..currentIndex + MANGLE_SPECIAL_NAME_LEN])) {
                pkg = stdPkg
                currentIndex += MANGLE_SPECIAL_NAME_LEN
            } else if (!IsCurrentCharDigit(mangledName[currentIndex])) {
                Reject("should be a number")
                return DemangleInfo("", DemanglerTypeKind.COMMON_DECL)
            }
        } else if (!IsCurrentCharDigit(mangledName[currentIndex])) {
            Reject("should be a number")
            return DemangleInfo("", DemanglerTypeKind.COMMON_DECL)
        }
        if (mangledName[currentIndex] == b'0') {
            currentIndex++
            return DemangleInfo("", DemanglerTypeKind.COMMON_DECL)
        }
        let di = DemangleInfo("", DemanglerTypeKind.COMMON_DECL)
        if (pkg.isEmpty()) {
            pkg = DemangleStringName()
            if (let Some(pos) <- pkg.indexOf(":")) {
                if (pkg.size - pos > 1) {
                    pkg = pkg[0..pos] + ":" + pkg[pos..pkg.size]
                }
            }
        }
        if (IsFileName()) {
            di.isPrivateDeclaration = true
            DemangleFileName()
        }
        di.pkgName = ReplaceString(pkg, MANGLE_MODULE_SPLIT, MODULE_SPLIT)
        return di
    }

    private func DemangleStringName(): String {
        let identifyLength = DemangleLength()
        if (identifyLength == 0) {
            Reject("previous number should be non-zero")
            return ""
        }
        if (identifyLength > mangledName.size - currentIndex) {
            Reject("previous number is greater than the string size")
            return ""
        }
        let name = mangledName[currentIndex..currentIndex + identifyLength]
        currentIndex += identifyLength
        return name
    }

    private func DemangleProp(): String {
        var `prop` = ""
        if (mangledName[currentIndex..currentIndex + MANGLE_SPECIAL_NAME_LEN] == MANGLE_SET_PREFIX) {
            `prop` = "::set"
        } else {
            `prop` = "::get"
        }
        currentIndex += MANGLE_SPECIAL_NAME_LEN
        return `prop`
    }

    private func SkipPrivateTopLevelDeclHash(): Unit {
        if (currentIndex >= mangledName.size || !IsCurrentCharDigit(mangledName[currentIndex]) ||
            mangledName[currentIndex] == b'0') {
            return
        }
        let oldIdx = currentIndex
        let hashLen = DemangleLength()
        if (currentIndex + hashLen >= mangledName.size || mangledName[currentIndex] != b'$') {
            currentIndex = oldIdx
            return
        }
        let isBoxedDecl = (mangledName.indexOf(BOX_DECL_PREFIX, currentIndex) ?? -1) == currentIndex &&
            !EndsWith(mangledName[currentIndex..currentIndex + hashLen], CJ_FILE_EXT)
        if (isBoxedDecl) {
            currentIndex = oldIdx
            return
        }
        currentIndex += hashLen
    }

    private func DemangleManglingNumber(): Int64 {
        var content = ""
        while (true) {
            if (let Some(c) <- GetChar()) {
                if (c == b'_') {
                    break
                } else {
                    content += ByteToString(c)
                }
            } else {
                Reject("mangling number has no termination symbol")
                return 0
            }
        }
        if (content == "") {
            return 0
        }
        var value: Int64 = 0
        var power: Int64 = 1
        var index = content.size - 1
        while (true) {
            var matched = false
            var i: Int64 = 0
            while (i < BASE62_CHARS_SIZE) {
                if (content[index] == BASE62_CHARS[i]) {
                    value += i * power
                    power *= BASE62_CHARS_SIZE
                    matched = true
                    break
                }
                i++
            }
            if (!matched) {
                Reject("mangling number has invalid character")
                return 0
            }
            if (index == 0) {
                break
            }
            index--
        }
        return value + 1
    }

    private func DemangleFileNameNumber(): Unit {
        var content = ""
        while (true) {
            if (content.size == FILE_HASH_LEN) {
                break
            } else if (let Some(c) <- GetChar()) {
                if (c == b'$') {
                    return
                } else {
                    content += ByteToString(c)
                }
            } else {
                Reject("mangling number has no termination symbol")
                return
            }
        }

        var index = content.size - 1
        while (true) {
            var matched = false
            var i: Int64 = 0
            while (i < BASE62_CHARS_SIZE) {
                if (content[index] == BASE62_CHARS[i]) {
                    matched = true
                    break
                }
                i++
            }
            if (!matched) {
                Reject("mangling number has invalid character")
                return
            }
            if (index == 0) {
                break
            }
            index--
        }
    }

    private func IsFileName(): Bool {
        if (let Some(c) <- PeekChar()) {
            if (c != b'U') {
                return false
            }
            return true
        }
        return false
    }

    private func DemangleFileName(): Unit {
        SkipChar(b'U')
        DemangleFileNameNumber()
    }

    private func SkipLocalCounter(): Unit {
        if (let Some(c) <- PeekChar()) {
            if (c != b'K') {
                return
            }
            SkipChar(b'K')
            DemangleManglingNumber()
        }
    }

    private func DemangleArgTypes(delimiter: String, size!: Int64 = UINT32_MAX_AS_INT64): String {
        if (currentIndex == mangledName.size - 1 && mangledName[currentIndex] == b'v') {
            SkipChar(b'v')
            return ""
        }
        var i: Int64 = 0
        var result = ""
        var hasTrailingDelimiter = false
        let argsArr = Array<String>(MAX_ARGS_SIZE, repeat: "")
        while (IsNotEndOfMangledName() && i < size) {
            if (mangledName[currentIndex] == b'_') {
                SkipChar(b'_')
            }
            if (IsMaybeDefaultFuncParamFunction()) {
                break
            }
            let curDi = DemangleNextUnit("invalid argument type")
            if (!isValid) {
                return ""
            }
            let j = i % MAX_ARGS_SIZE
            if (j == 0 && i != 0) {
                for (arg in argsArr) {
                    result += arg + delimiter
                }
                var resetIdx: Int64 = 0
                while (resetIdx < argsArr.size) {
                    argsArr[resetIdx] = ""
                    resetIdx++
                }
                hasTrailingDelimiter = true
            }
            i++
            argsArr[j] = curDi.GetFullName(scopeResolution)
        }
        if (i == 0) {
            return result
        }
        let remainingLength = ((i - 1) % MAX_ARGS_SIZE) + 1
        if (remainingLength == 0 && hasTrailingDelimiter) {
            result = result[0..result.size - delimiter.size]
        }
        result += GetArgTypesFullName(argsArr, remainingLength, delimiter)
        return result
    }

    private func DemangleNestedDecls(isClass!: Bool = false, isParamInit!: Bool = false): DemangleInfo {
        let delimiter = scopeResolution
        var i: Int64 = 0
        var result = ""
        let argsArr = Array<String>(MAX_ARGS_SIZE, repeat: "")
        var typeKind = DemanglerTypeKind.COMMON_DECL
        var lastElement = DemangleInfo()
        while (IsNotEndOfMangledName()) {
            typeKind = DemanglerTypeKind.COMMON_DECL
            if (mangledName[currentIndex] == b'L') {
                currentIndex++
                let lambdaIDString = UIntToString(DemangleManglingNumber())
                let j = i % MAX_ARGS_SIZE
                i++
                argsArr[j] = "lambda." + lambdaIDString
                typeKind = DemanglerTypeKind.LAMBDA_FUNCTION
                continue
            }
            if (mangledName[currentIndex] == b'X') {
                currentIndex++
                if (!IsQualifiedType()) {
                    return Reject("invalid mangling name")
                }
                let curDi = DemangleNextUnit("invalid mangling name")
                let j = i % MAX_ARGS_SIZE
                i++
                argsArr[j] = curDi.GetIdentifier()
                if (IsFileName()) {
                    DemangleFileName()
                }
                SkipLocalCounter()
                continue
            }
            var curDi: DemangleInfo
            if (IsOperatorName()) {
                curDi = DemangleInfo(GetOperatorNameMap(mangledName[currentIndex..currentIndex + MANGLE_SPECIAL_NAME_LEN]),
                    DemanglerTypeKind.NAME, isValid)
                currentIndex += MANGLE_SPECIAL_NAME_LEN
            } else {
                curDi = DemangleInfo(DemangleStringName(), DemanglerTypeKind.NAME, isValid)
                if (IsProp()) {
                    curDi.demangled += DemangleProp()
                }
            }
            if (currentIndex >= mangledName.size) {
                let j = i % MAX_ARGS_SIZE
                i++
                argsArr[j] = curDi.GetFullName(scopeResolution)
                break
            }
            SkipLocalCounter()
            if (!isValid) {
                return Reject("mangle name is invalid")
            }
            if (IsGeneric(mangledName[currentIndex])) {
                SkipChar(b'I')
                let generic = DemangleGenericTypes().GetFullName(scopeResolution)
                curDi.genericTypes = genericTypefilter(generic)
                if (!isClass) {
                    SkipOptionalChar(b'E')
                }
            }
            if (let Some(ch) <- PeekChar()) {
                if (IsFunction(ch)) {
                    SkipChar(b'H')
                    typeKind = DemanglerTypeKind.FUNCTION_DECL
                    let funcTys = DemangleFunctionParameterTypes().args
                    curDi.functionParameterTypes = funcTys
                    SkipOptionalChar(b'E')
                }
            }
            let j = i % MAX_ARGS_SIZE
            if (j == 0 && i != 0) {
                for (arg in argsArr) {
                    result += arg + delimiter
                }
                result = result[0..result.size - delimiter.size]
            }
            i++
            if (isParamInit && IsNotEndOfMangledName() && curDi.functionParameterTypes.size > 0) {
                argsArr[j] = curDi.GetFullName(scopeResolution) + LEFT_BRACKET + curDi.functionParameterTypes +
                    RIGHT_BRACKET
            } else {
                argsArr[j] = curDi.GetFullName(scopeResolution)
            }
            lastElement = curDi
        }
        let remainingLength = if (i == 0) { 0 } else { ((i - 1) % MAX_ARGS_SIZE) + 1 }
        result += GetArgTypesFullName(argsArr, remainingLength, delimiter)
        let resDi = DemangleInfo(result, typeKind, isValid)
        resDi.functionParameterTypes = lastElement.functionParameterTypes
        return resDi
    }

    private func DemangleClass(typeKind: DemanglerTypeKind): DemangleInfo {
        currentIndex++
        let di = DemangleCommonDecl(isClass: true)
        di.`type` = typeKind
        if (let Some(ch) <- PeekChar()) {
            if (ch == b'E') {
                SkipChar(b'E')
            }
        }
        return di
    }

    private func DemangleCFuncType(): DemangleInfo {
        SkipString(MANGLE_C_FUNCTY_PREFIX)
        let di = DemangleInfo(DemangleNextUnit().GetFullName(scopeResolution), DemanglerTypeKind.FUNCTION)
        di.args = DemangleArgTypes(ARGS_DELIMITER)
        SkipChar(b'E')
        return di
    }

    private func DemangleFunction(): DemangleInfo {
        SkipString(MANGLE_FUNCTY_PREFIX)
        let di = DemangleInfo(DemangleNextUnit().GetFullName(scopeResolution), DemanglerTypeKind.FUNCTION)
        di.args = DemangleArgTypes(ARGS_DELIMITER)
        SkipChar(b'E')
        return di
    }

    private func DemangleTuple(): DemangleInfo {
        let di = DemangleInfo(MANGLE_TUPLE_STR, DemanglerTypeKind.TUPLE)
        SkipChar(b'T')
        DemangleManglingNumber()
        let generic = DemangleGenericTypes().GetFullName(scopeResolution)
        di.genericTypes = genericTypefilter(generic)
        SkipChar(b'E')
        return di
    }

    private func DemangleRawArray(): DemangleInfo {
        let di = DemangleInfo(MANGLE_ARRAY_STR, DemanglerTypeKind.RAW_ARRAY)
        SkipChar(b'A')
        var dim = DemangleManglingNumber()
        while (dim > 0) {
            di.genericConstraints += "[]"
            dim--
        }
        di.args = DemangleNextUnit().GetFullName(scopeResolution)
        return di
    }

    private func DemangleVArray(): DemangleInfo {
        let di = DemangleInfo(MANGLE_VARRAY_STR, DemanglerTypeKind.TUPLE)
        SkipChar(b'V')
        let num = DemangleManglingNumber()
        di.genericTypes = DemangleGenericTypes().GetFullName(scopeResolution, num)
        return di
    }

    private func DemangleCPointer(): DemangleInfo {
        let di = DemangleInfo(MANGLE_PTR_STR, DemanglerTypeKind.CPOINTER)
        SkipChar(b'P')
        let generic = DemangleType().GetFullName(scopeResolution)
        di.genericTypes = genericTypefilter(generic)
        return di
    }

    private func DemangleCommonDecl(isClass!: Bool = false): DemangleInfo {
        var isGlobalVariableInitPrefix = false
        if (mangledName[currentIndex] == b'N') {
            SkipString(MANGLE_NESTED_PREFIX)
        } else {
            SkipString(GLOBAL_VARIABLE_INIT_PREFIX)
            isGlobalVariableInitPrefix = true
        }
        if (!isValid) {
            return Reject()
        }
        let di = DemangleInfo("", DemanglerTypeKind.COMMON_DECL)
        let pkgDi = DemanglePackageName()
        di.pkgName = pkgDi.pkgName
        di.isPrivateDeclaration = pkgDi.isPrivateDeclaration
        let nestedDi = DemangleNestedDecls(isClass: isClass)
        di.demangled = nestedDi.demangled
        di.`type` = nestedDi.`type`
        di.args = nestedDi.args
        if (!isValid || di.demangled.isEmpty()) {
            return Reject()
        }
        if (di.`type` == DemanglerTypeKind.FUNCTION_DECL) {
            di.args = nestedDi.functionParameterTypes
        }
        if (isGlobalVariableInitPrefix) {
            di.`type` = DemanglerTypeKind.COMMON_DECL
        }
        return di
    }

    private func DemangleDecl(): DemangleInfo {
        SkipString(MANGLE_CANGJIE_PREFIX)
        if (!isValid) {
            return Reject()
        }
        let di = DemangleCommonDecl()
        if (di.`type` == DemanglerTypeKind.LAMBDA_FUNCTION) {
            return di
        }
        if (!isValid || currentIndex >= mangledName.size) {
            return di
        }
        if (mangledName[currentIndex] == b'E') {
            return di
        }
        di.`type` = DemanglerTypeKind.FUNCTION_DECL
        di.args = DemangleArgTypes(ARGS_DELIMITER)
        if (!isValid) {
            return Reject()
        }
        if (IsMaybeDefaultFuncParamFunction()) {
            let dpf = DemangleDefaultParamFunction()
            if (!isValid) {
                return Reject()
            }
            di.demangled = di.GetFullName(scopeResolution) + scopeResolution + dpf.demangled
            di.args = dpf.args
        }
        return di
    }

    private func DemanglePrimitive(): DemangleInfo {
        if (currentIndex >= mangledName.size) {
            return Reject(ERROR_EXCEED_THE_INPUT_STRING_LENGTH)
        }
        let ch = mangledName[currentIndex]
        if (MatchForward(MANGLE_FLOAT16_PREFIX, MANGLE_FLOAT16_PREFIX.size)) {
            SkipString(MANGLE_FLOAT16_PREFIX)
        } else {
            SkipChar(ch)
        }
        return DemangleInfo(GetPrimitiveDemangleMap(ch), DemanglerTypeKind.PRIMITIVE)
    }

    private func DemangleCStringType(): DemangleInfo {
        SkipChar(b'k')
        return DemangleInfo(MANGLE_CSTRING_STR, DemanglerTypeKind.CSTRING, isValid)
    }

    private func DemangleGenericType(): DemangleInfo {
        SkipChar(b'G')
        let gNumber = DemangleManglingNumber()
        var name = ""
        if (genericVec.isEmpty()) {
            name = "T" + UIntToString(gNumber)
        } else {
            if (gNumber < genericVec.size) {
                name = genericVec[gNumber]
            } else {
                isValid = false
            }
        }
        return DemangleInfo(name, DemanglerTypeKind.GENERIC_TYPES, isValid)
    }

    private func DemangleType(): DemangleInfo {
        let di = DemangleInfo("", DemanglerTypeKind.GENERIC_TYPES)
        if (IsQualifiedType()) {
            let curDi = DemangleNextUnit()
            if (isValid) {
                di.args = curDi.GetFullName(scopeResolution)
                return di
            }
        }
        isValid = false
        return di
    }

    private func DemangleGenericTypes(): DemangleInfo {
        let di = DemangleInfo("", DemanglerTypeKind.GENERIC_TYPES)
        var firstIteration = true
        var argTypesFullName = ""
        while (IsNotEndOfMangledName() && !IsCurrentCharDigit(mangledName[currentIndex]) &&
            !IsFunction(mangledName[currentIndex]) && !IsOperatorName()) {
            let curDi = DemangleNextUnit()
            if (!isValid) {
                break
            }
            if (!firstIteration) {
                argTypesFullName += ARGS_DELIMITER_TYPE
            }
            argTypesFullName += curDi.GetFullName(scopeResolution)
            firstIteration = false
        }
        di.args = argTypesFullName
        return di
    }

    private func DemangleFunctionParameterTypes(): DemangleInfo {
        let di = DemangleInfo("", DemanglerTypeKind.FUNCTION_PARAMETER_TYPES)
        var firstIteration = true
        var argTypesFullName = ""
        if (IsNotEndOfMangledName() && mangledName[currentIndex] == b'v') {
            currentIndex += MANGLE_CHAR_LEN
        } else {
            while (IsNotEndOfMangledName() && !IsCurrentCharDigit(mangledName[currentIndex])) {
                let curDi = DemangleNextUnit()
                if (!isValid) {
                    break
                }
                if (!firstIteration) {
                    argTypesFullName += ARGS_DELIMITER
                }
                argTypesFullName += curDi.GetFullName(scopeResolution)
                firstIteration = false
            }
        }
        di.args = argTypesFullName
        return di
    }

    private func DemangleDefaultParamFunction(): DemangleInfo {
        let pos = mangledName.indexOf(MANGLE_WILDCARD_PREFIX, currentIndex) ?? -1
        if (pos == -1 || pos == mangledName.size - 1 || !IsCurrentCharDigit(mangledName[pos + MANGLE_CHAR_LEN])) {
            return Reject("invalid decl")
        }
        SkipChar(b'$')
        let identifier = mangledName[currentIndex..pos]
        let di = DemangleInfo(identifier, DemanglerTypeKind.FUNCTION_DECL)
        SkipString(identifier)
        SkipChar(b'_')
        DemangleLength()
        if (!IsNotEndOfMangledName()) {
            return Reject("invalid decl")
        }
        di.args = DemangleArgTypes(ARGS_DELIMITER)
        return di
    }

    private func DemangleInnerFunction(): DemangleInfo {
        let di = DemangleInfo("", DemanglerTypeKind.LAMBDA_FUNCTION)
        let prefixIndex = mangledName.indexOf(MANGLE_INNER_FUNCTION_PREFIX) ?? 0
        if (!isValid) {
            return Reject()
        }
        let pkgName = mangledName[currentIndex..prefixIndex]
        di.pkgName = pkgName
        let funcName = mangledName[prefixIndex + MANGLE_CHAR_LEN..]
        di.demangled = funcName
        currentIndex = mangledName.size
        return di
    }

    private func DemangleWrappedFunction(): DemangleInfo {
        let endIndex = mangledName.indexOf(MANGLE_DOLLAR_PREFIX, currentIndex) ?? mangledName.size
        let prefixIndex = currentIndex + MANGLE_WRAPPED_FUNCTION_PREFIX.size
        mangledName = MANGLE_CANGJIE_PREFIX + mangledName[prefixIndex..endIndex]
        let di = DemangleDecl()
        di.demangled += WRAPPED_FUNCTION_SUFFIX_INFO
        di.`type` = DemanglerTypeKind.WRAPPED_FUNCTION
        return di
    }

    private func Reject(): DemangleInfo {
        return Reject("")
    }

    private func Reject(reason: String): DemangleInfo {
        if (currentIndex == mangledName.size && !isValid) {
            return dumpDi
        }
        ErrorLog(reason)
        isValid = false
        currentIndex = mangledName.size
        return dumpDi
    }

    private func DemangleNextUnit(): DemangleInfo {
        return DemangleNextUnit("")
    }

    private func DemangleNextUnit(message: String): DemangleInfo {
        let di = DemangleByPrefix()
        if (!isValid) {
            return Reject("Demangle next token error: " + message)
        }
        return di
    }

    private func DemangleByPrefix(): DemangleInfo {
        if (currentIndex >= mangledName.size) {
            return Reject(ERROR_EXCEED_THE_INPUT_STRING_LENGTH)
        }
        let ch = mangledName[currentIndex]
        match (ch) {
            case b'C' => return DemangleClass(DemanglerTypeKind.CLASS)
            case b'R' => return DemangleClass(DemanglerTypeKind.STRUCT)
            case b'F' =>
                if (currentIndex + MANGLE_CHAR_LEN < mangledName.size) {
                    if (mangledName[currentIndex + MANGLE_CHAR_LEN] == b'0') {
                        return DemangleFunction()
                    } else if (mangledName[currentIndex + MANGLE_CHAR_LEN] == b'C') {
                        return DemangleCFuncType()
                    }
                }
            case b'N' => return DemangleClass(DemanglerTypeKind.ENUM)
            case b'T' => return DemangleTuple()
            case b'P' => return DemangleCPointer()
            case b'_' => ()
            case b'A' => return DemangleRawArray()
            case b'V' => return DemangleVArray()
            case b'k' => return DemangleCStringType()
            case b'G' => return DemangleGenericType()
            case _ =>
                if (IsCurrentCharDigit(ch)) {
                    return DemangleInfo(DemangleStringName(), DemanglerTypeKind.NAME, isValid)
                } else if (IsPrimitive(ch)) {
                    return DemanglePrimitive()
                } else if (IsOperatorName()) {
                    let di = DemangleInfo(GetOperatorNameMap(mangledName[currentIndex..currentIndex + MANGLE_SPECIAL_NAME_LEN]),
                        DemanglerTypeKind.NAME, isValid)
                    currentIndex += MANGLE_SPECIAL_NAME_LEN
                    return di
                }
        }
        return Reject("unexpected character")
    }
}
