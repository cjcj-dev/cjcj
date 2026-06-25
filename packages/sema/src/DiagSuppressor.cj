package cangjie_compiler::sema

import cangjie_compiler::basic.*

public class DiagSuppressor <: Resource {
    private var diag: Option<DiagnosticEngine> = None
    private var originDiagVec: Array<Diagnostic> = Array<Diagnostic>()
    private var closed: Bool = false

    public init(diag: Option<DiagnosticEngine>) {
        this.diag = diag
        if (let Some(diagValue) <- diag) {
            originDiagVec = diagValue.DisableDiagnose()
        }
    }

    public init(diag: DiagnosticEngine) {
        this.diag = Some(diag)
        originDiagVec = diag.DisableDiagnose()
    }

    public init() {}

    public func GetSuppressedDiag(): Array<Diagnostic> {
        if (let Some(diagValue) <- diag) {
            return diagValue.ConsumeStoredDiags()
        }
        return Array<Diagnostic>()
    }

    public func ReportDiag(): Unit {
        if (let Some(diagValue) <- diag) {
            let diags = GetSuppressedDiag()
            diagValue.EnableDiagnose(originDiagVec)
            for (diagnostic in diags) {
                let builder = diagValue.Diagnose(diagnostic)
                builder.Emit()
            }
            originDiagVec = diagValue.DisableDiagnose()
        }
    }

    public func HasError(): Bool {
        if (let Some(diagValue) <- diag) {
            for (diagnostic in diagValue.GetStoredDiags()) {
                if (diagnostic.diagSeverity == DiagSeverity.DS_ERROR) {
                    return true
                }
            }
        }
        return false
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        closed = true
        if (let Some(diagValue) <- diag) {
            diagValue.EnableDiagnose(originDiagVec)
        }
    }

    public func isClosed(): Bool {
        return closed
    }
}
