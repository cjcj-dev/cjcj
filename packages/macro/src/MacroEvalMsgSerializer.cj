package cangjie_compiler::macro_pkg

import cangjie_compiler::basic.DiagCategory
import std.collection.*
import std.convert.*

public enum MacroMsgContent {
    | DEF_LIB
    | MULTI_CALLS
    | MACRO_RESULT
    | EXIT_TASK
    | NONE
}

private func MacroMsgContentIndex(kind: MacroMsgContent): Int64 {
    return match (kind) {
        case MacroMsgContent.DEF_LIB => 0
        case MacroMsgContent.MULTI_CALLS => 1
        case MacroMsgContent.MACRO_RESULT => 2
        case MacroMsgContent.EXIT_TASK => 3
        case MacroMsgContent.NONE => 4
    }
}

extend MacroMsgContent <: Equatable<MacroMsgContent> {
    public operator func ==(right: MacroMsgContent): Bool {
        return MacroMsgContentIndex(this) == MacroMsgContentIndex(right)
    }

    public operator func !=(right: MacroMsgContent): Bool {
        return !(this == right)
    }
}

private func escapeField(value: String): String {
    return value.replace("\\", "\\\\").replace("\n", "\\n").replace("|", "\\p").replace(",", "\\c").replace(";", "\\s").
        replace("#", "\\h")
}

private func unescapeField(value: String): String {
    return value.replace("\\h", "#").replace("\\s", ";").replace("\\c", ",").replace("\\p", "|").replace("\\n", "\n").
        replace("\\\\", "\\")
}

private func bytesToString(bytes: ArrayList<UInt8>): String {
    let raw = ArrayList<UInt8>()
    for (byte in bytes) {
        raw.add(byte)
    }
    return String.fromUtf8(raw.toArray())
}

private func stringToBytes(value: String, out: ArrayList<UInt8>): Unit {
    out.clear()
    for (byte in value.toArray()) {
        out.add(byte)
    }
}

private func hexDigit(value: UInt8): String {
    if (value < 10u8) {
        return String.fromUtf8([b'0' + value])
    }
    return String.fromUtf8([b'a' + (value - 10u8)])
}

private func bytesToHex(bytes: ArrayList<UInt8>): String {
    let builder = StringBuilder()
    for (byte in bytes) {
        builder.append(hexDigit((byte >> 4) & 0x0fu8))
        builder.append(hexDigit(byte & 0x0fu8))
    }
    return builder.toString()
}

private func nibble(byte: UInt8): UInt8 {
    if (byte >= b'0' && byte <= b'9') {
        return byte - b'0'
    }
    if (byte >= b'a' && byte <= b'f') {
        return byte - b'a' + 10u8
    }
    if (byte >= b'A' && byte <= b'F') {
        return byte - b'A' + 10u8
    }
    return 0u8
}

private func hexToBytes(value: String): ArrayList<UInt8> {
    let out = ArrayList<UInt8>()
    let bytes = value.toArray()
    var idx: Int64 = 0
    while (idx + 1 < bytes.size) {
        out.add((nibble(bytes[idx]) << 4) | nibble(bytes[idx + 1]))
        idx += 2
    }
    return out
}

private func encodePosition(pos: Position): String {
    return pos.fileID.toString() + "," + pos.line.toString() + "," + pos.column.toString()
}

private func decodePosition(value: String): Position {
    let parts = value.split(",")
    if (parts.size != 3) {
        return INVALID_POSITION
    }
    return Position(UInt64.parse(parts[0]), Int64.parse(parts[1]), Int64.parse(parts[2]))
}

private func encodeStringList(values: ArrayList<String>): String {
    let builder = StringBuilder()
    var idx: Int64 = 0
    while (idx < values.size) {
        if (idx > 0) {
            builder.append(",")
        }
        builder.append(escapeField(values[idx]))
        idx++
    }
    return builder.toString()
}

private func decodeStringList(value: String, out: ArrayList<String>): Unit {
    out.clear()
    if (value.isEmpty()) {
        return
    }
    for (part in value.split(",")) {
        out.add(unescapeField(part))
    }
}

private func encodeTokens(tokens: ArrayList<Token>): String {
    return bytesToHex(TokenSerialization.GetTokensBytes(tokens))
}

private func decodeTokens(value: String, out: ArrayList<Token>): Unit {
    out.clear()
    let decoded = TokenSerialization.GetTokensFromBytes(hexToBytes(value))
    for (token in decoded) {
        out.add(token)
    }
}

