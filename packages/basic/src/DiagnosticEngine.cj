package cangjie_compiler::basic

import std.collection.*
import std.sort.*

public let MAIN_HINT_COLOR: DiagColor = DiagColor.RED
public let OTHER_HINT_COLOR: DiagColor = DiagColor.CYAN
public let NOTE_COLOR: DiagColor = DiagColor.BLUE
public let HELP_COLOR: DiagColor = DiagColor.GREEN
public let NO_COLOR: DiagColor = DiagColor.NO_COLOR
public let MACROCALL_CODE: String = "the code after the macro is expanded as follows"

public enum DiagArgumentKind {
    | INT
    | STRING
    | CHAR
    | POSITION
}

private let DIAG_INT_MODULUS: Int64 = 4294967296
private let DIAG_INT_SIGN_BIT: Int64 = 2147483648
private let DIAG_UINT_MASK: UInt64 = 0xffffffffu64
private let DIAG_UINT_SIGN_BIT: UInt64 = 0x80000000u64
private let DIAG_INT64_SIGN_BIT: UInt64 = 0x8000000000000000u64

private func NarrowDiagnosticInt(value: Int64): Int64 {
    var remainder = value % DIAG_INT_MODULUS
    if (remainder < 0) {
        remainder += DIAG_INT_MODULUS
    }
    if (remainder >= DIAG_INT_SIGN_BIT) {
        return remainder - DIAG_INT_MODULUS
    }
    return remainder
}

private func NarrowDiagnosticUInt(value: UInt64): Int64 {
    let lowBits = value & DIAG_UINT_MASK
    if (lowBits >= DIAG_UINT_SIGN_BIT) {
        return Int64(lowBits) - DIAG_INT_MODULUS
    }
    return Int64(lowBits)
}

private func SignedDiagnosticInt64Bits(value: Int64): UInt64 {
    if (value >= 0) {
        return UInt64(value)
    }
    return DIAG_INT64_SIGN_BIT + UInt64(value - Int64.Min)
}

private func DiagArgumentKindIndex(kind: DiagArgumentKind): Int64 {
    return match (kind) {
        case DiagArgumentKind.INT => 0
        case DiagArgumentKind.STRING => 1
        case DiagArgumentKind.CHAR => 2
        case DiagArgumentKind.POSITION => 3
    }
}

extend DiagArgumentKind <: Equatable<DiagArgumentKind> {
    public operator func ==(right: DiagArgumentKind): Bool {
        return DiagArgumentKindIndex(this) == DiagArgumentKindIndex(right)
    }

    public operator func !=(right: DiagArgumentKind): Bool {
        return !(this == right)
    }
}

public class DiagArgument {
    public let kind: DiagArgumentKind
    public let intValue: Int64
    public let stringValue: String
    public let positionValue: Position

    public init() {
        kind = DiagArgumentKind.INT
        intValue = 0
        stringValue = ""
        positionValue = DEFAULT_POSITION
    }

    public init(value: Int64) {
        kind = DiagArgumentKind.INT
        intValue = NarrowDiagnosticInt(value)
        stringValue = ""
        positionValue = DEFAULT_POSITION
    }

    public init(value: UInt64) {
        kind = DiagArgumentKind.INT
        intValue = NarrowDiagnosticUInt(value)
        stringValue = ""
        positionValue = DEFAULT_POSITION
    }

    public init(value: UInt8) {
        kind = DiagArgumentKind.CHAR
        intValue = 0
        stringValue = String.fromUtf8([value])
        positionValue = DEFAULT_POSITION
    }

    public init(value: String) {
        kind = DiagArgumentKind.STRING
        intValue = 0
        stringValue = value
        positionValue = DEFAULT_POSITION
    }

    public init(position: Position) {
        kind = DiagArgumentKind.POSITION
        intValue = 0
        stringValue = ""
        positionValue = position
    }
}

public func DiagCategoryIndex(category: DiagCategory): Int64 {
    return match (category) {
        case DiagCategory.LEX => 0
        case DiagCategory.PARSE => 1
        case DiagCategory.PARSE_QUERY => 2
        case DiagCategory.CONDITIONAL_COMPILATION => 3
        case DiagCategory.IMPORT_PACKAGE => 4
        case DiagCategory.MODULE => 5
        case DiagCategory.MACRO_EXPAND => 6
        case DiagCategory.SEMA => 7
        case DiagCategory.CHIR => 8
        case DiagCategory.OTHER => 9
    }
}

public struct Range <: Hashable & Equatable<Range> {
    public var begin: Position = DEFAULT_POSITION
    public var end: Position = DEFAULT_POSITION

    public init() {}

    public init(begin: Position, end: Position) {
        this.begin = begin
        this.end = end
    }

    public operator func ==(right: Range): Bool {
        return begin == right.begin && end == right.end
    }

    public operator func !=(right: Range): Bool {
        return !(this == right)
    }

    public func Hash(): UInt64 {
        return begin.fileID ^ (SignedDiagnosticInt64Bits(begin.line) << 8) ^
            (SignedDiagnosticInt64Bits(begin.column) << 16) ^ (begin.fileID << 24) ^
            (SignedDiagnosticInt64Bits(begin.line) << 32) ^ (SignedDiagnosticInt64Bits(begin.column) << 40)
    }

    public func EqualForHash(right: Range): Bool {
        return begin.fileID == right.begin.fileID && begin == right.begin && end == right.end
    }

    public func IsDefault(): Bool {
        return begin == DEFAULT_POSITION && end == DEFAULT_POSITION
    }

    public func HasZero(): Bool {
        return begin.IsZero() || end.IsZero()
    }

    public func hashCode(): Int64 {
        return Int64(Hash())
    }
}

