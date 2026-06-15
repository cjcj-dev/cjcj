package cangjie_compiler::modules

import std.collection.*

public enum DiagnosticSeverity {
    | ERROR
    | WARNING
    | NOTE
}

private func DiagnosticSeverityIndex(severity: DiagnosticSeverity): Int64 {
    return match (severity) {
        case DiagnosticSeverity.ERROR => 0
        case DiagnosticSeverity.WARNING => 1
        case DiagnosticSeverity.NOTE => 2
    }
}

extend DiagnosticSeverity <: Equatable<DiagnosticSeverity> {
    public operator func ==(right: DiagnosticSeverity): Bool {
        return DiagnosticSeverityIndex(this) == DiagnosticSeverityIndex(right)
    }

    public operator func !=(right: DiagnosticSeverity): Bool {
        return !(this == right)
    }
}

public class ModuleDiagnostic {
    public var kind: String = ""
    public var message: String = ""
    public var range: Range = Range()
    public var severity: DiagnosticSeverity = DiagnosticSeverity.ERROR

    public init() {}

    public init(kind: String, message: String, range: Range, severity: DiagnosticSeverity) {
        this.kind = kind
        this.message = message
        this.range = range
        this.severity = severity
    }
}

public class DiagnosticEngine {
    private let diagnostics: ArrayList<ModuleDiagnostic> = ArrayList<ModuleDiagnostic>()

    public init() {}

    public func ReportError(kind: String, message: String, range!: Range = Range()): Unit {
        diagnostics.add(ModuleDiagnostic(kind, message, range, DiagnosticSeverity.ERROR))
    }

    public func ReportWarning(kind: String, message: String, range!: Range = Range()): Unit {
        diagnostics.add(ModuleDiagnostic(kind, message, range, DiagnosticSeverity.WARNING))
    }

    public func ReportNote(kind: String, message: String, range!: Range = Range()): Unit {
        diagnostics.add(ModuleDiagnostic(kind, message, range, DiagnosticSeverity.NOTE))
    }

    public func HasErrors(): Bool {
        for (diag in diagnostics) {
            if (diag.severity == DiagnosticSeverity.ERROR) {
                return true
            }
        }
        return false
    }

    public func GetDiagnostics(): ArrayList<ModuleDiagnostic> {
        let out = ArrayList<ModuleDiagnostic>()
        for (diag in diagnostics) {
            out.add(diag)
        }
        return out
    }

    public func Clear(): Unit {
        diagnostics.clear()
    }
}

public func WarnConflictImport(diag: DiagnosticEngine, name: String, current: Range, previous: Range): Unit {
    let _ = previous
    diag.ReportWarning("package_import_conflict", "import '${name}' conflicts with an earlier import", range: current)
}

public func WarnUselessImport(diag: DiagnosticEngine, range: Range, decl: Decl): Unit {
    diag.ReportWarning("package_useless_import", "import is shadowed by declaration '${decl.identifier}'", range: range)
}

public func DiagForDifferentPackageNames(diag: DiagnosticEngine, packageNames: ArrayList<String>): Unit {
    diag.ReportError("package_name_inconsistent", "source files declare different package names: " +
        JoinStrings(packageNames, ", "))
}
