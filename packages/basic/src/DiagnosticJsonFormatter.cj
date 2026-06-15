package cangjie_compiler::basic

private func jsonEscape(value: String): String {
    return StringConvertor.EscapeToJsonString(value)
}

private func jsonSeverity(severity: DiagSeverity): String {
    return match (severity) {
        case DiagSeverity.DS_ERROR => "error"
        case DiagSeverity.DS_WARNING => "warning"
        case DiagSeverity.DS_NOTE => "note"
        case DiagSeverity.DS_HINT => "hint"
    }
}

private func jsonWarnGroup(group: WarnGroup): String {
    if (group == WarnGroup.NONE) {
        return "none"
    }
    if (group == WarnGroup.UNGROUPED) {
        return "ungrouped"
    }
    let index = WarnGroupIndex(group)
    if (index >= 0 && index < warnGroupDescrs.size) {
        return warnGroupDescrs[index]
    }
    return "unknown"
}

public class DiagnosticJsonFormatter {
    private let diag: DiagnosticEngine

    public init(diag: DiagnosticEngine) {
        this.diag = diag
    }

    public func FormatDiagnosticToJson(diagnostic: Diagnostic): String {
        let builder = StringBuilder()
        builder.append("{")
        appendField(builder, "Severity", jsonSeverity(diagnostic.diagSeverity), comma: true)
        appendField(builder, "Message", diagnostic.errorMessage, comma: true)
        appendField(builder, "Category", "${DiagCategoryIndex(diagnostic.diagCategory)}", comma: true)
        appendField(builder, "WarnGroup", jsonWarnGroup(diagnostic.warnGroup), comma: true)
        builder.append("\"Range\": ")
        appendRange(builder, diagnostic.mainHint.range)
        builder.append(", \"Hints\": [")
        var hintIndex: Int64 = 0
        for (hint in diagnostic.otherHints) {
            if (hintIndex > 0) {
                builder.append(", ")
            }
            appendIntegratedString(builder, hint)
            hintIndex++
        }
        builder.append("], \"Notes\": [")
        var noteIndex: Int64 = 0
        for (note in diagnostic.subDiags) {
            if (noteIndex > 0) {
                builder.append(", ")
            }
            appendSubDiagnostic(builder, note)
            noteIndex++
        }
        builder.append("]}")
        return builder.toString()
    }

    public func FormatDiagnosticCountToJsonString(): String {
        return "\"ErrorCount\": ${diag.GetErrorCount()}, \"WarningCount\": ${diag.GetWarningCount()}"
    }

    public static func AssembleDiagnosticJsonString(diagsJsonBuff: Array<String>, diagNumJsonBuff: String): String {
        let builder = StringBuilder()
        builder.append("{\"Diagnostics\": [")
        var idx: Int64 = 0
        for (entry in diagsJsonBuff) {
            if (idx > 0) {
                builder.append(", ")
            }
            builder.append(entry)
            idx++
        }
        builder.append("]")
        if (!diagNumJsonBuff.isEmpty()) {
            builder.append(", " + diagNumJsonBuff)
        }
        builder.append("}\n")
        return builder.toString()
    }

    private static func appendField(builder: StringBuilder, name: String, value: String, comma!: Bool = false): Unit {
        builder.append("\"" + name + "\": \"" + jsonEscape(value) + "\"")
        if (comma) {
            builder.append(", ")
        }
    }

    private static func appendPosition(builder: StringBuilder, pos: Position): Unit {
        builder.append("{\"FileID\": ${pos.fileID}, \"Line\": ${pos.line}, \"Column\": ${pos.column}}")
    }

    private static func appendRange(builder: StringBuilder, range: Range): Unit {
        builder.append("{\"Begin\": ")
        appendPosition(builder, range.begin)
        builder.append(", \"End\": ")
        appendPosition(builder, range.end)
        builder.append("}")
    }

    private static func appendIntegratedString(builder: StringBuilder, hint: IntegratedString): Unit {
        builder.append("{\"Text\": \"" + jsonEscape(hint.str) + "\", \"Range\": ")
        appendRange(builder, hint.range)
        builder.append("}")
    }

    private static func appendSubDiagnostic(builder: StringBuilder, note: SubDiagnostic): Unit {
        builder.append("{\"Message\": \"" + jsonEscape(note.subDiagMessage) + "\", \"Range\": ")
        appendRange(builder, note.mainHint.range)
        builder.append("}")
    }

    // TODO(selfhost:Basic): match the C++ JSON schema byte-for-byte, including macro notes, help substitutions, and range-error fallback.
}
