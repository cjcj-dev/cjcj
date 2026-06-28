package cangjie_compiler::parse

import std.collection.*

public enum DiagSeverity {
    | ERROR | WARNING | NOTE
}

private func DiagSeverityIndex(kind: DiagSeverity): Int64 {
    return match (kind) {
        case DiagSeverity.ERROR => 0
        case DiagSeverity.WARNING => 1
        case DiagSeverity.NOTE => 2
    }
}

extend DiagSeverity <: Equatable<DiagSeverity> {
    public operator func ==(right: DiagSeverity): Bool { return DiagSeverityIndex(this) == DiagSeverityIndex(right) }
    public operator func !=(right: DiagSeverity): Bool { return !(this == right) }
}

public enum DiagKindRefactor {
    | PARSE_ERROR | EXPECTED_TOKEN | EXPECTED_IDENTIFIER | UNEXPECTED_TOKEN | UNTERMINATED_DELIMITER
    | INVALID_MODIFIER | DUPLICATED_MODIFIER | CONFLICTING_MODIFIER | INVALID_ANNOTATION
    | lex_unknown_start_of_token | parse_invalid_quote_dollar_expr
}

public class Diagnostic {
    public let severity: DiagSeverity
    public let kind: DiagKindRefactor
    public let pos: Position
    public let message: String

    public init(severity: DiagSeverity, kind: DiagKindRefactor, pos: Position, message: String) {
        this.severity = severity
        this.kind = kind
        this.pos = pos
        this.message = message
    }
}

public class DiagnosticBuilder {
    private let engine: DiagnosticEngine
    private let diagnostic: Diagnostic
    private var emitted: Bool = false

    public init(engine: DiagnosticEngine, diagnostic: Diagnostic) {
        this.engine = engine
        this.diagnostic = diagnostic
    }

    public func Emit(): Unit {
        if (!emitted) {
            engine.Store(diagnostic)
            emitted = true
        }
    }

    public func close(): Unit {
        Emit()
    }
}

public class DiagnosticEngine {
    private let diagnostics = ArrayList<Diagnostic>()

    public init() {}

    public func Store(diagnostic: Diagnostic): Unit {
        diagnostics.add(diagnostic)
    }

    public func DiagnoseRefactor(kind: DiagKindRefactor, pos: Position, message: String): DiagnosticBuilder {
        let builder = DiagnosticBuilder(this, Diagnostic(DiagSeverity.ERROR, kind, pos, message))
        builder.Emit()
        return builder
    }

    public func Warning(kind: DiagKindRefactor, pos: Position, message: String): Unit {
        diagnostics.add(Diagnostic(DiagSeverity.WARNING, kind, pos, message))
    }

    public func HasError(): Bool {
        for (diagnostic in diagnostics) {
            if (diagnostic.severity == DiagSeverity.ERROR) {
                return true
            }
        }
        return false
    }

    public func Diagnostics(): ArrayList<Diagnostic> {
        return diagnostics
    }

    public func Clear(): Unit {
        diagnostics.clear()
    }
}
