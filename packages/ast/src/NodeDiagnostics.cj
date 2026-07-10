package cangjie_compiler::ast

import cangjie_compiler::basic.{
    Diagnostic, DiagnosticBuilder, DiagnosticEngine, DiagKindRefactor, GetDiagnoseCategory, SubDiagnostic
}
import cangjie_compiler::basic.Range as BasicRange

public func MakeRealRange(
    node: Node,
    begin: Position,
    end: Position,
    begLowBound!: Bool = false
): BasicRange {
    let newBegin = node.GetMacroCallPos(begin, isLowerBound: begLowBound)
    let newEnd = node.GetMacroCallPos(end, isLowerBound: true)
    return MakeRange(newBegin, newEnd)
}

public func AddMacroCallNote(
    diag: DiagnosticEngine,
    diagnostic: Diagnostic,
    node: Node,
    pos: Position
): Unit {
    if (let Some(macroCall) <- node.curMacroCall) {
        if (let Some(invocation) <- macroCall.GetInvocation()) {
            diagnostic.macroDiagInfo = Some(invocation.macroCallDiagInfo)
            diag.AddMacroCallNote(diagnostic, invocation.macroCallDiagInfo, pos)
        }
    }
}

public func DiagnoseRefactor(
    diag: DiagnosticEngine,
    kind: DiagKindRefactor,
    node: Node,
    arguments!: Array<String> = Array<String>()
): DiagnosticBuilder {
    let range = MakeRange(node.GetBegin(), node.GetEnd())
    let diagnostic = Diagnostic(true, range, kind, arguments: arguments)
    diagnostic.isInMacroCall = node.isInMacroCall
    AddMacroCallNote(diag, diagnostic, node, node.begin)
    return DiagnosticBuilder(diag, diagnostic)
}

public func DiagnoseRefactor(
    diag: DiagnosticEngine,
    kind: DiagKindRefactor,
    node: Node,
    argument: String
): DiagnosticBuilder {
    return DiagnoseRefactor(diag, kind, node, arguments: [argument])
}

public func DiagnoseRefactor(
    diag: DiagnosticEngine,
    kind: DiagKindRefactor,
    node: Node,
    arg0: String,
    arg1: String
): DiagnosticBuilder {
    return DiagnoseRefactor(diag, kind, node, arguments: [arg0, arg1])
}

public func DiagnoseRefactor(
    diag: DiagnosticEngine,
    kind: DiagKindRefactor,
    node: Node,
    arg0: String,
    arg1: String,
    arg2: String
): DiagnosticBuilder {
    return DiagnoseRefactor(diag, kind, node, arguments: [arg0, arg1, arg2])
}

public func DiagnoseRefactor(
    diag: DiagnosticEngine,
    kind: DiagKindRefactor,
    node: Node,
    pos: Position,
    arguments!: Array<String> = Array<String>()
): DiagnosticBuilder {
    let begin = node.GetMacroCallPos(pos, isLowerBound: true)
    let range = MakeRange(begin, begin + 1)
    let diagnostic = Diagnostic(true, range, kind, arguments: arguments)
    diagnostic.isInMacroCall = node.isInMacroCall
    AddMacroCallNote(diag, diagnostic, node, pos)
    return DiagnosticBuilder(diag, diagnostic)
}

public func DiagnoseRefactor(
    diag: DiagnosticEngine,
    kind: DiagKindRefactor,
    node: Node,
    pos: Position,
    argument: String
): DiagnosticBuilder {
    return DiagnoseRefactor(diag, kind, node, pos, arguments: [argument])
}

public func DiagnoseRefactor(
    diag: DiagnosticEngine,
    kind: DiagKindRefactor,
    node: Node,
    pos: Position,
    arg0: String,
    arg1: String
): DiagnosticBuilder {
    return DiagnoseRefactor(diag, kind, node, pos, arguments: [arg0, arg1])
}

public func DiagnoseRefactor(
    diag: DiagnosticEngine,
    kind: DiagKindRefactor,
    node: Node,
    pos: Position,
    arg0: String,
    arg1: String,
    arg2: String
): DiagnosticBuilder {
    return DiagnoseRefactor(diag, kind, node, pos, arguments: [arg0, arg1, arg2])
}

