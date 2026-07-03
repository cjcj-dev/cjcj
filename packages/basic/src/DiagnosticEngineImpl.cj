package cangjie_compiler::basic

import std.collection.*

public class DiagnosticEngineImpl {
    private var errorCount: UInt64 = 0
    private var warningCount: UInt64 = 0
    private var errorPrintCount: UInt64 = 0
    private var warningPrintCount: UInt64 = 0
    private var errorByCategory: Array<UInt64> = [0u64, 0u64, 0u64, 0u64, 0u64, 0u64, 0u64, 0u64, 0u64, 0u64]
    private var warningByCategory: Array<UInt64> = [0u64, 0u64, 0u64, 0u64, 0u64, 0u64, 0u64, 0u64, 0u64, 0u64]
    var disableDiagDeep: Int64 = 0
    var enableDiagnose: Bool = true
    private var disableWarning: Bool = false
    private var hardDisable: Bool = false
    private var handler: Option<DiagnosticHandler> = None
    private var maxNumOfDiags: Option<UInt64> = UInt64(DEFAULT_DIAG_NUM)
    let storedDiags: ArrayList<Diagnostic> = ArrayList<Diagnostic>()
    private var isEmitter: Bool = true
    private var isDumpErrCnt: Bool = true
    private var sourceManager: Option<SourceManager> = None
    private var isInTransaction: Bool = false
    private let transactionBuffer: ArrayList<Diagnostic> = ArrayList<Diagnostic>()
    private var checkRangeErrorCodeRatherICE: Bool = false
    private var diagEngineErrorCode: DiagEngineErrorCode = DiagEngineErrorCode.NO_ERRORS
    private var firstErrorCategory: Option<DiagCategory> = None
    private let pos2MacroCallDiagInfoMap: ArrayList<(UInt64, Option<MacroCallDiagInfo>)> =
        ArrayList<(UInt64, Option<MacroCallDiagInfo>)>()

    public init() {}

    ~init() {
        let activeHandler = handler.getOrThrow()
        if (IsCompilerDiagnosticHandlerKind(activeHandler.GetKind())) {
            if (activeHandler.IsJsonFormat()) {
                activeHandler.EmitDiagnosesInJson()
            }
        }
    }

    public func HasSourceManager(): Bool {
        if (let Some(_) <- sourceManager) {
            return true
        }
        return false
    }

    public func SetIsEmitter(emitter: Bool): Unit { isEmitter = emitter }
    public func SetDisableWarning(dis: Bool): Unit { disableWarning = dis }
    public func GetIsEmitter(): Bool { return isEmitter }
    public func SetIsDumpErrCnt(dump: Bool): Unit { isDumpErrCnt = dump }
    public func GetIsDumpErrCnt(): Bool { return isDumpErrCnt }
    public func SetSourceManager(sm: SourceManager): Unit { sourceManager = sm }

    public func GetSourceManager(): SourceManager {
        return sourceManager ?? throw IllegalStateException("sourceManager is null")
    }

    public func FirstErrorCategory(): Option<DiagCategory> {
        return firstErrorCategory
    }

    public func GetDisableDiagDeep(): Int64 {
        return disableDiagDeep
    }

    public func GetStoredDiags(): Array<Diagnostic> {
        return storedDiags.toArray()
    }

    public func SetStoredDiags(value: Array<Diagnostic>): Unit {
        storedDiags.clear()
        for (diagnostic in value) {
            storedDiags.add(diagnostic)
        }
    }

    public func GetEnableDiagnose(): Bool {
        return enableDiagnose
    }

    public func RegisterHandler(handler: DiagnosticHandler): Unit {
        this.handler = handler
    }

    public func IncreaseErrorCount(category: DiagCategory): Unit {
        let index = DiagCategoryIndex(category)
        if (firstErrorCategory == None || DiagCategoryIndex(firstErrorCategory ?? category) > index) {
            firstErrorCategory = category
        }
        errorByCategory[index] = errorByCategory[index] + 1
        IncreaseErrorCount()
    }

    public func IncreaseWarningCount(category: DiagCategory): Unit {
        let index = DiagCategoryIndex(category)
        warningByCategory[index] = warningByCategory[index] + 1
        warningCount++
    }

    public func IncreaseErrorCount(): Unit {
        errorCount++
    }

    public func GetWarningCount(): UInt64 {
        if (let Some(first) <- firstErrorCategory) {
            let last = DiagCategoryIndex(first)
            var idx: Int64 = 0
            var count: UInt64 = 0
            while (idx <= last) {
                count += warningByCategory[idx]
                idx++
            }
            return count
        }
        return warningCount
    }

    public func GetErrorCount(): UInt64 {
        if (let Some(first) <- firstErrorCategory) {
            return errorByCategory[DiagCategoryIndex(first)]
        }
        return 0
    }