public func MakeRange(begin: Position, end: Position): Range {
    var fixedEnd = end
    if (begin.fileID != end.fileID) {
        fixedEnd = begin + 1
    }
    return Range(begin, fixedEnd)
}

public func MakeRange(identifierPos: Position, identifier: String): Range {
    var index: Int64 = 0
    while (index < identifier.size) {
        if (identifier[index] > UInt8(0x7f)) {
            throw IllegalStateException("identifier character is not ASCII")
        }
        index++
    }
    return MakeRange(identifierPos, identifierPos + identifier.size)
}

public struct IntegratedString {
    public var range: Range = MakeRange(DEFAULT_POSITION, DEFAULT_POSITION)
    public var str: String = ""
    public var color: DiagColor = DiagColor.RESET

    public init() {}

    public init(range: Range, str: String, color: DiagColor) {
        this.range = range
        this.str = str
        this.color = color
    }

    public func IsDefault(): Bool {
        return range.begin == DEFAULT_POSITION && range.end == DEFAULT_POSITION
    }
}

public struct Substitution {
    public var range: Range = MakeRange(DEFAULT_POSITION, DEFAULT_POSITION)
    public var str: String = ""

    public init() {}

    public init(range: Range, str: String) {
        this.range = range
        this.str = str
    }
}

public class DiagHelp {
    public let substitutions: ArrayList<Substitution> = ArrayList<Substitution>()
    public var helpMes: String = ""

    public init() {}

    public init(helpMes: String) {
        this.helpMes = helpMes
    }

    public func AddSubstitution(pos: Position, str: String): Unit {
        substitutions.add(Substitution(MakeRange(pos, pos + 1), str))
    }

    public func AddSubstitution(range: Range, str: String): Unit {
        substitutions.add(Substitution(range, str))
    }

    public func AddSubstitution(tok: Token, str: String): Unit {
        substitutions.add(Substitution(MakeRange(tok.Begin(), tok.End()), str))
    }

    public func IsShowSource(): Bool {
        return !substitutions.isEmpty()
    }

    public func IsDefault(): Bool {
        return helpMes.isEmpty() && substitutions.isEmpty()
    }
}

public class SubDiagnostic {
    public var subDiagMessage: String
    public var mainHint: IntegratedString = IntegratedString()
    public let otherHints: ArrayList<IntegratedString> = ArrayList<IntegratedString>()
    public var help: DiagHelp = DiagHelp()

    public init(message: String) {
        subDiagMessage = message
    }

    public init(range: Range, message: String) {
        subDiagMessage = message
        mainHint = IntegratedString(range, "", NOTE_COLOR)
    }

    public func AddMainHint(range: Range, str: String): Unit {
        mainHint = IntegratedString(range, str, NOTE_COLOR)
    }

    public func AddHelp(help: DiagHelp): Unit {
        this.help = help
    }

    public func IsShowSource(): Bool {
        return !(mainHint.IsDefault() && otherHints.isEmpty())
    }
}

public class Diagnostic {
    public var start: Position = DEFAULT_POSITION
    public var end: Position = DEFAULT_POSITION
    public var kind: DiagKind = DEFAULT_KIND
    public var printSourceCode: Bool = true
    public var isRefactor: Bool = false
    public var isConvertedToRefactor: Bool = false
    public var rKind: DiagKindRefactor = DiagKindRefactor.lex_diag_begin
    public var errorMessage: String = ""
    public var mainHint: IntegratedString = IntegratedString()
    public let otherHints: ArrayList<IntegratedString> = ArrayList<IntegratedString>()
    public let subDiags: ArrayList<SubDiagnostic> = ArrayList<SubDiagnostic>()
    public let helps: ArrayList<DiagHelp> = ArrayList<DiagHelp>()
    public let args: ArrayList<DiagArgument> = ArrayList<DiagArgument>()
    public var diagSeverity: DiagSeverity = DiagSeverity.DS_ERROR
    public var diagMessage: String = ""
    public var diagCategory: DiagCategory = DiagCategory.SEMA
    public var warnGroup: WarnGroup = WarnGroup.NONE
    public let notes: ArrayList<Diagnostic> = ArrayList<Diagnostic>()
    public var macroDiagInfo: Option<MacroCallDiagInfo> = None
    public var isInMacroCall: Bool = false

    public init() {
        setLegacyMetadata(kind)
    }

    public init(start: Position, end: Position, kind: DiagKind, args!: Array<DiagArgument> = Array<DiagArgument>()) {
        this.start = start
        this.end = end
        this.kind = kind
        for (arg in args) {
            this.args.add(arg)
        }
        setLegacyMetadata(kind)
    }

    public init(refactor: Bool, range: Range, kind: DiagKindRefactor, arguments!: Array<String> = Array<String>()) {
        isRefactor = refactor
        rKind = kind
        let index = DiagKindRefactorIndex(kind)
        diagSeverity = rDiagSeveritys[index]
        warnGroup = rWarnGroups[index]
        let errData = errorData[index]
        errorMessage = Diagnostic.InsertArguments(errData.message, arguments)
        mainHint = IntegratedString(range, errData.mainHint, severityColor(diagSeverity))
        diagCategory = GetDiagnoseCategory(kind)
    }

    private func setLegacyMetadata(kind: DiagKind): Unit {
        let index = DiagKindIndex(kind)
        diagSeverity = DiagSeveritys[index]
        diagCategory = GetDiagnoseCategory(kind)
        warnGroup = warnGroups[index]
        rKind = DiagKindRefactor.parse_diag_begin
    }

    public func IsValid(): Bool {
        if (mainHint.range.HasZero()) {
            return false
        }
        for (subDiag in subDiags) {
            if (subDiag.mainHint.range.HasZero()) {
                return false
            }
        }
        return true
    }

    public func GetBegin(): Position {
        if (!start.IsZero()) {
            return start
        }
        return mainHint.range.begin
    }