public func DiagnoseRefactor(
    diag: DiagnosticEngine,
    kind: DiagKindRefactor,
    node: Node,
    range: BasicRange,
    arguments!: Array<String> = Array<String>()
): DiagnosticBuilder {
    diag.CheckRange(GetDiagnoseCategory(kind), range)
    let newRange = MakeRealRange(node, range.begin, range.end)
    let diagnostic = Diagnostic(true, newRange, kind, arguments: arguments)
    diagnostic.isInMacroCall = node.isInMacroCall
    AddMacroCallNote(diag, diagnostic, node, range.begin)
    return DiagnosticBuilder(diag, diagnostic)
}

public func DiagnoseRefactor(
    diag: DiagnosticEngine,
    kind: DiagKindRefactor,
    node: Node,
    range: BasicRange,
    argument: String
): DiagnosticBuilder {
    return DiagnoseRefactor(diag, kind, node, range, arguments: [argument])
}

public func DiagnoseRefactor(
    diag: DiagnosticEngine,
    kind: DiagKindRefactor,
    node: Node,
    range: BasicRange,
    arg0: String,
    arg1: String
): DiagnosticBuilder {
    return DiagnoseRefactor(diag, kind, node, range, arguments: [arg0, arg1])
}

public func DiagnoseRefactor(
    diag: DiagnosticEngine,
    kind: DiagKindRefactor,
    node: Node,
    range: BasicRange,
    arg0: String,
    arg1: String,
    arg2: String
): DiagnosticBuilder {
    return DiagnoseRefactor(diag, kind, node, range, arguments: [arg0, arg1, arg2])
}

public func DiagnoseRefactor(
    diag: DiagnosticEngine,
    kind: DiagKindRefactor,
    node: Node,
    token: Token,
    arguments!: Array<String> = Array<String>()
): DiagnosticBuilder {
    let range = MakeRealRange(
        node,
        token.Begin(),
        token.End(),
        begLowBound: token.kind == TokenKind.END
    )
    let diagnostic = Diagnostic(true, range, kind, arguments: arguments)
    diagnostic.isInMacroCall = node.isInMacroCall
    AddMacroCallNote(diag, diagnostic, node, token.Begin())
    return DiagnosticBuilder(diag, diagnostic)
}

public func DiagnoseRefactor(
    diag: DiagnosticEngine,
    kind: DiagKindRefactor,
    node: Node,
    token: Token,
    argument: String
): DiagnosticBuilder {
    return DiagnoseRefactor(diag, kind, node, token, arguments: [argument])
}

public func DiagnoseRefactor(
    diag: DiagnosticEngine,
    kind: DiagKindRefactor,
    node: Node,
    token: Token,
    arg0: String,
    arg1: String
): DiagnosticBuilder {
    return DiagnoseRefactor(diag, kind, node, token, arguments: [arg0, arg1])
}

public func DiagnoseRefactor(
    diag: DiagnosticEngine,
    kind: DiagKindRefactor,
    node: Node,
    token: Token,
    arg0: String,
    arg1: String,
    arg2: String
): DiagnosticBuilder {
    return DiagnoseRefactor(diag, kind, node, token, arguments: [arg0, arg1, arg2])
}

public func AddHint(
    builder: DiagnosticBuilder,
    node: Node,
    arguments!: Array<String> = Array<String>()
): Unit {
    builder.AddHint(MakeRange(node.GetBegin(), node.GetEnd()), arguments: arguments)
}

public func AddNote(builder: DiagnosticBuilder, node: Node, note: String): Unit {
    let range = MakeRange(node.begin, node.end)
    builder.diag.CheckRange(builder.diagnostic.GetDiagCategory(), range)
    let subDiag = SubDiagnostic(range, note)
    builder.AddNote(subDiag)
}

public func AddNote(builder: DiagnosticBuilder, node: Node, range: BasicRange, note: String): Unit {
    builder.diag.CheckRange(builder.diagnostic.GetDiagCategory(), range)
    let newRange = MakeRange(
        node.GetMacroCallPos(range.begin),
        node.GetMacroCallPos(range.end, isLowerBound: true)
    )
    let subDiag = SubDiagnostic(newRange, note)
    builder.AddNote(subDiag)
}