    public func IncreaseWarningPrintCount(): Unit { warningPrintCount++ }
    public func GetWarningPrintCount(): UInt64 { return warningPrintCount }
    public func IncreaseErrorPrintCount(): Unit { errorPrintCount++ }
    public func GetErrorPrintCount(): UInt64 { return errorPrintCount }
    public func GetMaxNumOfDiags(): Option<UInt64> { return maxNumOfDiags }
    public func SetErrorCountLimit(errorCountLimit: Option<UInt64>): Unit { maxNumOfDiags = errorCountLimit }
    public func EnableCheckRangeErrorCodeRatherICE(): Unit { checkRangeErrorCodeRatherICE = true }
    public func DisableCheckRangeErrorCodeRatherICE(): Unit { checkRangeErrorCodeRatherICE = false }
    public func IsCheckRangeErrorCodeRatherICE(): Bool { return checkRangeErrorCodeRatherICE }
    public func SetDiagEngineErrorCode(errorCode: DiagEngineErrorCode): Unit { diagEngineErrorCode = errorCode }
    public func HardDisable(): Bool { return hardDisable }

    public func ConvertArgsToDiagMessage(diagnostic: Diagnostic): Unit {
        var formatStr = DiagMessages[DiagKindIndex(diagnostic.kind)]
        var index: Int64 = 0
        var formatPos = formatStr.indexOf("%")
        while (let Some(pos) <- formatPos) {
            if (index >= diagnostic.args.size) {
                break
            }
            if (pos + 1 >= formatStr.size) {
                return
            }
            let argStr = getArgStr(formatStr[pos + 1], diagnostic.args, index, diagnostic)
            if (!argStr.isEmpty()) {
                formatStr = formatStr[0..pos] + argStr + formatStr[pos + 2..]
                formatPos = formatStr.indexOf("%", pos + argStr.size)
            } else {
                formatPos = formatStr.indexOf("%", pos)
            }
            index++
        }
        diagnostic.diagMessage = formatStr
        for (note in diagnostic.notes) {
            ConvertArgsToDiagMessage(note)
        }
    }

    private func getArgStr(formatChar: UInt8, formatArgs: ArrayList<DiagArgument>, index: Int64, diagnostic: Diagnostic): String {
        let arg = formatArgs[index]
        if (formatChar == b'd') {
            if (arg.kind == DiagArgumentKind.INT) {
                return "${arg.intValue}"
            }
            Errorln("The num ${index}format parameter does not match")
            return ""
        }
        if (formatChar == b's') {
            if (arg.kind == DiagArgumentKind.STRING) {
                if (arg.stringValue.isEmpty()) {
                    diagnostic.kind = DEFAULT_KIND
                }
                return arg.stringValue
            }
            Errorln("The num ${index}format parameter does not match")
            return ""
        }
        if (formatChar == b'c') {
            if (arg.kind == DiagArgumentKind.CHAR) {
                return arg.stringValue
            }
            Errorln("The num ${index}format parameter does not match")
            return ""
        }
        if (formatChar == b'p') {
            if (arg.kind == DiagArgumentKind.POSITION) {
                let pos = arg.positionValue
                let path = GetSourceManager().GetSource(pos.fileID).path
                return path + ":" + "${pos.line}" + ":" + "${pos.column}"
            }
            Errorln("The num ${index}format parameter does not match")
            return ""
        }
        Errorln("%" + String.fromUtf8([formatChar]) + " is illegal format")
        return ""
    }

    public func HandleDiagnostic(diagnostic: Diagnostic): Unit {
        if (!enableDiagnose) {
            return
        }
        if (diagnostic.diagSeverity == DiagSeverity.DS_WARNING) {
            if (disableWarning || isWarningSuppressed(diagnostic.warnGroup) || IsSupressedUnusedMain(diagnostic)) {
                return
            }
            if (diagnostic.warnGroup != WarnGroup.UNGROUPED && diagnostic.warnGroup != WarnGroup.NONE) {
                let warnGroupName = warnGroupDescrs[WarnGroupIndex(diagnostic.warnGroup)]
                let msg = "this warning can be suppressed by setting the compiler option `-Woff " + warnGroupName + "`"
                diagnostic.subDiags.add(SubDiagnostic(msg))
            }
        }
        if (isInTransaction) {
            transactionBuffer.add(diagnostic)
            return
        }
        if (let Some(activeHandler) <- handler) {
            activeHandler.HandleDiagnose(diagnostic)
        }
    }

    public func IsSupressedUnusedMain(diagnostic: Diagnostic): Bool {
        return isWarningSuppressed(WarnGroup.UNUSED_MAIN) &&
            diagnostic.rKind == DiagKindRefactor.chir_dce_unused_function_main
    }