    public func GetEnd(): Position {
        if (!end.IsZero()) {
            return end
        }
        return mainHint.range.end
    }

    public func GetErrorMessage(): String {
        if (!diagMessage.isEmpty()) {
            return diagMessage
        }
        return errorMessage
    }

    public func GetDiagCategory(): DiagCategory {
        return diagCategory
    }

    public func GetDiagKind(): Int64 {
        if (!start.IsZero()) {
            return DiagKindIndex(kind)
        }
        return DiagKindIndex(DiagKind.sema_diag_end) + DiagKindRefactorIndex(rKind)
    }

    public func HandleBadOtherHints(): Unit {
        var idx: Int64 = 0
        while (idx < otherHints.size) {
            if (otherHints[idx].range.begin.fileID == mainHint.range.begin.fileID) {
                idx++
            } else {
                subDiags.add(SubDiagnostic(otherHints[idx].range, otherHints[idx].str))
                otherHints.remove(at: idx)
            }
        }
    }

    public static func InsertArguments(rawString: String, arguments: Array<String>): String {
        if (rawString.isEmpty()) {
            return rawString
        }
        var result = rawString
        var index: Int64 = 0
        var formatPos = result.indexOf("%s")
        while (let Some(pos) <- formatPos) {
            if (index >= arguments.size) {
                throw IllegalStateException("diagnostic argument count does not match format placeholders")
            }
            let argument = arguments[index]
            result = result[0..pos] + argument + result[pos + 2..]
            index++
            formatPos = result.indexOf("%s", pos + argument.size)
        }
        if (index != arguments.size) {
            throw IllegalStateException("diagnostic argument count does not match format placeholders")
        }
        return result
    }
}

public class DiagnosticInfo {
    public var severity: DiagSeverity
    public var range: Range
    public var msg: String
    public var hint: String

    public init(
        severity: DiagSeverity,
        range!: Range = MakeRange(DEFAULT_POSITION, DEFAULT_POSITION),
        msg!: String = "",
        hint!: String = ""
    ) {
        this.severity = severity
        this.range = range
        this.msg = msg
        this.hint = hint
    }
}

public enum DiagHandlerKind {
    | HANDLER
    | COMPILER_HANDLER
    | LSP_HANDLER
}

public func IsCompilerDiagnosticHandlerKind(kind: DiagHandlerKind): Bool {
    return match (kind) {
        case DiagHandlerKind.COMPILER_HANDLER => true
        case _ => false
    }
}

public open class DiagnosticHandler {
    protected let diag: DiagnosticEngine
    private let kind: DiagHandlerKind
    private let prevDiags: ArrayList<(Position, String)> = ArrayList<(Position, String)>()

    public init(diag: DiagnosticEngine, kind: DiagHandlerKind) {
        this.diag = diag
        this.kind = kind
    }

    public open func HandleDiagnose(myDiag: Diagnostic): Unit {
        if (myDiag.GetDiagKind() < 0) {
            return
        }
    }

    public open func Clear(): Unit {
        prevDiags.clear()
    }

    public open func EmitCategoryDiagnostics(cate: DiagCategory): Unit {
        if (DiagCategoryIndex(cate) < 0) {
            return
        }
    }

    public open func EmitCategoryDiagnosticInfos(cate: DiagCategory): Array<DiagnosticInfo> {
        if (DiagCategoryIndex(cate) < 0) {
            return Array<DiagnosticInfo>()
        }
        return Array<DiagnosticInfo>()
    }

    public open func EmitDiagnoseGroup(): Unit {}

    public open func EmitDiagnosesInJson(): Unit {}

    public open func CacheTheCountInJsonFormat(): Unit {}

    public open func GetCategoryDiagnostic(cate: DiagCategory): Array<Diagnostic> {
        if (DiagCategoryIndex(cate) < 0) {
            return Array<Diagnostic>()
        }
        return Array<Diagnostic>()
    }

    public open func IsJsonFormat(): Bool {
        return false
    }

    public open func SetOutToStringStream(): Unit {}

    public open func SetOutToErrStream(): Unit {}

    public open func GetOutString(): String {
        return ""
    }

    public func SetPrevDiag(pos: Position, str: String): Unit {
        prevDiags.add((pos, str))
    }

    public func HasPrevDiag(pos: Position, str: String): Bool {
        for ((oldPos, oldStr) in prevDiags) {
            if (oldPos.fileID == pos.fileID && oldPos.line == pos.line && oldPos.column == pos.column && oldStr == str) {
                return true
            }
        }
        return false
    }

    public func GetKind(): DiagHandlerKind {
        return kind
    }
}

public class CompilerDiagnosticHandler <: DiagnosticHandler {
    private var noColor: Bool = false
    private var jsonFormat: Bool = false
    private let diagnostics: ArrayList<Diagnostic> = ArrayList<Diagnostic>()
    private let diagsJsonBuff: ArrayList<String> = ArrayList<String>()
    private var diagNumJsonBuff: String = ""
    private var outToStringStream: Bool = false
    private let strStream: StringBuilder = StringBuilder()

    public init(diag: DiagnosticEngine, noColor!: Bool = false, jsonFormat!: Bool = false) {
        super(diag, DiagHandlerKind.COMPILER_HANDLER)
        this.noColor = noColor
        this.jsonFormat = jsonFormat
    }

    public override func IsJsonFormat(): Bool {
        return jsonFormat
    }

    public override func SetOutToStringStream(): Unit {
        outToStringStream = true
    }

    public override func SetOutToErrStream(): Unit {
        outToStringStream = false
    }

    public override func GetOutString(): String {
        return strStream.toString()
    }

    public override func Clear(): Unit {
        super.Clear()
        diagnostics.clear()
        diagsJsonBuff.clear()
        diagNumJsonBuff = ""
    }

