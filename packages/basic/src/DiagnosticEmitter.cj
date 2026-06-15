package cangjie_compiler::basic

private func severityName(severity: DiagSeverity): String {
    return match (severity) {
        case DiagSeverity.DS_ERROR => "error"
        case DiagSeverity.DS_WARNING => "warning"
        case DiagSeverity.DS_NOTE => "note"
        case DiagSeverity.DS_HINT => "hint"
    }
}

private func emitterSeverityColor(severity: DiagSeverity): DiagColor {
    return match (severity) {
        case DiagSeverity.DS_ERROR => DiagColor.RED
        case DiagSeverity.DS_WARNING => DiagColor.YELLOW
        case DiagSeverity.DS_NOTE => DiagColor.BLUE
        case DiagSeverity.DS_HINT => DiagColor.GREEN
    }
}

private let LINE_SYMBOL: String = "==>"
private let SOURCE_GUTTER: String = "|"
private let WITHOUT_SOURCE_SYMBOL: String = "#"
private let MAIN_HINT_MARKER: String = "^"
private let OTHER_HINT_MARKER: String = "~"

private func colorForEmitter(noColor: Bool, color: DiagColor, text: String): String {
    if (noColor) {
        return text
    }
    return coloredString(color, text)
}

private func sourceDisplayName(source: Source): String {
    if (let Some(name) <- source.packageName) {
        return "(package " + name + ")" + FileName(source.path)
    }
    return if (source.path.isEmpty()) { "<unknown>" } else { source.path }
}

private func displayedRangeWidth(line: String, beginColumn: Int64, endColumn: Int64): Int64 {
    if (line.isEmpty()) {
        return 1
    }
    var start = beginColumn - 1
    var end = endColumn - 1
    if (start < 0) {
        start = 0
    }
    if (start > line.size) {
        start = line.size
    }
    if (end < start) {
        end = start
    }
    if (end > line.size) {
        end = line.size
    }
    let width = DisplayWidth(line[start..end])
    return if (width > 0) { width } else { 1 }
}

public class DiagnosticEmitter {
    private let diagnostic: Diagnostic
    private let noColor: Bool
    private let checkRange: Bool
    private let sourceManager: SourceManager

    public init(diagnostic: Diagnostic, noColor: Bool, checkRange: Bool, sourceManager: SourceManager) {
        this.diagnostic = diagnostic
        this.noColor = noColor
        this.checkRange = checkRange
        this.sourceManager = sourceManager
    }

    public func Emit(): Bool {
        WriteError(Render())
        return !hasRangeError()
    }

    public func Render(showSourceOnly!: Bool = false): String {
        let builder = StringBuilder()
        if (!showSourceOnly) {
            renderHeader(builder)
        }
        renderMainDiagnosticSource(builder)
        renderMacroExpansion(builder)
        for (subDiag in diagnostic.subDiags) {
            renderSubDiagnostic(builder, subDiag)
        }
        for (help in diagnostic.helps) {
            renderHelp(builder, help)
        }
        if (!diagnostic.mainHint.range.IsDefault()) {
            builder.append("\n")
        }
        return builder.toString()
    }

    private func renderHeader(builder: StringBuilder): Unit {
        let sev = severityName(diagnostic.diagSeverity)
        let headerColor = if (diagnostic.mainHint.color == DiagColor.RESET) {
            emitterSeverityColor(diagnostic.diagSeverity)
        } else {
            diagnostic.mainHint.color
        }
        let colored = colorForEmitter(noColor, headerColor, sev)
        builder.append(colored + ": " + diagnostic.errorMessage + "\n")
    }

    private func renderMainDiagnosticSource(builder: StringBuilder): Unit {
        if (diagnostic.mainHint.range.IsDefault()) {
            return
        }
        let width = lineNumberWidth()
        renderLocation(builder, diagnostic.mainHint.range.begin, width)
        renderGutterLine(builder, width)
        renderSourceLine(builder, diagnostic.mainHint.range, MAIN_HINT_MARKER, diagnostic.mainHint.str,
            diagnostic.mainHint.color, width)
        for (hint in diagnostic.otherHints) {
            renderHint(builder, hint, OTHER_HINT_MARKER, width)
        }
        renderGutterLine(builder, width)
    }

