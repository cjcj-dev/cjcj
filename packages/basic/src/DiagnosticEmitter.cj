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
        renderPrimaryRange(builder)
        for (hint in diagnostic.otherHints) {
            renderHint(builder, hint, "~")
        }
        for (subDiag in diagnostic.subDiags) {
            renderSubDiagnostic(builder, subDiag)
        }
        for (help in diagnostic.helps) {
            renderHelp(builder, help)
        }
        return builder.toString()
    }

    private func renderHeader(builder: StringBuilder): Unit {
        let sev = severityName(diagnostic.diagSeverity)
        let colored = if (noColor) { sev } else { coloredString(emitterSeverityColor(diagnostic.diagSeverity), sev) }
        builder.append(colored + ": " + diagnostic.errorMessage + "\n")
    }

    private func renderPrimaryRange(builder: StringBuilder): Unit {
        if (diagnostic.mainHint.range.IsDefault()) {
            return
        }
        renderLocation(builder, diagnostic.mainHint.range.begin)
        renderSourceLine(builder, diagnostic.mainHint.range, "^", diagnostic.mainHint.str)
    }

    private func renderSubDiagnostic(builder: StringBuilder, subDiag: SubDiagnostic): Unit {
        if (!subDiag.subDiagMessage.isEmpty()) {
            builder.append("note: " + subDiag.subDiagMessage + "\n")
        }
        if (!subDiag.mainHint.IsDefault()) {
            renderLocation(builder, subDiag.mainHint.range.begin)
            renderSourceLine(builder, subDiag.mainHint.range, "^", subDiag.mainHint.str)
        }
        for (hint in subDiag.otherHints) {
            renderHint(builder, hint, "~")
        }
        renderHelp(builder, subDiag.help)
    }

    private func renderHint(builder: StringBuilder, hint: IntegratedString, marker: String): Unit {
        if (hint.IsDefault()) {
            return
        }
        renderLocation(builder, hint.range.begin)
        renderSourceLine(builder, hint.range, marker, hint.str)
    }

    private func renderHelp(builder: StringBuilder, help: DiagHelp): Unit {
        if (help.IsDefault()) {
            return
        }
        if (!help.helpMes.isEmpty()) {
            builder.append("help: " + help.helpMes + "\n")
        }
        for (substitution in help.substitutions) {
            renderLocation(builder, substitution.range.begin)
            renderSourceLine(builder, substitution.range, "~", substitution.str)
        }
    }

    private func renderLocation(builder: StringBuilder, pos: Position): Unit {
        let source = sourceManager.GetSource(pos.fileID)
        let path = if (source.path.isEmpty()) { "<unknown>" } else { source.path }
        builder.append(" ==> " + path + ":" + "${pos.line}" + ":" + "${pos.column}" + "\n")
    }

    private func renderSourceLine(builder: StringBuilder, range: Range, marker: String, hintText: String): Unit {
        let line = sourceLine(range.begin)
        if (line.isEmpty()) {
            return
        }
        builder.append("${range.begin.line} | " + line + "\n")
        let prefix = repeatString(" ", "${range.begin.line}".size) + " | "
        let before = if (range.begin.column > 1) { GetSpaceBeforeTarget(line, range.begin.column) } else { "" }
        let widthValue = range.end.column - range.begin.column
        let width = if (widthValue > 0) { widthValue } else { 1 }
        builder.append(prefix + before + repeatString(marker, width))
        if (!hintText.isEmpty()) {
            builder.append(" " + hintText)
        }
        builder.append("\n")
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
        return diagnostic.mainHint.range.HasZero()
    }

    // TODO(selfhost:Basic): match the full C++ DiagnosticEmitter layout, macro expansion blocks, color policy, and comment rendering exactly.
}