    public override func GetCategoryDiagnostic(cate: DiagCategory): Array<Diagnostic> {
        let list = ArrayList<Diagnostic>()
        for (diagnostic in diagnostics) {
            if (diagnostic.diagCategory == cate) {
                list.add(diagnostic)
            }
        }
        return list.toArray()
    }

    public func SaveCategoryDiagnostic(diagnostic: Diagnostic): Bool {
        for (oldDiag in diagnostics) {
            if (oldDiag.diagCategory == diagnostic.diagCategory &&
                oldDiag.mainHint.range.EqualForHash(diagnostic.mainHint.range) &&
                oldDiag.diagSeverity == diagnostic.diagSeverity) {
                return false
            }
        }
        diagnostics.add(diagnostic)
        return true
    }

    private func ShouldSaveDiagnosticCategory(category: DiagCategory): Bool {
        return match (category) {
            case DiagCategory.LEX | DiagCategory.PARSE | DiagCategory.CONDITIONAL_COMPILATION |
                DiagCategory.IMPORT_PACKAGE | DiagCategory.MODULE | DiagCategory.MACRO_EXPAND |
                DiagCategory.SEMA | DiagCategory.CHIR | DiagCategory.OTHER => true
            case _ => false
        }
    }

    public func SaveDiagnostics(diagnostic: Diagnostic): Bool {
        if (!ShouldSaveDiagnosticCategory(diagnostic.diagCategory)) {
            return true
        }
        return SaveCategoryDiagnostic(diagnostic)
    }

    public func CanBeEmitted(category: DiagCategory): Bool {
        if (let Some(first) <- diag.FirstErrorCategory()) {
            return DiagCategoryIndex(category) <= DiagCategoryIndex(first)
        }
        return true
    }

    public override func HandleDiagnose(myDiag: Diagnostic): Unit {
        var diagnostic = myDiag
        if (!diagnostic.isRefactor) {
            convertOldDiagToNew(diagnostic)
        }
        if (HasPrevDiag(diagnostic.mainHint.range.begin, diagnostic.errorMessage)) {
            return
        }
        SetPrevDiag(diagnostic.mainHint.range.begin, diagnostic.errorMessage)
        if (!diagnostic.mainHint.range.IsDefault()) {
            if (!jsonFormat) {
                diagnostic.HandleBadOtherHints()
            }
            if (!SaveDiagnostics(diagnostic)) {
                return
            }
        }
        if (!CanBeEmitted(diagnostic.diagCategory)) {
            return
        }
        if (diagnostic.diagSeverity == DiagSeverity.DS_ERROR) {
            diag.IncreaseErrorCount(diagnostic.diagCategory)
        } else if (diagnostic.diagSeverity == DiagSeverity.DS_WARNING) {
            diag.IncreaseWarningCount(diagnostic.diagCategory)
        }
        if (diagnostic.diagCategory == DiagCategory.LEX || diagnostic.diagCategory == DiagCategory.PARSE ||
            diagnostic.diagCategory == DiagCategory.CHIR) {
            return
        }
        EmitDiagnose(diagnostic)
    }

    public func EmitDiagnose(diagnostic: Diagnostic): Unit {
        if (!diag.GetIsEmitter()) {
            return
        }
        if (let Some(limit) <- diag.GetMaxNumOfDiags()) {
            if (diag.GetErrorPrintCount() >= limit) {
                return
            }
        }
        if (jsonFormat) {
            let formatter = DiagnosticJsonFormatter(diag)
            diagsJsonBuff.add(formatter.FormatDiagnosticToJson(diagnostic))
        } else {
            let sm = if (diag.HasSourceManager()) { diag.GetSourceManager() } else { SourceManager() }
            let emitter = DiagnosticEmitter(diagnostic, noColor, !diag.IsCheckRangeErrorCodeRatherICE(), sm)
            let rendered = emitter.Render()
            if (emitter.HasRangeError()) {
                diag.SetDiagEngineErrorCode(DiagEngineErrorCode.DIAG_RANGE_ERROR)
            }
            if (outToStringStream) {
                strStream.append(rendered)
            } else {
                WriteError(rendered)
            }
        }
        if (diagnostic.diagSeverity == DiagSeverity.DS_ERROR) {
            diag.IncreaseErrorPrintCount()
        } else {
            diag.IncreaseWarningPrintCount()
        }
    }

    public func GetDiagnosticInfo(diagnostic: Diagnostic): DiagnosticInfo {
        let hint = if (diag.HasSourceManager()) {
            let sm = diag.GetSourceManager()
            let emitter = DiagnosticEmitter(diagnostic, true, !diag.IsCheckRangeErrorCodeRatherICE(), sm)
            let rendered = emitter.Render(showSourceOnly: true)
            if (emitter.HasRangeError()) {
                diag.SetDiagEngineErrorCode(DiagEngineErrorCode.DIAG_RANGE_ERROR)
            }
            rendered
        } else {
            let sm = SourceManager()
            let emitter = DiagnosticEmitter(diagnostic, true, !diag.IsCheckRangeErrorCodeRatherICE(), sm)
            let rendered = emitter.Render()
            if (emitter.HasRangeError()) {
                diag.SetDiagEngineErrorCode(DiagEngineErrorCode.DIAG_RANGE_ERROR)
            }
            rendered
        }
        return DiagnosticInfo(diagnostic.diagSeverity, range: diagnostic.mainHint.range,
            msg: diagnostic.errorMessage, hint: hint)
    }