    private func renderSubDiagnostic(builder: StringBuilder, subDiag: SubDiagnostic): Unit {
        if (!subDiag.IsShowSource()) {
            if (!subDiag.subDiagMessage.isEmpty()) {
                renderMessageWithoutSource(builder, "note", subDiag.subDiagMessage)
            }
            return
        }
        let noteColor = if (!subDiag.mainHint.IsDefault()) { subDiag.mainHint.color } else { NOTE_COLOR }
        renderLabeledMessage(builder, "note", subDiag.subDiagMessage, noteColor)
        let width = lineNumberWidth()
        if (!subDiag.mainHint.IsDefault()) {
            renderLocation(builder, subDiag.mainHint.range.begin, width)
        } else if (!subDiag.otherHints.isEmpty()) {
            renderLocation(builder, subDiag.otherHints[0].range.begin, width)
        }
        renderGutterLine(builder, width)
        if (!subDiag.mainHint.IsDefault()) {
            renderSourceLine(builder, subDiag.mainHint.range, MAIN_HINT_MARKER, subDiag.mainHint.str,
                subDiag.mainHint.color, width)
        }
        for (hint in subDiag.otherHints) {
            renderHint(builder, hint, OTHER_HINT_MARKER, width)
        }
        renderGutterLine(builder, width)
        renderHelp(builder, subDiag.help)
    }

    private func renderHint(builder: StringBuilder, hint: IntegratedString, marker: String, width: Int64): Unit {
        if (hint.IsDefault()) {
            return
        }
        renderSourceLine(builder, hint.range, marker, hint.str, hint.color, width)
    }

    private func renderHelp(builder: StringBuilder, help: DiagHelp): Unit {
        if (help.IsDefault()) {
            return
        }
        if (!help.IsShowSource()) {
            if (!help.helpMes.isEmpty()) {
                renderMessageWithoutSource(builder, "help", help.helpMes)
            }
            return
        }
        renderLabeledMessage(builder, "help", help.helpMes + ":", HELP_COLOR)
        let width = lineNumberWidth()
        renderLocation(builder, help.substitutions[0].range.begin, width)
        renderGutterLine(builder, width)
        for (substitution in help.substitutions) {
            renderSourceLine(builder, substitution.range, OTHER_HINT_MARKER, substitution.str, HELP_COLOR, width)
        }
        renderGutterLine(builder, width)
    }

    private func renderLabeledMessage(builder: StringBuilder, label: String, message: String, color: DiagColor): Unit {
        builder.append(colorForEmitter(noColor, color, label) + ": " + message + "\n")
    }

    private func renderMessageWithoutSource(builder: StringBuilder, label: String, message: String): Unit {
        let width = lineNumberWidth()
        let prefix = repeatString(" ", width + 1)
        builder.append(prefix + colorForEmitter(noColor, OTHER_HINT_COLOR, WITHOUT_SOURCE_SYMBOL) + " " +
            label + ": " + message + "\n")
    }

    private func renderLocation(builder: StringBuilder, pos: Position, width: Int64): Unit {
        let source = sourceManager.GetSource(pos.fileID)
        let path = sourceDisplayName(source)
        builder.append(repeatString(" ", width) + colorForEmitter(noColor, OTHER_HINT_COLOR, LINE_SYMBOL) +
            " " + path + ":" + "${pos.line}" + ":" + "${pos.column}" + ":\n")
    }

    private func renderGutterLine(builder: StringBuilder, width: Int64): Unit {
        builder.append(emptyLinePrefix(width) + "\n")
    }

    private func renderSourceLine(
        builder: StringBuilder,
        range: Range,
        marker: String,
        hintText: String,
        color: DiagColor,
        width: Int64
    ): Unit {
        if (range.begin.line != range.end.line) {
            renderMultiLineSourceRange(builder, range, marker, hintText, color, width)
            return
        }
        renderSingleSourceLine(builder, range.begin.fileID, range.begin.line, range.begin.column, range.end.column,
            marker, hintText, color, width)
    }

    private func renderMultiLineSourceRange(
        builder: StringBuilder,
        range: Range,
        marker: String,
        hintText: String,
        color: DiagColor,
        width: Int64
    ): Unit {
        var lineNo = range.begin.line
        while (lineNo <= range.end.line) {
            let line = sourceLine(Position(range.begin.fileID, lineNo, 1))
            let startColumn = if (lineNo == range.begin.line) { range.begin.column } else { 1 }
            let endColumn = if (lineNo == range.end.line) { range.end.column } else { line.size + 1 }
            let text = if (lineNo == range.end.line) { hintText } else { "" }
            renderSingleSourceLine(builder, range.begin.fileID, lineNo, startColumn, endColumn, marker, text,
                color, width)
            lineNo++
        }
    }

    private func renderSingleSourceLine(
        builder: StringBuilder,
        fileID: UInt64,
        lineNumber: Int64,
        beginColumn: Int64,
        endColumn: Int64,
        marker: String,
        hintText: String,
        color: DiagColor,
        width: Int64
    ): Unit {
        let range = MakeRange(Position(fileID, lineNumber, beginColumn), Position(fileID, lineNumber, endColumn))
        let line = sourceLine(range.begin)
        if (line.isEmpty()) {
            return
        }
        let printableLine = printableSourceLine(line)
        builder.append(sourceLinePrefix(lineNumber, width) + printableLine + "\n")
        let before = if (beginColumn > 1) { GetSpaceBeforeTarget(line, beginColumn) } else { "" }
        let markerWidth = displayedRangeWidth(line, range.begin.column, range.end.column)
        var indicator = repeatString(marker, markerWidth)
        if (!hintText.isEmpty()) {
            indicator += " " + hintText
        }
        builder.append(emptyLinePrefix(width) + before + colorForEmitter(noColor, color, indicator) + "\n")
    }