private func encodeItems(items: ArrayList<ItemInfo>): String {
    let builder = StringBuilder()
    var idx: Int64 = 0
    while (idx < items.size) {
        if (idx > 0) {
            builder.append(";")
        }
        let item = items[idx]
        builder.append(escapeField(item.key) + "," + ItemKindIndex(item.kind).toString() + ",")
        if (item.kind == ItemKind.STRING) {
            builder.append(escapeField(item.sValue))
        } else if (item.kind == ItemKind.INT) {
            builder.append(item.iValue.toString())
        } else if (item.kind == ItemKind.BOOL) {
            builder.append(if (item.bValue) { "1" } else { "0" })
        } else {
            builder.append(encodeTokens(item.tValue))
        }
        idx++
    }
    return builder.toString()
}

private func decodeItems(value: String, out: ArrayList<ItemInfo>): Unit {
    out.clear()
    if (value.isEmpty()) {
        return
    }
    for (segment in value.split(";")) {
        let fields = segment.split(",")
        if (fields.size < 3) {
            continue
        }
        let key = unescapeField(fields[0])
        let kindID = Int64.parse(fields[1])
        if (kindID == ItemKindIndex(ItemKind.STRING)) {
            out.add(ItemInfo(key, unescapeField(fields[2])))
        } else if (kindID == ItemKindIndex(ItemKind.INT)) {
            out.add(ItemInfo(key, Int64.parse(fields[2])))
        } else if (kindID == ItemKindIndex(ItemKind.BOOL)) {
            out.add(ItemInfo(key, fields[2] == "1"))
        } else if (kindID == ItemKindIndex(ItemKind.TKS)) {
            let tokens = ArrayList<Token>()
            decodeTokens(fields[2], tokens)
            out.add(ItemInfo(key, tokens))
        }
    }
}

private func diagSeverityIndex(value: DiagSeverity): Int64 {
    return match (value) {
        case DiagSeverity.DS_ERROR => 0
        case DiagSeverity.DS_WARNING => 1
        case DiagSeverity.DS_NOTE => 2
        case DiagSeverity.DS_HINT => 3
    }
}

private func diagSeverityFromIndex(value: Int64): DiagSeverity {
    return match (value) {
        case 0 => DiagSeverity.DS_ERROR
        case 1 => DiagSeverity.DS_WARNING
        case 2 => DiagSeverity.DS_NOTE
        case _ => DiagSeverity.DS_HINT
    }
}

private func diagnosticRange(diag: Diagnostic): Range {
    if (!diag.mainHint.range.IsDefault()) {
        return diag.mainHint.range
    }
    return Range(diag.GetBegin(), diag.GetEnd())
}

private func encodeDiagnostics(diags: ArrayList<Diagnostic>): String {
    let builder = StringBuilder()
    var idx: Int64 = 0
    while (idx < diags.size) {
        if (idx > 0) {
            builder.append(";")
        }
        let diag = diags[idx]
        let range = diagnosticRange(diag)
        builder.append(diagSeverityIndex(diag.diagSeverity).toString() + ",")
        builder.append(encodePosition(range.begin) + ",")
        builder.append(encodePosition(range.end) + ",")
        builder.append(escapeField(diag.GetErrorMessage()) + ",")
        builder.append(escapeField(diag.mainHint.str))
        idx++
    }
    return builder.toString()
}

private func diagnosticKindForSeverity(severity: DiagSeverity): DiagKindRefactor {
    if (severity == DiagSeverity.DS_WARNING) {
        return DiagKindRefactor.parse_diag_warning
    }
    return DiagKindRefactor.parse_diag_error
}

private func decodeDiagnostics(value: String, out: ArrayList<Diagnostic>): Unit {
    out.clear()
    if (value.isEmpty()) {
        return
    }
    for (segment in value.split(";")) {
        let fields = segment.split(",")
        if (fields.size < 9) {
            continue
        }
        let severity = diagSeverityFromIndex(Int64.parse(fields[0]))
        let begin = Position(UInt64.parse(fields[1]), Int64.parse(fields[2]), Int64.parse(fields[3]))
        let end = Position(UInt64.parse(fields[4]), Int64.parse(fields[5]), Int64.parse(fields[6]))
        let message = unescapeField(fields[7])
        let hint = unescapeField(fields[8])
        let diag = Diagnostic(true, Range(begin, end), diagnosticKindForSeverity(severity), arguments: [message])
        diag.start = begin
        diag.end = end
        diag.diagSeverity = severity
        diag.errorMessage = message
        diag.mainHint.str = hint
        out.add(diag)
    }
}