    private func sortedDiagnostics(category: DiagCategory): Array<Diagnostic> {
        let sorted = ArrayList<Diagnostic>()
        for (diagnostic in GetCategoryDiagnostic(category)) {
            sorted.add(diagnostic)
        }
        sort(sorted, by: { left: Diagnostic, right: Diagnostic =>
            let leftRange = left.mainHint.range
            let rightRange = right.mainHint.range
            if (leftRange.begin < rightRange.begin) {
                Ordering.LT
            } else if (rightRange.begin < leftRange.begin) {
                Ordering.GT
            } else if (leftRange.end < rightRange.end) {
                Ordering.LT
            } else if (rightRange.end < leftRange.end) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        }, stable: true)
        return sorted.toArray()
    }

    public override func EmitCategoryDiagnostics(cate: DiagCategory): Unit {
        if (!CanBeEmitted(cate)) {
            return
        }
        for (diagnostic in sortedDiagnostics(cate)) {
            EmitDiagnose(diagnostic)
        }
        removeCategory(cate)
    }

    public override func EmitCategoryDiagnosticInfos(cate: DiagCategory): Array<DiagnosticInfo> {
        let infos = ArrayList<DiagnosticInfo>()
        if (!CanBeEmitted(cate)) {
            return infos.toArray()
        }
        for (diagnostic in sortedDiagnostics(cate)) {
            infos.add(GetDiagnosticInfo(diagnostic))
        }
        removeCategory(cate)
        return infos.toArray()
    }

    public override func EmitDiagnoseGroup(): Unit {
        EmitCategoryDiagnostics(DiagCategory.LEX)
        if (diag.GetErrorPrintCount() == 0) {
            EmitCategoryDiagnostics(DiagCategory.PARSE)
        }
    }

    public override func CacheTheCountInJsonFormat(): Unit {
        let formatter = DiagnosticJsonFormatter(diag)
        diagNumJsonBuff = formatter.FormatDiagnosticCountToJsonString()
    }

    public override func EmitDiagnosesInJson(): Unit {
        if (!diag.GetIsEmitter()) {
            return
        }
        WriteError(DiagnosticJsonFormatter.AssembleDiagnosticJsonString(diagsJsonBuff.toArray(), diagNumJsonBuff))
    }

    private func removeCategory(cate: DiagCategory): Unit {
        var idx: Int64 = 0
        while (idx < diagnostics.size) {
            if (diagnostics[idx].diagCategory == cate) {
                diagnostics.remove(at: idx)
            } else {
                idx++
            }
        }
    }
}

public class DiagnosticBuilder <: Resource {
    public var diagnostic: Diagnostic
    public let diag: DiagnosticEngine
    private var emitted: Bool = false

    public init(diag: DiagnosticEngine, diagnostic: Diagnostic) {
        this.diag = diag
        this.diagnostic = diagnostic
    }

    public init(diag: DiagnosticEngine, diagnostic: Diagnostic, info: Option<MacroCallDiagInfo>) {
        this.diag = diag
        this.diagnostic = diagnostic
        if (let Some(diagInfo) <- info) {
            if (!diagInfo.IsCustomAnnotation()) {
                this.diagnostic.macroDiagInfo = diagInfo
            }
        }
    }

    public func AddNote(pos: Position, kind: DiagKind, args!: Array<DiagArgument> = Array<DiagArgument>()): Unit {
        let noteEnd = if (pos == DEFAULT_POSITION) { pos } else { pos + 1 }
        diagnostic.notes.add(Diagnostic(pos, noteEnd, kind, args: args))
    }

    public func AddHint(pos: Position, arguments!: Array<String> = Array<String>()): Unit {
        var finalPos = pos
        if (let Some(info) <- diagnostic.macroDiagInfo) {
            finalPos = info.MapPos(pos, isLowerBound: true)
        }
        AddHint(MakeRange(finalPos, finalPos + 1), arguments: arguments)
    }

    public func AddHint(range: Range, arguments!: Array<String> = Array<String>()): Unit {
        if (let Some(info) <- diagnostic.macroDiagInfo) {
            let newRange = MakeRange(info.MapPos(range.begin), info.MapPos(range.end, isLowerBound: true))
            AddHint(newRange, arguments: arguments)
            return
        }
        diag.CheckRange(diagnostic.GetDiagCategory(), range)
        let errData = errorData[DiagKindRefactorIndex(diagnostic.rKind)]
        if (diagnostic.otherHints.size >= errData.otherHints.size) {
            if (arguments.size > 1) {
                throw IllegalStateException("diagnostic argument count does not match format placeholders")
            }
            let text = if (arguments.isEmpty()) { "" } else { arguments[0] }
            diagnostic.otherHints.add(IntegratedString(range, text, OTHER_HINT_COLOR))
            return
        }
        let template = errData.otherHints[diagnostic.otherHints.size]
        let inserted = Diagnostic.InsertArguments(template, arguments)
        diagnostic.otherHints.add(IntegratedString(range, inserted, OTHER_HINT_COLOR))
    }

    public func AddHint(tok: Token, arguments!: Array<String> = Array<String>()): Unit {
        AddHint(MakeRange(tok.Begin(), tok.End()), arguments: arguments)
    }

    public func AddMainHintArguments(arguments: Array<String>): Unit {
        diagnostic.mainHint.str = Diagnostic.InsertArguments(diagnostic.mainHint.str, arguments)
    }

    public func AddNote(sub: SubDiagnostic): Unit {
        diag.CheckRange(diagnostic.GetDiagCategory(), sub.mainHint.range)
        for (hint in sub.otherHints) {
            diag.CheckRange(diagnostic.GetDiagCategory(), hint.range)
        }
        for (substitution in sub.help.substitutions) {
            diag.CheckRange(diagnostic.GetDiagCategory(), substitution.range)
        }
        diagnostic.subDiags.add(sub)
    }

    public func AddNote(range: Range, note: String): Unit {
        diag.CheckRange(diagnostic.GetDiagCategory(), range)
        AddNote(SubDiagnostic(range, note))
    }

    public func AddNote(note: String): Unit {
        AddNote(SubDiagnostic(note))
    }