    private func renderMacroExpansion(builder: StringBuilder): Unit {
        if (let Some(info) <- diagnostic.macroDiagInfo) {
            if (info.hasShownCode || info.mcBegin == DEFAULT_POSITION || info.mcEnd == DEFAULT_POSITION) {
                return
            }
            let content = sourceManager.GetContentBetween(info.mcBegin, info.mcEnd)
            if (content.isEmpty()) {
                return
            }
            info.hasShownCode = true
            let width = lineWidthForRange(MakeRange(info.mcBegin, info.mcEnd))
            renderLabeledMessage(builder, "note", MACROCALL_CODE, NOTE_COLOR)
            renderGutterLine(builder, width)
            var lineNo = info.mcBegin.line
            for (line in SplitLines(content)) {
                builder.append(sourceLinePrefix(lineNo, width) + printableSourceLine(line) + "\n")
                lineNo++
            }
            renderGutterLine(builder, width)
        }
    }

    private func sourceLine(pos: Position): String {
        let source = sourceManager.GetSource(pos.fileID)
        let lines = SplitLines(source.buffer)
        if (pos.line <= 0 || pos.line > lines.size) {
            return ""
        }
        return lines[pos.line - 1]
    }

    private func hasRangeError(): Bool {
        if (!checkRange) {
            return false
        }
        if (diagnostic.mainHint.range.HasZero()) {
            return true
        }
        for (hint in diagnostic.otherHints) {
            if (hint.range.HasZero()) {
                return true
            }
        }
        for (subDiag in diagnostic.subDiags) {
            if (!subDiag.mainHint.IsDefault() && subDiag.mainHint.range.HasZero()) {
                return true
            }
            for (hint in subDiag.otherHints) {
                if (hint.range.HasZero()) {
                    return true
                }
            }
        }
        for (help in diagnostic.helps) {
            for (substitution in help.substitutions) {
                if (substitution.range.HasZero()) {
                    return true
                }
            }
        }
        return false
    }

    private func lineNumberWidth(): Int64 {
        var maxLine: Int64 = 0
        maxLine = maxLineInRange(maxLine, diagnostic.mainHint.range)
        for (hint in diagnostic.otherHints) {
            maxLine = maxLineInRange(maxLine, hint.range)
        }
        for (subDiag in diagnostic.subDiags) {
            maxLine = maxLineInRange(maxLine, subDiag.mainHint.range)
            for (hint in subDiag.otherHints) {
                maxLine = maxLineInRange(maxLine, hint.range)
            }
            for (substitution in subDiag.help.substitutions) {
                maxLine = maxLineInRange(maxLine, substitution.range)
            }
        }
        for (help in diagnostic.helps) {
            for (substitution in help.substitutions) {
                maxLine = maxLineInRange(maxLine, substitution.range)
            }
        }
        if (maxLine <= 0) {
            return 0
        }
        return "${maxLine}".size
    }

    private func lineWidthForRange(range: Range): Int64 {
        let maxLine = if (range.end.line > range.begin.line) { range.end.line } else { range.begin.line }
        if (maxLine <= 0) {
            return 0
        }
        return "${maxLine}".size
    }

    private func maxLineInRange(current: Int64, range: Range): Int64 {
        if (range.IsDefault()) {
            return current
        }
        var result = current
        if (range.begin.line > result) {
            result = range.begin.line
        }
        if (range.end.line > result) {
            result = range.end.line
        }
        return result
    }

    private func sourceLinePrefix(lineNumber: Int64, width: Int64): String {
        let lineText = "${lineNumber}"
        let padding = repeatString(" ", width - lineText.size + 1)
        return colorForEmitter(noColor, OTHER_HINT_COLOR, lineText) + padding +
            colorForEmitter(noColor, OTHER_HINT_COLOR, SOURCE_GUTTER + " ")
    }

    private func emptyLinePrefix(width: Int64): String {
        return repeatString(" ", width + 1) + colorForEmitter(noColor, OTHER_HINT_COLOR, SOURCE_GUTTER + " ")
    }
}

private func printableSourceLine(line: String): String {
    let builder = StringBuilder()
    for (byte in line.toArray()) {
        if (byte == b'\t') {
            builder.append(repeatString(" ", HORIZONTAL_TAB_LEN))
        } else if (byte < 0x20u8 || byte == 0x7fu8) {
            builder.append(ConvertUnicode(Int64(byte)))
        } else {
            builder.append(String.fromUtf8([byte]))
        }
    }
    return builder.toString()
}
