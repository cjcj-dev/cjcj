package cangjie_compiler::sema

import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.Position as BasicPosition
import cangjie_compiler::ast.*

public func SemaDiag(diag: BasicDiagnosticEngine, kind: BasicDiagKindRefactor, node: Node): Unit {
    let pos = BasicPosition(node.begin.fileID, node.begin.line, node.begin.column)
    diag.DiagnoseRefactor(kind, pos)
}
