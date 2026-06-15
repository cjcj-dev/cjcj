package cangjie_compiler::lex

import cangjie_compiler::basic.*
import cangjie_compiler::basic.Range as BasicRange

private func oneArg(value: String): Array<String> {
    return [value]
}

private func twoArgs(left: String, right: String): Array<String> {
    return [left, right]
}

func lexDiagnose(diag: DiagnosticEngine, kind: DiagKindRefactor, pos: Position): Unit {
    diag.DiagnoseRefactor(kind, pos)
}

func lexDiagnose(diag: DiagnosticEngine, kind: DiagKindRefactor, pos: Position, arg: String): Unit {
    diag.DiagnoseRefactor(kind, pos, arguments: oneArg(arg))
}

func lexDiagnose(diag: DiagnosticEngine, kind: DiagKindRefactor, range: BasicRange): Unit {
    diag.DiagnoseRefactor(kind, range)
}

func lexDiagnose(diag: DiagnosticEngine, kind: DiagKindRefactor, range: BasicRange, arg: String): Unit {
    diag.DiagnoseRefactor(kind, range, arguments: oneArg(arg))
}

func lexDiagnose2(diag: DiagnosticEngine, kind: DiagKindRefactor, pos: Position, left: String, right: String): Unit {
    diag.DiagnoseRefactor(kind, pos, arguments: twoArgs(left, right))
}
