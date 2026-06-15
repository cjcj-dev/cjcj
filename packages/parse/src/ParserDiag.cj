package cangjie_compiler::parse

extend ParserImpl {
    public func DiagExpectedIdentifier(pos: Position): Unit {
        diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_IDENTIFIER, pos, "expected identifier")
    }

    public func DiagExpectedExpression(): Unit {
        diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, Peek().Begin(), "expected expression")
    }

    public func DiagExpectedDeclaration(scopeKind: ScopeKind): Unit {
        diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, Peek().Begin(), "expected declaration")
    }
}