    public func AddNote(pos: Position, note: String): Unit {
        let noteEnd = if (pos == DEFAULT_POSITION) { pos } else { pos + 1 }
        AddNote(MakeRange(pos, noteEnd), note)
    }

    public func AddHelp(help: DiagHelp): Unit {
        for (sub in help.substitutions) {
            diag.CheckRange(diagnostic.GetDiagCategory(), sub.range)
        }
        diagnostic.helps.add(help)
    }

    public func Emit(): Unit {
        if (emitted) {
            return
        }
        emitted = true
        if (!diag.GetEnableDiagnose()) {
            let consumed = diag.ConsumeStoredDiags()
            let storedDiags = ArrayList<Diagnostic>()
            for (storedDiag in consumed) {
                storedDiags.add(storedDiag)
            }
            storedDiags.add(diagnostic)
            diag.SetStoredDiags(storedDiags.toArray())
            return
        }
        if (!diagnostic.isRefactor) {
            diag.ConvertArgsToDiagMessage(diagnostic)
            if (diag.DiagFilter(diagnostic)) {
                return
            }
            if (diagnostic.kind == DEFAULT_KIND) {
                return
            }
        }
        if (diagnostic.isInMacroCall) {
            return
        }
        diag.HandleDiagnostic(diagnostic)
    }

    public func close(): Unit {
        Emit()
    }

    public func isClosed(): Bool {
        return emitted
    }
}

public class DiagnosticCache {
    public let cachedDiags: ArrayList<Diagnostic> = ArrayList<Diagnostic>()

    public init() {}

    public func ToExclude(diagBefore: DiagnosticEngine): Unit {
        cachedDiags.clear()
        for (diagnostic in diagBefore.GetStoredDiags()) {
            cachedDiags.add(diagnostic)
        }
    }

    public func BackUp(diagAfter: DiagnosticEngine): Unit {
        let storedDiags = diagAfter.GetStoredDiags()
        let oldSize = cachedDiags.size
        cachedDiags.clear()
        if (storedDiags.size > oldSize) {
            var idx = oldSize
            while (idx < storedDiags.size) {
                cachedDiags.add(storedDiags[idx])
                idx++
            }
        }
    }

    public func Restore(dst: DiagnosticEngine): Unit {
        let old = ArrayList<Diagnostic>()
        for (diagnostic in dst.ConsumeStoredDiags()) {
            old.add(diagnostic)
        }
        for (diagnostic in cachedDiags) {
            old.add(diagnostic)
        }
        dst.SetStoredDiags(old.toArray())
    }

    public func NoError(): Bool {
        for (diagnostic in cachedDiags) {
            if (diagnostic.diagSeverity == DiagSeverity.DS_ERROR) {
                return false
            }
        }
        return true
    }

    public static func ExtractKey(diag: DiagnosticEngine): Int64 {
        return if (diag.GetDisableDiagDeep() == 0) { 0 } else { 1 }
    }
}

public class StashDisableDiagnoseStatus <: Resource {
    private let engine: DiagnosticEngine
    private let enableDiagnose: Bool
    private let disableDiagDeep: Int64
    private let storedDiags: Array<Diagnostic>
    private let hasTargetType: Bool
    private var closed: Bool = false

    public init(engine: DiagnosticEngine, hasTargetType!: Bool = false) {
        this.engine = engine
        this.enableDiagnose = engine.impl.enableDiagnose
        this.disableDiagDeep = engine.impl.disableDiagDeep
        this.storedDiags = engine.impl.GetStoredDiags()
        this.hasTargetType = hasTargetType
        if (!hasTargetType) {
            engine.impl.enableDiagnose = true
            engine.impl.disableDiagDeep = 0
            engine.impl.storedDiags.clear()
        }
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        closed = true
        if (hasTargetType) {
            engine.impl.enableDiagnose = true
            engine.impl.disableDiagDeep = 0
            var idx: Int64 = 0
            while (idx < engine.impl.storedDiags.size) {
                if (engine.impl.storedDiags[idx].diagSeverity == DiagSeverity.DS_ERROR) {
                    engine.impl.storedDiags.remove(at: idx)
                } else {
                    idx++
                }
            }
            for (diagnostic in engine.impl.storedDiags) {
                let builder = engine.Diagnose(diagnostic)
                builder.Emit()
            }
        }
        engine.impl.enableDiagnose = enableDiagnose
        engine.impl.disableDiagDeep = disableDiagDeep
        engine.impl.SetStoredDiags(storedDiags)
    }

    public func isClosed(): Bool {
        return closed
    }
}

public enum DiagEngineErrorCode {
    | NO_ERRORS
    | DIAG_RANGE_ERROR
    | UNKNOWN
}

private func DiagEngineErrorCodeIndex(code: DiagEngineErrorCode): Int64 {
    return match (code) {
        case DiagEngineErrorCode.NO_ERRORS => 0
        case DiagEngineErrorCode.DIAG_RANGE_ERROR => 1
        case DiagEngineErrorCode.UNKNOWN => 2
    }
}

extend DiagEngineErrorCode <: Equatable<DiagEngineErrorCode> {
    public operator func ==(right: DiagEngineErrorCode): Bool {
        return DiagEngineErrorCodeIndex(this) == DiagEngineErrorCodeIndex(right)
    }

    public operator func !=(right: DiagEngineErrorCode): Bool {
        return !(this == right)
    }
}

private func severityColor(severity: DiagSeverity): DiagColor {
    return match (severity) {
        case DiagSeverity.DS_ERROR => DiagColor.RED
        case DiagSeverity.DS_WARNING => DiagColor.YELLOW
        case DiagSeverity.DS_NOTE => DiagColor.RED
        case DiagSeverity.DS_HINT => DiagColor.RED
    }
}