private func getCallDiagnostics(macCall: MacroCall): ArrayList<Diagnostic> {
    if (let Some(instance) <- macCall.ci) {
        let out = ArrayList<Diagnostic>()
        for (diag in instance.GetDiag().GetCategoryDiagnostic(DiagCategory.PARSE)) {
            out.add(diag)
        }
        return out
    }
    return ArrayList<Diagnostic>()
}

private func appendLine(builder: StringBuilder, key: String, value: String): Unit {
    builder.append(key + "|" + value + "\n")
}

private func lineValue(lines: Array<String>, key: String): Option<String> {
    for (line in lines) {
        if (line.startsWith(key + "|")) {
            return line[(key.size + 1)..]
        }
    }
    return None
}

private func createMacroCallMessage(macCall: MacroCall): String {
    let builder = StringBuilder()
    let invocation = macCall.RequireInvocation()
    let childMessages = ArrayList<ChildMessage>()
    CollectChildMessages(macCall, childMessages)
    appendLine(builder, "CALL_BEGIN", encodePosition(macCall.GetBeginPos()))
    appendLine(builder, "CALL_END", encodePosition(macCall.GetEndPos()))
    appendLine(builder, "ID", escapeField(invocation.macroCallDiagInfo.identifier))
    appendLine(builder, "ID_POS", encodePosition(invocation.macroCallDiagInfo.identifierPos))
    appendLine(builder, "FULL", escapeField(invocation.macroCallDiagInfo.fullName))
    appendLine(builder, "HAS_ATTR", if (invocation.hasAttr) { "1" } else { "0" })
    appendLine(builder, "ARGS", encodeTokens(invocation.args))
    appendLine(builder, "ATTRS", encodeTokens(invocation.attrs))
    appendLine(builder, "PARENTS", encodeStringList(macCall.parentNames))
    appendLine(builder, "CHILDREN", encodeChildMessages(childMessages))
    appendLine(builder, "METHOD", escapeField(macCall.methodName))
    appendLine(builder, "PACKAGE", escapeField(macCall.packageName))
    appendLine(builder, "LIB", escapeField(macCall.libPath))
    appendLine(builder, "CALL_DONE", "")
    return builder.toString()
}

public func CollectChildMessages(macCall: MacroCall, out: ArrayList<ChildMessage>): Unit {
    for (child in macCall.children) {
        if (!child.items.isEmpty()) {
            out.add(ChildMessage(child.GetFullName(), child.items))
        }
        CollectChildMessages(child, out)
    }
}

private func encodeChildMessages(messages: ArrayList<ChildMessage>): String {
    let builder = StringBuilder()
    var idx: Int64 = 0
    while (idx < messages.size) {
        if (idx > 0) {
            builder.append("#")
        }
        let message = messages[idx]
        builder.append(escapeField(message.childName) + "|" + encodeItems(message.items))
        idx++
    }
    return builder.toString()
}

private func decodeChildMessages(value: String, out: ArrayList<ChildMessage>): Unit {
    out.clear()
    if (value.isEmpty()) {
        return
    }
    for (segment in value.split("#")) {
        let fields = segment.split("|")
        if (fields.size < 2) {
            continue
        }
        let items = ArrayList<ItemInfo>()
        decodeItems(fields[1], items)
        out.add(ChildMessage(unescapeField(fields[0]), items))
    }
}

private func resultMessage(macCall: MacroCall): String {
    let builder = StringBuilder()
    let invocation = macCall.RequireInvocation()
    appendLine(builder, "TYPE", "RESULT")
    appendLine(builder, "ID", escapeField(invocation.macroCallDiagInfo.identifier))
    appendLine(builder, "ID_POS", encodePosition(invocation.macroCallDiagInfo.identifierPos))
    appendLine(builder, "STATUS", MacroEvalStatusIndex(macCall.status).toString())
    appendLine(builder, "TOKENS", encodeTokens(invocation.newTokens))
    appendLine(builder, "ITEMS", encodeItems(macCall.items))
    appendLine(builder, "ASSERT_PARENTS", encodeStringList(macCall.assertParents))
    appendLine(builder, "DIAGS", encodeDiagnostics(getCallDiagnostics(macCall)))
    return builder.toString()
}

