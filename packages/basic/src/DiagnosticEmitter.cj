package cangjie_compiler::basic

import std.collection.*

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
private let COMPRESS_LEN: Int64 = 2

private func colorForEmitter(noColor: Bool, color: DiagColor, text: String): String {
    if (noColor) {
        return text
    }
    return coloredString(color, text)
}

private func sourceDisplayName(source: Source): String {
    if (let Some(name) <- source.packageName) {
        return "(package " + name + ")" + BasicGetFileName(source.path)
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
    private var macroNoteSwapped: Bool = false

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

    public func HasRangeError(): Bool {
        return hasRangeError()
    }

    public func Render(showSourceOnly!: Bool = false): String {
        swapErrorMessageWithNote()
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
        if (canRenderSameLineHintGroup(diagnostic.mainHint, diagnostic.otherHints)) {
            renderSameLineHintGroup(builder, diagnostic.mainHint, diagnostic.otherHints, width)
        } else {
            renderSourceLine(builder, diagnostic.mainHint.range, MAIN_HINT_MARKER, diagnostic.mainHint.str,
                diagnostic.mainHint.color, width)
            for (hint in diagnostic.otherHints) {
                renderHint(builder, hint, OTHER_HINT_MARKER, width)
            }
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
        if (!subDiag.mainHint.IsDefault() && canRenderSameLineHintGroup(subDiag.mainHint, subDiag.otherHints)) {
            renderSameLineHintGroup(builder, subDiag.mainHint, subDiag.otherHints, width)
        } else if (!subDiag.mainHint.IsDefault()) {
            renderSourceLine(builder, subDiag.mainHint.range, MAIN_HINT_MARKER, subDiag.mainHint.str,
                subDiag.mainHint.color, width)
            for (hint in subDiag.otherHints) {
                renderHint(builder, hint, OTHER_HINT_MARKER, width)
            }
        } else {
            for (hint in subDiag.otherHints) {
                renderHint(builder, hint, OTHER_HINT_MARKER, width)
            }
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

    private func canRenderSameLineHintGroup(mainHint: IntegratedString, otherHints: ArrayList<IntegratedString>): Bool {
        if (mainHint.IsDefault() || mainHint.range.begin.line != mainHint.range.end.line) {
            return false
        }
        for (hint in otherHints) {
            if (hint.IsDefault()) {
                continue
            }
            if (hint.range.begin.fileID != mainHint.range.begin.fileID ||
                hint.range.begin.line != mainHint.range.begin.line ||
                hint.range.end.line != hint.range.begin.line) {
                return false
            }
        }
        return true
    }

    private func renderSameLineHintGroup(
        builder: StringBuilder,
        mainHint: IntegratedString,
        otherHints: ArrayList<IntegratedString>,
        width: Int64
    ): Unit {
        let line = sourceLine(mainHint.range.begin)
        if (line.isEmpty()) {
            return
        }
        builder.append(sourceLinePrefix(mainHint.range.begin.fileID, mainHint.range.begin.line, width) +
            printableSourceLine(line) + "\n")
        renderInlineMarker(builder, line, mainHint.range.begin.column, mainHint.range.end.column, MAIN_HINT_MARKER,
            mainHint.str, mainHint.color, width)
        for (hint in otherHints) {
            if (!hint.IsDefault()) {
                renderInlineMarker(builder, line, hint.range.begin.column, hint.range.end.column, OTHER_HINT_MARKER,
                    hint.str, hint.color, width)
            }
        }
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
        let substitutions = sortedSubstitutions(help)
        if (substitutions.isEmpty()) {
            return
        }
        renderLabeledMessage(builder, "help", help.helpMes + ":", HELP_COLOR)
        let width = lineNumberWidth()
        renderLocation(builder, substitutions[0].range.begin, width)
        renderGutterLine(builder, width)
        renderHelpSubstitutionSource(builder, substitutions, width)
        renderGutterLine(builder, width)
    }

    private func renderHelpSubstitutionSource(builder: StringBuilder, substitutions: Array<Substitution>, width: Int64): Unit {
        let firstSubstitution = substitutions[0]
        let firstPos = firstSubstitution.range.begin
        var line = sourceLine(firstPos)
        if (line.isEmpty()) {
            return
        }
        let lastSubstitution = substitutions[substitutions.size - 1]
        if (line.size < lastSubstitution.range.begin.column) {
            return
        }
        let replacementRanges = ArrayList<Range>()
        for (substitution in substitutions) {
            let range = substitution.range
            if (range.begin.fileID != firstPos.fileID || range.begin.line != firstPos.line ||
                range.end.line != range.begin.line) {
                continue
            }
            let replaceBegin = range.begin.column - 1
            let replaceEnd = range.end.column - 1
            if (replaceBegin < 0 || replaceBegin > line.size || replaceEnd < replaceBegin) {
                continue
            }
            let fixedEnd = if (replaceEnd > line.size) { line.size } else { replaceEnd }
            line = line[0..replaceBegin] + substitution.str + line[fixedEnd..]
            replacementRanges.add(MakeRange(range.begin, range.begin + substitution.str.size))
        }
        builder.append(sourceLinePrefix(firstPos.fileID, firstPos.line, width) + printableSourceLine(line) + "\n")
        for (range in replacementRanges) {
            renderInlineMarker(builder, line, range.begin.column, range.end.column, OTHER_HINT_MARKER, "", HELP_COLOR, width)
        }
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
        if (!sourceManager.IsSourceFileExist(pos.fileID)) {
            return
        }
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
            if (shouldCompressMultiLineRange(range, lineNo)) {
                renderCompressedLine(builder, width)
                lineNo = range.end.line
            }
            let line = sourceLine(Position(range.begin.fileID, lineNo, 1))
            let startColumn = if (lineNo == range.begin.line) { range.begin.column } else { 1 }
            let endColumn = if (lineNo == range.end.line) { range.end.column } else { line.size + 1 }
            let text = if (lineNo == range.end.line) { hintText } else { "" }
            renderSingleSourceLine(builder, range.begin.fileID, lineNo, startColumn, endColumn, marker, text,
                color, width)
            lineNo++
        }
    }

    private func shouldCompressMultiLineRange(range: Range, lineNo: Int64): Bool {
        return lineNo == range.begin.line + COMPRESS_LEN && range.end.line - range.begin.line > COMPRESS_LEN
    }

    private func renderCompressedLine(builder: StringBuilder, width: Int64): Unit {
        builder.append(emptyLinePrefix(width) + "...\n")
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
        builder.append(sourceLinePrefix(fileID, lineNumber, width) + printableLine + "\n")
        let before = if (beginColumn > 1) { GetSpaceBeforeTarget(line, beginColumn) } else { "" }
        let markerWidth = displayedRangeWidth(line, range.begin.column, range.end.column)
        var indicator = repeatString(marker, markerWidth)
        if (!hintText.isEmpty()) {
            indicator += " " + hintText
        }
        builder.append(emptyLinePrefix(width) + before + colorForEmitter(noColor, color, indicator) + "\n")
    }

    private func renderInlineMarker(
        builder: StringBuilder,
        line: String,
        beginColumn: Int64,
        endColumn: Int64,
        marker: String,
        hintText: String,
        color: DiagColor,
        width: Int64
    ): Unit {
        let before = if (beginColumn > 1) { GetSpaceBeforeTarget(line, beginColumn) } else { "" }
        let markerWidth = displayedRangeWidth(line, beginColumn, endColumn)
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
                builder.append(sourceLinePrefix(info.mcBegin.fileID, lineNo, width) + printableSourceLine(line) + "\n")
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

    private func swapErrorMessageWithNote(): Unit {
        if (macroNoteSwapped || diagnostic.subDiags.isEmpty()) {
            return
        }
        if (let Some(info) <- diagnostic.macroDiagInfo) {
            let mainHint = diagnostic.mainHint
            if (info.isCurFile || mainHint.range.begin.isCurFile ||
                (diagnostic.start != INVALID_POSITION && diagnostic.start.isCurFile) ||
                !sourceManager.IsInMacroCallSourceFile(mainHint.range.begin) ||
                (diagnostic.start != INVALID_POSITION && !sourceManager.IsInMacroCallSourceFile(diagnostic.start))) {
                return
            }
            let subDiag = diagnostic.subDiags[0]
            if (diagnostic.isRefactor) {
                swapRefactorMacroNote(subDiag, mainHint)
            } else {
                swapLegacyMacroNote(subDiag)
            }
            macroNoteSwapped = true
        }
    }

    private func swapRefactorMacroNote(subDiag: SubDiagnostic, mainHint: IntegratedString): Unit {
        let newSubDiag = SubDiagnostic(diagnostic.errorMessage)
        newSubDiag.AddMainHint(mainHint.range, mainHint.str)
        for (hint in diagnostic.otherHints) {
            newSubDiag.otherHints.add(hint)
        }
        diagnostic.subDiags[0] = newSubDiag
        diagnostic.errorMessage = subDiag.subDiagMessage
        diagnostic.mainHint = IntegratedString(subDiag.mainHint.range, "", mainHint.color)
        diagnostic.otherHints.clear()
        for (hint in subDiag.otherHints) {
            diagnostic.otherHints.add(hint)
        }
    }

    private func swapLegacyMacroNote(subDiag: SubDiagnostic): Unit {
        let newSubDiag = SubDiagnostic(diagnostic.diagMessage)
        newSubDiag.AddMainHint(MakeRange(diagnostic.start, diagnostic.end), "")
        diagnostic.subDiags.add(newSubDiag, at: 0)
        diagnostic.diagMessage = subDiag.subDiagMessage
        diagnostic.errorMessage = subDiag.subDiagMessage
        diagnostic.start = subDiag.mainHint.range.begin
        diagnostic.end = subDiag.mainHint.range.end
        diagnostic.mainHint = IntegratedString(subDiag.mainHint.range, "", diagnostic.mainHint.color)
        diagnostic.otherHints.clear()
        for (hint in subDiag.otherHints) {
            diagnostic.otherHints.add(hint)
        }
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

    private func sourceLinePrefix(fileID: UInt64, lineNumber: Int64, width: Int64): String {
        if (!sourceManager.IsSourceFileExist(fileID)) {
            return emptyLinePrefix(width)
        }
        let lineText = "${lineNumber}"
        let padding = repeatString(" ", width - lineText.size + 1)
        return colorForEmitter(noColor, OTHER_HINT_COLOR, lineText) + padding +
            colorForEmitter(noColor, OTHER_HINT_COLOR, SOURCE_GUTTER + " ")
    }

    private func emptyLinePrefix(width: Int64): String {
        return repeatString(" ", width + 1) + colorForEmitter(noColor, OTHER_HINT_COLOR, SOURCE_GUTTER + " ")
    }

    private func sortedSubstitutions(help: DiagHelp): Array<Substitution> {
        let sorted = ArrayList<Substitution>()
        for (substitution in help.substitutions) {
            var idx: Int64 = 0
            while (idx < sorted.size && sorted[idx].range.begin <= substitution.range.begin) {
                idx++
            }
            sorted.add(substitution, at: idx)
        }
        return sorted.toArray()
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