    private func isWarningSuppressed(group: WarnGroup): Bool {
        let index = WarnGroupIndex(group)
        if (index < 0) {
            return false
        }
        return WarningOptionMgr.GetInstance().IsSuppressed(UInt64(index))
    }

    public func Prepare(): Unit {
        isInTransaction = true
        transactionBuffer.clear()
    }

    public func Commit(): Unit {
        if (let Some(activeHandler) <- handler) {
            for (diagnostic in transactionBuffer) {
                activeHandler.HandleDiagnose(diagnostic)
            }
        }
        transactionBuffer.clear()
        isInTransaction = false
    }

    public func ClearTransaction(): Unit {
        transactionBuffer.clear()
        isInTransaction = false
    }

    public func EmitCategoryDiagnostics(cate: DiagCategory): Unit {
        if (let Some(activeHandler) <- handler) {
            activeHandler.EmitCategoryDiagnostics(cate)
        }
    }

    public func GetCategoryDiagnosticsString(cate: DiagCategory): (DiagEngineErrorCode, String) {
        if (let Some(activeHandler) <- handler) {
            if (diagEngineErrorCode != DiagEngineErrorCode.NO_ERRORS && checkRangeErrorCodeRatherICE) {
                return (diagEngineErrorCode, "")
            }
            activeHandler.SetOutToStringStream()
            activeHandler.EmitCategoryDiagnostics(cate)
            activeHandler.SetOutToErrStream()
            return (diagEngineErrorCode, activeHandler.GetOutString())
        }
        return (diagEngineErrorCode, "")
    }

    public func GetCategoryDiagnosticInfos(cate: DiagCategory): (DiagEngineErrorCode, Array<DiagnosticInfo>) {
        if (let Some(activeHandler) <- handler) {
            if (diagEngineErrorCode != DiagEngineErrorCode.NO_ERRORS && checkRangeErrorCodeRatherICE) {
                return (diagEngineErrorCode, Array<DiagnosticInfo>())
            }
            return (diagEngineErrorCode, activeHandler.EmitCategoryDiagnosticInfos(cate))
        }
        return (diagEngineErrorCode, Array<DiagnosticInfo>())
    }

    public func EmitCategoryGroup(): Unit {
        if (let Some(activeHandler) <- handler) {
            activeHandler.EmitDiagnoseGroup()
        }
    }

    public func GetCategoryDiagnostic(cate: DiagCategory): Array<Diagnostic> {
        if (let Some(activeHandler) <- handler) {
            return activeHandler.GetCategoryDiagnostic(cate)
        }
        return Array<Diagnostic>()
    }

    public func ClearError(): Unit {
        errorCount = 0
    }

    public func Reset(): Unit {
        errorCount = 0
        warningCount = 0
        errorByCategory = [0u64, 0u64, 0u64, 0u64, 0u64, 0u64, 0u64, 0u64, 0u64, 0u64]
        warningByCategory = [0u64, 0u64, 0u64, 0u64, 0u64, 0u64, 0u64, 0u64, 0u64, 0u64]
        firstErrorCategory = None
        if (let Some(activeHandler) <- handler) {
            activeHandler.Clear()
        }
    }

    public func SetDiagnoseStatus(enable: Bool): Unit {
        enableDiagnose = enable
        hardDisable = !enable
    }

    public func GetDiagnoseStatus(): Bool {
        return enableDiagnose
    }

    public func ReportErrorAndWarningCount(): Unit {
        if (!GetIsDumpErrCnt()) {
            return
        }
        if (let Some(activeHandler) <- handler) {
            if (IsCompilerDiagnosticHandlerKind(activeHandler.GetKind()) && activeHandler.IsJsonFormat()) {
                activeHandler.CacheTheCountInJsonFormat()
                activeHandler.EmitDiagnosesInJson()
                return
            }
        }
        if (GetErrorCount() > 0) {
            let count = GetErrorCount()
            WriteError("${count} error" + if (count > 1) { "s" } else { "" } +
                " generated, ${GetErrorPrintCount()} error" + if (GetErrorPrintCount() > 1) { "s" } else { "" } +
                " printed.\n")
        }
        if (GetWarningCount() > 0) {
            let count = GetWarningCount()
            WriteError("${count} warning" + if (count > 1) { "s" } else { "" } +
                " generated, ${GetWarningPrintCount()} warning" + if (GetWarningPrintCount() > 1) { "s" } else { "" } +
                " printed.\n")
        }
    }

    public func DiagFilter(diagnostic: Diagnostic): Bool {
        return diagnostic.GetDiagKind() < 0
    }

    public func DisableDiagnose(): Array<Diagnostic> {
        disableDiagDeep++
        if (disableDiagDeep > 0 && enableDiagnose) {
            enableDiagnose = false
        }
        return ConsumeStoredDiags()
    }