private func convertOldDiagToNew(diagnostic: Diagnostic): Unit {
    diagnostic.isConvertedToRefactor = true
    diagnostic.isRefactor = true
    diagnostic.errorMessage = diagnostic.diagMessage
    let first = diagnostic.start
    let second = if (diagnostic.end == DEFAULT_POSITION || diagnostic.end > diagnostic.start) {
        diagnostic.end
    } else {
        diagnostic.start + 1
    }
    diagnostic.mainHint = IntegratedString(MakeRange(first, second), "", severityColor(diagnostic.diagSeverity))
    for (note in diagnostic.notes) {
        let noteFirst = note.start
        let noteSecond = if (note.end == DEFAULT_POSITION || note.end > note.start) { note.end } else { note.start + 1 }
        diagnostic.subDiags.add(SubDiagnostic(MakeRange(noteFirst, noteSecond), note.diagMessage))
    }
    diagnostic.start = INVALID_POSITION
    diagnostic.end = INVALID_POSITION
    diagnostic.diagMessage = ""
    diagnostic.notes.clear()
    diagnostic.rKind = DiagKindRefactor.lex_diag_begin
}

public class DiagnosticEngine {
    let impl: DiagnosticEngineImpl = DiagnosticEngineImpl()
    public var ignoreScopeCheck: Bool = false

    public init() {
        RegisterHandler(DiagFormat.DEFAULT)
    }

    public func SetIsEmitter(emitter: Bool): Unit { impl.SetIsEmitter(emitter) }
    public func SetDisableWarning(dis: Bool): Unit { impl.SetDisableWarning(dis) }
    public func HasSourceManager(): Bool { return impl.HasSourceManager() }
    public func GetIsEmitter(): Bool { return impl.GetIsEmitter() }
    public func SetIsDumpErrCnt(dump: Bool): Unit { impl.SetIsDumpErrCnt(dump) }
    public func GetIsDumpErrCnt(): Bool { return impl.GetIsDumpErrCnt() }
    public func SetSourceManager(sm: SourceManager): Unit { impl.SetSourceManager(sm) }
    public func GetSourceManager(): SourceManager { return impl.GetSourceManager() }
    public func FirstErrorCategory(): Option<DiagCategory> { return impl.FirstErrorCategory() }
    public func GetDisableDiagDeep(): Int64 { return impl.GetDisableDiagDeep() }
    public func GetStoredDiags(): Array<Diagnostic> { return impl.GetStoredDiags() }
    public func SetStoredDiags(value: Array<Diagnostic>): Unit { impl.SetStoredDiags(value) }
    public func GetEnableDiagnose(): Bool { return impl.GetEnableDiagnose() }
    public func DisableDiagnose(): Array<Diagnostic> { return impl.DisableDiagnose() }
    public func EnableDiagnose(): Unit { impl.EnableDiagnose() }
    public func EnableDiagnose(diags: Array<Diagnostic>): Unit { impl.EnableDiagnose(diags) }
    public func ConsumeStoredDiags(): Array<Diagnostic> { return impl.ConsumeStoredDiags() }
    public func DiagFilter(diagnostic: Diagnostic): Bool { return impl.DiagFilter(diagnostic) }
    public func Prepare(): Unit { impl.Prepare() }
    public func Commit(): Unit { impl.Commit() }
    public func ClearTransaction(): Unit { impl.ClearTransaction() }
    public func EnableCheckRangeErrorCodeRatherICE(): Unit { impl.EnableCheckRangeErrorCodeRatherICE() }
    public func DisableCheckRangeErrorCodeRatherICE(): Unit { impl.DisableCheckRangeErrorCodeRatherICE() }
    public func IsCheckRangeErrorCodeRatherICE(): Bool { return impl.IsCheckRangeErrorCodeRatherICE() }
    public func SetDiagEngineErrorCode(errorCode: DiagEngineErrorCode): Unit { impl.SetDiagEngineErrorCode(errorCode) }
    public func RegisterHandler(handler: DiagnosticHandler): Unit { impl.RegisterHandler(handler) }
    public func RegisterHandler(format: DiagFormat): Unit {
        match (format) {
            case DiagFormat.JSON => RegisterHandler(CompilerDiagnosticHandler(this, noColor: true, jsonFormat: true))
            case DiagFormat.NO_COLOR => RegisterHandler(CompilerDiagnosticHandler(this, noColor: true))
            case DiagFormat.DEFAULT => RegisterHandler(CompilerDiagnosticHandler(this))
        }
    }
    public func IncreaseErrorCount(category: DiagCategory): Unit { impl.IncreaseErrorCount(category) }
    public func IncreaseWarningCount(category: DiagCategory): Unit { impl.IncreaseWarningCount(category) }
    public func IncreaseErrorCount(): Unit { impl.IncreaseErrorCount() }
    public func GetWarningCount(): UInt64 { return impl.GetWarningCount() }
    public func GetErrorCount(): UInt64 { return impl.GetErrorCount() }
    public func IncreaseWarningPrintCount(): Unit { impl.IncreaseWarningPrintCount() }
    public func GetWarningPrintCount(): UInt64 { return impl.GetWarningPrintCount() }
    public func IncreaseErrorPrintCount(): Unit { impl.IncreaseErrorPrintCount() }
    public func GetErrorPrintCount(): UInt64 { return impl.GetErrorPrintCount() }
    public func GetMaxNumOfDiags(): Option<UInt64> { return impl.GetMaxNumOfDiags() }
    public func HandleDiagnostic(diagnostic: Diagnostic): Unit { impl.HandleDiagnostic(diagnostic) }
    public func EmitCategoryDiagnostics(cate: DiagCategory): Unit { impl.EmitCategoryDiagnostics(cate) }
    public func GetCategoryDiagnosticsString(cate: DiagCategory): (DiagEngineErrorCode, String) {
        return impl.GetCategoryDiagnosticsString(cate)
    }
    public func GetCategoryDiagnosticInfos(cate: DiagCategory): (DiagEngineErrorCode, Array<DiagnosticInfo>) {
        return impl.GetCategoryDiagnosticInfos(cate)
    }
    public func EmitCategoryGroup(): Unit { impl.EmitCategoryGroup() }
    public func SetErrorCountLimit(errorCountLimit: Option<UInt64>): Unit { impl.SetErrorCountLimit(errorCountLimit) }
    public func GetCategoryDiagnostic(cate: DiagCategory): Array<Diagnostic> { return impl.GetCategoryDiagnostic(cate) }
    public func ClearError(): Unit { impl.ClearError() }
    public func Reset(): Unit { impl.Reset() }
    public func SetDiagnoseStatus(enable: Bool): Unit { impl.SetDiagnoseStatus(enable) }
    public func GetDiagnoseStatus(): Bool { return impl.GetDiagnoseStatus() }
    public func ReportErrorAndWarningCount(): Unit { impl.ReportErrorAndWarningCount() }
    public func DisableScopeCheck(): Unit { ignoreScopeCheck = true }
    public func HardDisable(): Bool { return impl.HardDisable() }
    public func CheckRange(cate: DiagCategory, range: Range): Unit { impl.CheckRange(cate, range) }
    public func AutoStashDisableDiagnoseStatus(hasTargetType!: Bool = false): StashDisableDiagnoseStatus {
        return StashDisableDiagnoseStatus(this, hasTargetType: hasTargetType)
    }