private func statusFromIndex(value: Int64): MacroEvalStatus {
    return match (value) {
        case 0 => MacroEvalStatus.INIT
        case 1 => MacroEvalStatus.READY
        case 2 => MacroEvalStatus.EVAL
        case 3 => MacroEvalStatus.SUCCESS
        case 4 => MacroEvalStatus.FAIL
        case 5 => MacroEvalStatus.REEVAL
        case 6 => MacroEvalStatus.FINISH
        case 7 => MacroEvalStatus.ANNOTATION
        case _ => MacroEvalStatus.REEVALFAILED
    }
}

public class MacroEvalMsgSerializer {
    public init() {}

    public func SerializeDeflibMsg(macrolibs: ArrayList<String>, bufferData: ArrayList<UInt8>): Unit {
        let builder = StringBuilder()
        appendLine(builder, "TYPE", "DEF")
        appendLine(builder, "PATHS", encodeStringList(macrolibs))
        stringToBytes(builder.toString(), bufferData)
    }

    public func SerializeMacroCallMsg(macCall: MacroCall, bufferData: ArrayList<UInt8>): Unit {
        let builder = StringBuilder()
        appendLine(builder, "TYPE", "CALLS")
        appendLine(builder, "COUNT", "1")
        builder.append(createMacroCallMessage(macCall))
        stringToBytes(builder.toString(), bufferData)
    }

    public func SerializeMultiCallsMsg(macCalls: ArrayList<MacroCall>, bufferData: ArrayList<UInt8>): Unit {
        let builder = StringBuilder()
        appendLine(builder, "TYPE", "CALLS")
        appendLine(builder, "COUNT", macCalls.size.toString())
        for (call in macCalls) {
            builder.append(createMacroCallMessage(call))
        }
        stringToBytes(builder.toString(), bufferData)
    }

    public func SerializeMacroCallResultMsg(macCall: MacroCall, bufferData: ArrayList<UInt8>): Bool {
        stringToBytes(resultMessage(macCall), bufferData)
        return macCall.GetInvocation().isSome()
    }

    public func SerializeExitMsg(bufferData: ArrayList<UInt8>, flag!: Bool = true): Unit {
        let builder = StringBuilder()
        appendLine(builder, "TYPE", "EXIT")
        appendLine(builder, "FLAG", if (flag) { "1" } else { "0" })
        stringToBytes(builder.toString(), bufferData)
    }

    public static func GetExitFlag(bufferData: ArrayList<UInt8>): Bool {
        let lines = bytesToString(bufferData).split("\n")
        if (let Some(value) <- lineValue(lines, "FLAG")) {
            return value == "1"
        }
        return true
    }

    public static func GetMacroMsgContenType(bufferData: ArrayList<UInt8>): MacroMsgContent {
        let text = bytesToString(bufferData)
        let lines = text.split("\n")
        if (let Some(value) <- lineValue(lines, "TYPE")) {
            if (value == "DEF") {
                return MacroMsgContent.DEF_LIB
            }
            if (value == "CALLS") {
                return MacroMsgContent.MULTI_CALLS
            }
            if (value == "RESULT") {
                return MacroMsgContent.MACRO_RESULT
            }
            if (value == "EXIT") {
                return MacroMsgContent.EXIT_TASK
            }
        }
        return MacroMsgContent.NONE
    }

    public static func DeSerializeDeflibMsg(macroLibs: ArrayList<String>, bufferData: ArrayList<UInt8>): Unit {
        let lines = bytesToString(bufferData).split("\n")
        if (let Some(value) <- lineValue(lines, "PATHS")) {
            decodeStringList(value, macroLibs)
        }
    }

    public static func DeSerializeMacroCallMessages(bufferData: ArrayList<UInt8>, calls: ArrayList<String>): Unit {
        calls.clear()
        var currentBlock = ""
        var inCall = false
        for (line in bytesToString(bufferData).split("\n")) {
            if (line.startsWith("CALL_BEGIN|")) {
                currentBlock = ""
                inCall = true
            }
            if (inCall) {
                currentBlock += line + "\n"
            }
            if (line.startsWith("CALL_DONE|") && inCall) {
                calls.add(currentBlock)
                inCall = false
            }
        }
    }

    public static func DeSerializeRangeFromCall(begin: Box<Position>, end: Box<Position>, text: String): Unit {
        let lines = text.split("\n")
        if (let Some(value) <- lineValue(lines, "CALL_BEGIN")) {
            begin.value = decodePosition(value)
        }
        if (let Some(value) <- lineValue(lines, "CALL_END")) {
            end.value = decodePosition(value)
        }
    }

