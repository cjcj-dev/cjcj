package cangjie_compiler::basic

import std.collection.*

private let DIAG_JSON_DEEP: Int64 = 3
private let INDENT_WIDTH: Int64 = 4

private func jsonEscape(value: String): String {
    return StringConvertor.EscapeToJsonString(value)
}

private func jsonSeverity(severity: DiagSeverity): String {
    if (severity == DiagSeverity.DS_ERROR) {
        return "error"
    }
    return "warning"
}

private func jsonCategory(category: DiagCategory): String {
    return match (category) {
        case DiagCategory.LEX => "lex"
        case DiagCategory.PARSE => "parse"
        case DiagCategory.PARSE_QUERY => "parse_query"
        case DiagCategory.CONDITIONAL_COMPILATION => "conditional_compilation"
        case DiagCategory.IMPORT_PACKAGE => "import_package"
        case DiagCategory.MODULE => "module"
        case DiagCategory.MACRO_EXPAND => "macro_expand"
        case DiagCategory.SEMA => "sema"
        case DiagCategory.CHIR => "chir"
        case DiagCategory.OTHER => "other"
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

    public func FormatDiagnosticToJson(diagnostic: Diagnostic, deep!: Int64 = DIAG_JSON_DEEP): String {
        let builder = StringBuilder()
        builder.append(Whitespace(deep * INDENT_WIDTH) + "{\n")
        let nextDepth = deep + 1
        appendField(builder, nextDepth, "DiagKind", diagnosticName(diagnostic), comma: true)
        appendField(builder, nextDepth, "Severity", jsonSeverity(diagnostic.diagSeverity), comma: true)
        appendField(builder, nextDepth, "WarnGroup", jsonWarnGroup(diagnostic.warnGroup), comma: true)
        appendField(builder, nextDepth, "DiagCategory", jsonCategory(diagnostic.diagCategory), comma: true)
        builder.append(FormatDiagnosticMainContentJson(nextDepth, diagnostic))
        builder.append(",\n")
        builder.append(FormatDiagnosticNotesJson(nextDepth, diagnostic.subDiags))
        builder.append(",\n")
        builder.append(FormatDiagnosticHelpsJson(nextDepth, diagnostic.helps))
        builder.append("\n" + Whitespace(deep * INDENT_WIDTH) + "}")
        return builder.toString()
    }

    public func FormatDiagnosticCountToJsonString(): String {
        let builder = StringBuilder()
        builder.append(Whitespace(INDENT_WIDTH) + "\"Num\":{\n")
        let deep: Int64 = 2
        builder.append(Whitespace(deep * INDENT_WIDTH) + "\"Errors\": ${diag.GetErrorCount()},\n")
        builder.append(Whitespace(deep * INDENT_WIDTH) + "\"PrintedErrors\": ${diag.GetErrorPrintCount()},\n")
        builder.append(Whitespace(deep * INDENT_WIDTH) + "\"Warnings\": ${diag.GetWarningCount()},\n")
        builder.append(Whitespace(deep * INDENT_WIDTH) + "\"PrintedWarnings\": ${diag.GetWarningPrintCount()}\n")
        builder.append(Whitespace(INDENT_WIDTH) + "}")
        return builder.toString()
    }

    public static func AssembleDiagnosticJsonString(diagsJsonBuff: Array<String>, diagNumJsonBuff: String): String {
        if (diagsJsonBuff.isEmpty()) {
            return ""
        }
        let builder = StringBuilder()
        builder.append("{\n")
        builder.append(AssembleDiagnosticsJsonString(diagsJsonBuff))
        if (diagNumJsonBuff.isEmpty()) {
            builder.append("\n}\n")
        } else {
            builder.append(",\n" + diagNumJsonBuff + "\n}\n")
        }
        return builder.toString()
    }

    private static func Whitespace(num: Int64): String {
        return repeatString(" ", num)
    }

    private static func AssembleDiagnosticsJsonString(diagsJsonBuff: Array<String>): String {
        if (diagsJsonBuff.isEmpty()) {
            return "\"Diags\":[]"
        }
        let builder = StringBuilder()
        builder.append(Whitespace(INDENT_WIDTH) + "\"Diags\":[")
        var idx: Int64 = 0
        for (entry in diagsJsonBuff) {
            if (idx == 0) {
                builder.append("\n")
            } else {
                builder.append(",\n")
            }
            builder.append(entry)
            idx++
        }
        builder.append("\n" + Whitespace(INDENT_WIDTH) + "]")
        return builder.toString()
    }

    private func diagnosticName(diagnostic: Diagnostic): String {
        if (diagnostic.isRefactor && !diagnostic.isConvertedToRefactor) {
            return DiagKindRefactorName(diagnostic.rKind)
        }
        return DiagKindName(diagnostic.kind)
    }

    private static func appendField(
        builder: StringBuilder,
        deep: Int64,
        name: String,
        value: String,
        comma!: Bool = false
    ): Unit {
        builder.append(Whitespace(deep * INDENT_WIDTH) + "\"" + name + "\": \"" + jsonEscape(value) + "\"")
        if (comma) {
            builder.append(",\n")
        }
    }

    private func FormatPositionJson(deep: Int64, pos: Position): String {
        let builder = StringBuilder()
        var fileStr = "${pos.fileID}"
        if (diag.HasSourceManager() && diag.GetSourceManager().IsSourceFileExist(pos.fileID)) {
            let source = diag.GetSourceManager().GetSource(pos.fileID)
            if (let Some(pkgName) <- source.packageName) {
                fileStr = "(package " + pkgName + ")" + FileName(source.path)
            } else {
                fileStr = source.path
            }
        }
        builder.append(Whitespace(deep * INDENT_WIDTH) + "\"File\": \"" + jsonEscape(fileStr) + "\",\n")
        builder.append(Whitespace(deep * INDENT_WIDTH) + "\"Line\": ${pos.line},\n")
        builder.append(Whitespace(deep * INDENT_WIDTH) + "\"Column\": ${pos.column}")
        return builder.toString()
    }

    private func FormatRangeJson(deep: Int64, range: Range): String {
        let builder = StringBuilder()
        builder.append(Whitespace(deep * INDENT_WIDTH) + "\"Range\": {\n")
        let nextDepth = deep + 1
        builder.append(Whitespace(nextDepth * INDENT_WIDTH) + "\"Begin\": {\n")
        builder.append(FormatPositionJson(nextDepth + 1, range.begin) + "\n")
        builder.append(Whitespace(nextDepth * INDENT_WIDTH) + "},\n")
        builder.append(Whitespace(nextDepth * INDENT_WIDTH) + "\"End\": {\n")
        builder.append(FormatPositionJson(nextDepth + 1, range.end) + "\n")
        builder.append(Whitespace(nextDepth * INDENT_WIDTH) + "}\n")
        builder.append(Whitespace(deep * INDENT_WIDTH) + "}")
        return builder.toString()
    }

    private func FormatHintJson(deep: Int64, hint: IntegratedString, newLine!: Bool = true): String {
        let builder = StringBuilder()
        if (newLine) {
            builder.append(Whitespace(deep * INDENT_WIDTH))
        }
        builder.append("{\n")
        let nextDepth = deep + 1
        builder.append(Whitespace(nextDepth * INDENT_WIDTH) + "\"Content\": \"" + jsonEscape(hint.str) + "\",\n")
        builder.append(FormatRangeJson(nextDepth, hint.range) + "\n")
        builder.append(Whitespace(deep * INDENT_WIDTH) + "}")
        return builder.toString()
    }

    private func FormatHintsJson(deep: Int64, hints: ArrayList<IntegratedString>): String {
        if (hints.isEmpty()) {
            return "[]"
        }
        let builder = StringBuilder()
        builder.append("[\n")
        var idx: Int64 = 0
        for (hint in hints) {
            builder.append(FormatHintJson(deep + 1, hint))
            builder.append(if (idx == hints.size - 1) { "\n" } else { ",\n" })
            idx++
        }
        builder.append(Whitespace(deep * INDENT_WIDTH) + "]")
        return builder.toString()
    }

    private func FormatSubstitutionJson(deep: Int64, substitution: Substitution): String {
        let builder = StringBuilder()
        builder.append(Whitespace(deep * INDENT_WIDTH) + "{\n")
        let nextDepth = deep + 1
        builder.append(Whitespace(nextDepth * INDENT_WIDTH) + "\"Content\": \"" +
            jsonEscape(substitution.str) + "\",\n")
        builder.append(FormatRangeJson(nextDepth, substitution.range) + "\n")
        builder.append(Whitespace(deep * INDENT_WIDTH) + "}")
        return builder.toString()
    }

    private func FormatDiagnosticMainContentJson(deep: Int64, diagnostic: Diagnostic): String {
        let builder = StringBuilder()
        builder.append(Whitespace(deep * INDENT_WIDTH) + "\"Message\": \"" +
            jsonEscape(diagnostic.errorMessage) + "\",\n")
        builder.append(Whitespace(deep * INDENT_WIDTH) + "\"Location\": {\n")
        builder.append(FormatPositionJson(deep + 1, diagnostic.mainHint.range.begin) + "\n")
        builder.append(Whitespace(deep * INDENT_WIDTH) + "},\n")
        if (diagnostic.mainHint.IsDefault()) {
            builder.append(Whitespace(deep * INDENT_WIDTH) + "\"MainHint\": null,\n")
        } else {
            builder.append(Whitespace(deep * INDENT_WIDTH) + "\"MainHint\": ")
            builder.append(FormatHintJson(deep, diagnostic.mainHint, newLine: false) + ",\n")
        }
        builder.append(Whitespace(deep * INDENT_WIDTH) + "\"OtherHints\": " +
            FormatHintsJson(deep, diagnostic.otherHints))
        return builder.toString()
    }

    private func FormatDiagnosticDiagHelpJson(deep: Int64, help: DiagHelp, newLine!: Bool = true): String {
        let builder = StringBuilder()
        if (newLine) {
            builder.append(Whitespace(deep * INDENT_WIDTH))
        }
        builder.append("{\n")
        let nextDepth = deep + 1
        builder.append(Whitespace(nextDepth * INDENT_WIDTH) + "\"Message\": \"" + jsonEscape(help.helpMes) + "\",\n")
        builder.append(Whitespace(nextDepth * INDENT_WIDTH) + "\"Substitutions\": [")
        if (help.substitutions.isEmpty()) {
            builder.append("]")
        } else {
            builder.append("\n")
            var idx: Int64 = 0
            for (substitution in help.substitutions) {
                builder.append(FormatSubstitutionJson(nextDepth + 1, substitution))
                builder.append(if (idx == help.substitutions.size - 1) { "\n" } else { ",\n" })
                idx++
            }
            builder.append(Whitespace(nextDepth * INDENT_WIDTH) + "]")
        }
        builder.append("\n" + Whitespace(deep * INDENT_WIDTH) + "}")
        return builder.toString()
    }

    private func FormatDiagnosticSubDiagJson(deep: Int64, subDiag: SubDiagnostic): String {
        let builder = StringBuilder()
        builder.append(Whitespace(deep * INDENT_WIDTH) + "{\n")
        let nextDepth = deep + 1
        builder.append(Whitespace(nextDepth * INDENT_WIDTH) + "\"Message\": \"" +
            jsonEscape(subDiag.subDiagMessage) + "\",\n")
        if (subDiag.mainHint.IsDefault()) {
            builder.append(Whitespace(nextDepth * INDENT_WIDTH) + "\"MainHint\": null,\n")
        } else {
            builder.append(Whitespace(nextDepth * INDENT_WIDTH) + "\"MainHint\": ")
            builder.append(FormatHintJson(nextDepth, subDiag.mainHint, newLine: false) + ",\n")
        }
        builder.append(Whitespace(nextDepth * INDENT_WIDTH) + "\"OtherHints\": " +
            FormatHintsJson(nextDepth, subDiag.otherHints) + ",\n")
        if (subDiag.help.IsDefault()) {
            builder.append(Whitespace(nextDepth * INDENT_WIDTH) + "\"Help\": null")
        } else {
            builder.append(Whitespace(nextDepth * INDENT_WIDTH) + "\"Help\": ")
            builder.append(FormatDiagnosticDiagHelpJson(nextDepth, subDiag.help, newLine: false))
        }
        builder.append("\n" + Whitespace(deep * INDENT_WIDTH) + "}")
        return builder.toString()
    }

    private func FormatDiagnosticNotesJson(deep: Int64, subDiags: ArrayList<SubDiagnostic>): String {
        let builder = StringBuilder()
        builder.append(Whitespace(deep * INDENT_WIDTH) + "\"Notes\": [")
        if (subDiags.isEmpty()) {
            builder.append("]")
            return builder.toString()
        }
        builder.append("\n")
        var idx: Int64 = 0
        for (subDiag in subDiags) {
            builder.append(FormatDiagnosticSubDiagJson(deep + 1, subDiag))
            builder.append(if (idx == subDiags.size - 1) { "\n" } else { ",\n" })
            idx++
        }
        builder.append(Whitespace(deep * INDENT_WIDTH) + "]")
        return builder.toString()
    }

    private func FormatDiagnosticHelpsJson(deep: Int64, helps: ArrayList<DiagHelp>): String {
        let builder = StringBuilder()
        builder.append(Whitespace(deep * INDENT_WIDTH) + "\"Helps\": [")
        if (helps.isEmpty()) {
            builder.append("]")
            return builder.toString()
        }
        builder.append("\n")
        var idx: Int64 = 0
        for (help in helps) {
            builder.append(FormatDiagnosticDiagHelpJson(deep + 1, help))
            builder.append(if (idx == helps.size - 1) { "\n" } else { ",\n" })
            idx++
        }
        builder.append(Whitespace(deep * INDENT_WIDTH) + "]")
        return builder.toString()
    }
}
