package cangjie_compiler::parse

import cangjie_compiler::option.BackendToString as OptionBackendToString

extend ParserImpl {
    public func DiagExpectedIdentifier(pos: Position): Unit {
        diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_IDENTIFIER, pos, "expected identifier")
    }

    public func DiagExpectedExpression(): Unit {
        diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, Peek().Begin(), "expected expression")
    }

    public func DiagExpectedDeclaration(_: ScopeKind): Unit {
        diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, Peek().Begin(), "expected declaration")
    }

    public func DiagUnsafeWillBeIgnored(mod: Modifier): Unit {
        let backend = OptionBackendToString(compileOptions.backend)
        let builder = diag.DiagnoseRefactor(DiagKindRefactor.parse_unsafe_will_be_ignored, mod.begin, backend)
        builder.AddMainHintArguments(backend)
    }
}
