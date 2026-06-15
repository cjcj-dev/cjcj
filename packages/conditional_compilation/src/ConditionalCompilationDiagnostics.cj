package cangjie_compiler::conditional_compilation

import cangjie_compiler::ast.Position as AstPosition
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.Position as BasicPosition

class ConditionalDiagnosticReporter {
    private var engine: Option<BasicDiagnosticEngine> = None

    public init() {}

    public init(engine: Option<BasicDiagnosticEngine>) {
        this.engine = engine
    }

    public func GetErrorCount(): UInt64 {
        if (let Some(diag) <- engine) {
            return diag.GetErrorCount()
        }
        return 0u64
    }

    public func Diagnose(kind: BasicDiagKindRefactor, pos: AstPosition, args!: Array<String> = Array<String>()): Unit {
        if (let Some(diag) <- engine) {
            diag.DiagnoseRefactor(kind, ToBasicPosition(pos), arguments: args).Emit()
        }
    }

    public func DiagnoseDefault(kind: BasicDiagKindRefactor, args!: Array<String> = Array<String>()): Unit {
        if (let Some(diag) <- engine) {
            diag.DiagnoseRefactor(kind, BasicPosition(0u64, -1, -1), arguments: args).Emit()
        }
    }

    public func DiagnoseWithNote(
        kind: BasicDiagKindRefactor,
        pos: AstPosition,
        note: String,
        args!: Array<String> = Array<String>()
    ): Unit {
        if (let Some(diag) <- engine) {
            let builder = diag.DiagnoseRefactor(kind, ToBasicPosition(pos), arguments: args)
            builder.AddNote(note)
            builder.Emit()
        }
    }
}

private func ToBasicPosition(pos: AstPosition): BasicPosition {
    var out = BasicPosition(pos.fileID, pos.line, pos.column)
    out.isCurFile = pos.isCurFile
    return out
}