    public static func DeSerializeIdInfoFromCall(id: Box<String>, pos: Box<Position>, text: String): Unit {
        let lines = text.split("\n")
        if (let Some(value) <- lineValue(lines, "ID")) {
            id.value = unescapeField(value)
        }
        if (let Some(value) <- lineValue(lines, "ID_POS")) {
            pos.value = decodePosition(value)
        }
    }

    public static func DeSerializeArgsFromCall(args: ArrayList<Token>, text: String): Unit {
        let lines = text.split("\n")
        if (let Some(value) <- lineValue(lines, "ARGS")) {
            decodeTokens(value, args)
        }
    }

    public static func DeSerializeAttrsFromCall(attrs: ArrayList<Token>, text: String): Unit {
        let lines = text.split("\n")
        if (let Some(value) <- lineValue(lines, "ATTRS")) {
            decodeTokens(value, attrs)
        }
    }

    public static func DeSerializeParentNamesFromCall(parentNames: ArrayList<String>, text: String): Unit {
        let lines = text.split("\n")
        if (let Some(value) <- lineValue(lines, "PARENTS")) {
            decodeStringList(value, parentNames)
        }
    }

    public static func DeSerializeFullNameFromCall(fullName: Box<String>, text: String): Unit {
        let lines = text.split("\n")
        if (let Some(value) <- lineValue(lines, "FULL")) {
            fullName.value = unescapeField(value)
        }
    }

    public static func DeSerializeHasAttrFromCall(text: String): Bool {
        let lines = text.split("\n")
        if (let Some(value) <- lineValue(lines, "HAS_ATTR")) {
            return value == "1"
        }
        return false
    }

    public static func DeSerializeMethodInfoFromCall(methodName: Box<String>, packageName: Box<String>,
        libPath: Box<String>, text: String): Unit {
        let lines = text.split("\n")
        if (let Some(value) <- lineValue(lines, "METHOD")) {
            methodName.value = unescapeField(value)
        }
        if (let Some(value) <- lineValue(lines, "PACKAGE")) {
            packageName.value = unescapeField(value)
        }
        if (let Some(value) <- lineValue(lines, "LIB")) {
            libPath.value = unescapeField(value)
        }
    }

    public static func DeSerializeChildMsgesFromCall(childMsges: ArrayList<ChildMessage>, text: String): Unit {
        let lines = text.split("\n")
        if (let Some(value) <- lineValue(lines, "CHILDREN")) {
            decodeChildMessages(value, childMsges)
        }
    }

    public static func DeSerializeIdInfoFromResult(id: Box<String>, pos: Box<Position>, bufferData: ArrayList<UInt8>): Unit {
        let lines = bytesToString(bufferData).split("\n")
        if (let Some(value) <- lineValue(lines, "ID")) {
            id.value = unescapeField(value)
        }
        if (let Some(value) <- lineValue(lines, "ID_POS")) {
            pos.value = decodePosition(value)
        }
    }

    public static func DeSerializeTksFromResult(tks: ArrayList<Token>, bufferData: ArrayList<UInt8>): Unit {
        let lines = bytesToString(bufferData).split("\n")
        if (let Some(value) <- lineValue(lines, "TOKENS")) {
            decodeTokens(value, tks)
        }
    }

    public static func DeSerializeStatusFromResult(bufferData: ArrayList<UInt8>): MacroEvalStatus {
        let lines = bytesToString(bufferData).split("\n")
        if (let Some(value) <- lineValue(lines, "STATUS")) {
            return statusFromIndex(Int64.parse(value))
        }
        return MacroEvalStatus.REEVALFAILED
    }

    public static func DeSerializeItemsFromResult(items: ArrayList<ItemInfo>, bufferData: ArrayList<UInt8>): Unit {
        let lines = bytesToString(bufferData).split("\n")
        if (let Some(value) <- lineValue(lines, "ITEMS")) {
            decodeItems(value, items)
        }
    }

    public static func DeSerializeAssertParentsFromResult(assertParents: ArrayList<String>, bufferData: ArrayList<UInt8>): Unit {
        let lines = bytesToString(bufferData).split("\n")
        if (let Some(value) <- lineValue(lines, "ASSERT_PARENTS")) {
            decodeStringList(value, assertParents)
        }
    }

    public static func DeSerializeDiagsFromResult(diags: ArrayList<Diagnostic>, bufferData: ArrayList<UInt8>): Unit {
        diags.clear()
        let lines = bytesToString(bufferData).split("\n")
        if (let Some(value) <- lineValue(lines, "DIAGS")) {
            decodeDiagnostics(value, diags)
        }
    }
}
