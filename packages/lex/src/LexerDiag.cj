package cjcj::lex

import cjcj::basic.*
import cjcj::basic.Range as BasicRange

private func oneArg(value: String): Array<String> {
    return [value]
}

private func twoArgs(left: String, right: String): Array<String> {
    return [left, right]
}

func lexDiagnose(diag: DiagnosticEngine, kind: DiagKindRefactor, pos: Position): Unit {
    diag.DiagnoseRefactor(kind, pos).Emit()
}

func lexDiagnose(diag: DiagnosticEngine, kind: DiagKindRefactor, pos: Position, arg: String): Unit {
    diag.DiagnoseRefactor(kind, pos, arguments: oneArg(arg)).Emit()
}

func lexDiagnose(diag: DiagnosticEngine, kind: DiagKindRefactor, range: BasicRange): Unit {
    diag.DiagnoseRefactor(kind, range).Emit()
}

func lexDiagnose(diag: DiagnosticEngine, kind: DiagKindRefactor, range: BasicRange, arg: String): Unit {
    diag.DiagnoseRefactor(kind, range, arguments: oneArg(arg)).Emit()
}

func lexDiagnose2(diag: DiagnosticEngine, kind: DiagKindRefactor, pos: Position, left: String, right: String): Unit {
    diag.DiagnoseRefactor(kind, pos, arguments: twoArgs(left, right)).Emit()
}