    public func EnableDiagnose(): Unit {
        if (disableDiagDeep > 0) {
            disableDiagDeep--
        }
        if (disableDiagDeep == 0 && !enableDiagnose) {
            enableDiagnose = true
            storedDiags.clear()
        }
    }

    public func EnableDiagnose(diags: Array<Diagnostic>): Unit {
        EnableDiagnose()
        SetStoredDiags(diags)
    }

    public func ConsumeStoredDiags(): Array<Diagnostic> {
        let ret = storedDiags.toArray()
        storedDiags.clear()
        return ret
    }

    private func CheckZeroRange(range: Range): Unit {
        if (checkRangeErrorCodeRatherICE) {
            if (range.begin.IsZero() || range.end.IsZero()) {
                diagEngineErrorCode = DiagEngineErrorCode.DIAG_RANGE_ERROR
                return
            }
        }
        if (range.begin.IsZero()) {
            throw IllegalStateException("begin of range is zero")
        }
        if (range.end.IsZero()) {
            throw IllegalStateException("end of range is zero")
        }
    }

    public func CheckRange(cate: DiagCategory, range: Range): Unit {
        if (!range.begin.IsZero() && !range.end.IsZero()) {
            return
        }
        if (cate == DiagCategory.LEX || cate == DiagCategory.PARSE) {
            CheckZeroRange(range)
            return
        }
        if (errorByCategory[DiagCategoryIndex(DiagCategory.LEX)] == 0 &&
            errorByCategory[DiagCategoryIndex(DiagCategory.PARSE)] == 0) {
            CheckZeroRange(range)
        }
    }

    public func AddMacroCallNote(diagnostic: Diagnostic, info: MacroCallDiagInfo, pos: Position): Unit {
        if (info.IsCustomAnnotation()) {
            return
        }
        diagnostic.macroDiagInfo = info
        let mcBegin = info.macroCallBegin
        let sevInfo = if (diagnostic.diagSeverity == DiagSeverity.DS_ERROR) { "the error" } else { "the warning" }
        if (info.isForLSP) {
            let idPosEnd = info.identifierPos + info.identifier.size
            diagnostic.subDiags.add(SubDiagnostic(MakeRange(mcBegin, idPosEnd),
                sevInfo + " occurs after the macro is expanded"))
            return
        }
        var originPos = INVALID_POSITION
        let key = if (info.isCurFile) { pos.Hash32() } else { UInt32(pos.column) }
        if (info.isCurFile) {
            if (let Some(mapped) <- info.originPosMap.get(key)) {
                originPos = mapped
            }
        } else if (let Some(mapped) <- info.new2originPosMap.get(pos.Hash32())) {
            if (mapped.isCurFile) {
                originPos = mapped
            }
        }
        if (originPos != INVALID_POSITION && originPos != diagnostic.start && originPos != diagnostic.mainHint.range.begin) {
            if (diagnostic.errorMessage.isEmpty()) {
                diagnostic.start = originPos
                diagnostic.end = originPos + 1
            }
            diagnostic.mainHint = IntegratedString(MakeRange(originPos, originPos + 1),
                diagnostic.mainHint.str, diagnostic.mainHint.color)
        }
        let message = sevInfo + " originates in the macro `" + info.fullName +
            "` (consider using `--debug-macro` for more info)"
        diagnostic.subDiags.add(SubDiagnostic(MakeRange(mcBegin, info.macroCallEnd), message), at: 0)
    }

    public func FindMacroCallInfo(pos: Position): Option<MacroCallDiagInfo> {
        let key = pos.Hash64()
        var lower: Option<MacroCallDiagInfo> = None
        var found = false
        var lowerKey: UInt64 = 0u64
        for ((entryKey, entryValue) in pos2MacroCallDiagInfoMap) {
            if (entryKey <= key && (!found || entryKey > lowerKey)) {
                found = true
                lowerKey = entryKey
                lower = entryValue
            }
        }
        return lower
    }

    public func RegisterMacroCallDiagInfo(info: MacroCallDiagInfo): Unit {
        let beginKey = info.macroCallBegin.Hash64()
        let endKey = info.macroCallEnd.Hash64()
        insertMacroInfo(beginKey, Some(info))
        if (endKey != beginKey) {
            insertMacroInfo(endKey, None)
        }
    }

    private func insertMacroInfo(key: UInt64, info: Option<MacroCallDiagInfo>): Unit {
        var idx: Int64 = 0
        while (idx < pos2MacroCallDiagInfoMap.size) {
            let current = pos2MacroCallDiagInfoMap[idx]
            if (current[0] == key) {
                pos2MacroCallDiagInfoMap.remove(at: idx)
                break
            }
            idx++
        }
        pos2MacroCallDiagInfoMap.add((key, info))
    }
}