    public func Diagnose(
        start: Position,
        end: Position,
        kind: DiagKind,
        args!: Array<DiagArgument> = Array<DiagArgument>()
    ): DiagnosticBuilder {
        if (HardDisable()) {
            return DiagnosticBuilder(this, Diagnostic())
        }
        return DiagnosticBuilder(this, Diagnostic(start, end, kind, args: args))
    }

    public func Diagnose(pos: Position, kind: DiagKind, args!: Array<DiagArgument> = Array<DiagArgument>()): DiagnosticBuilder {
        return Diagnose(pos, pos + 1, kind, args: args)
    }

    public func Diagnose(kind: DiagKind, args!: Array<DiagArgument> = Array<DiagArgument>()): DiagnosticBuilder {
        if (HardDisable()) {
            return DiagnosticBuilder(this, Diagnostic())
        }
        return DiagnosticBuilder(this, Diagnostic(DEFAULT_POSITION, DEFAULT_POSITION, kind, args: args))
    }

    public func Diagnose(diagnostic: Diagnostic): DiagnosticBuilder {
        return DiagnosticBuilder(this, diagnostic)
    }

    public func DiagnoseRefactor(
        kind: DiagKindRefactor,
        pos: Position,
        arguments!: Array<String> = Array<String>()
    ): DiagnosticBuilder {
        if (let Some(info) <- FindMacroCallInfo(pos)) {
            return DiagnoseRefactor(kind, info, pos, formatArgs: arguments)
        }
        let range = MakeRange(pos, pos + 1)
        return DiagnosticBuilder(this, Diagnostic(true, range, kind, arguments: arguments))
    }

    public func DiagnoseRefactor(
        kind: DiagKindRefactor,
        range: Range,
        arguments!: Array<String> = Array<String>()
    ): DiagnosticBuilder {
        if (let Some(info) <- FindMacroCallInfo(range.begin)) {
            return DiagnoseRefactor(kind, info, range, formatArgs: arguments)
        }
        CheckRange(GetDiagnoseCategory(kind), range)
        return DiagnosticBuilder(this, Diagnostic(true, range, kind, arguments: arguments))
    }

    public func DiagnoseRefactor(
        kind: DiagKindRefactor,
        token: Token,
        arguments!: Array<String> = Array<String>()
    ): DiagnosticBuilder {
        return DiagnosticBuilder(this, Diagnostic(true, MakeRange(token.Begin(), token.End()), kind, arguments: arguments))
    }

    public func DiagnoseRefactor(
        kind: DiagKindRefactor,
        info: MacroCallDiagInfo,
        range: Range,
        formatArgs!: Array<String> = Array<String>()
    ): DiagnosticBuilder {
        let newRange = MakeRange(info.MapPos(range.begin), info.MapPos(range.end, isLowerBound: true))
        let diagnostic = Diagnostic(true, newRange, kind, arguments: formatArgs)
        impl.AddMacroCallNote(diagnostic, info, range.begin)
        return DiagnosticBuilder(this, diagnostic, Some(info))
    }

    public func DiagnoseRefactor(
        kind: DiagKindRefactor,
        info: MacroCallDiagInfo,
        pos: Position,
        formatArgs!: Array<String> = Array<String>()
    ): DiagnosticBuilder {
        let mapped = info.MapPos(pos)
        let diagnostic = Diagnostic(true, MakeRange(mapped, mapped + 1), kind, arguments: formatArgs)
        impl.AddMacroCallNote(diagnostic, info, pos)
        return DiagnosticBuilder(this, diagnostic, Some(info))
    }

    public func ConvertArgsToDiagMessage(diagnostic: Diagnostic): Unit { impl.ConvertArgsToDiagMessage(diagnostic) }
    public func AddMacroCallNote(diagnostic: Diagnostic, info: MacroCallDiagInfo, pos: Position): Unit {
        impl.AddMacroCallNote(diagnostic, info, pos)
    }
    public func FindMacroCallInfo(pos: Position): Option<MacroCallDiagInfo> { return impl.FindMacroCallInfo(pos) }
    public func RegisterMacroCallDiagInfo(info: MacroCallDiagInfo): Unit { impl.RegisterMacroCallDiagInfo(info) }
}
