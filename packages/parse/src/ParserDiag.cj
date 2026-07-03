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

    public func DiagMissingBody(str: String, name: String, pos: Position): Unit {
        if (parseDeclFile) {
            return
        }
        let bodyName = if (name.isEmpty()) { str } else { str + name }
        let builder = diag.DiagnoseRefactor(
            DiagKindRefactor.parse_missing_body,
            pos,
            "body of ${bodyName} is missing")
        builder.AddMainHintArguments(str)
    }

    public func DiagNamedParameterAfterUnnamed(param: FuncParam, pre: FuncParam): Unit {
        let _ = pre
        diag.DiagnoseRefactor(
            DiagKindRefactor.parse_named_parameter_after_unnamed,
            param.begin,
            "unnamed parameters must come before named parameters")
    }

    public func DiagMemberParameterAfterRegular(param: FuncParam, pre: FuncParam): Unit {
        let _ = pre
        diag.DiagnoseRefactor(
            DiagKindRefactor.parse_member_parameter_after_regular,
            param.begin,
            "regular parameters must come before member variable parameters")
    }

    public func DiagExpectNoModifier(mod: Modifier): Unit {
        diag.DiagnoseRefactor(
            DiagKindRefactor.parse_expected_no_modifier,
            mod.begin,
            "expected no modifier here")
    }

    public func DiagUnExpectedModifierOnDeclaration(decl: Decl): Unit {
        diag.DiagnoseRefactor(
            DiagKindRefactor.parse_unexpected_const_modifier_on_variable,
            decl.begin,
            "unexpected modifier 'const' on var or let variable")
    }

    public func DiagDeprecatedInvalidTarget(node: Node, invalidTarget: String): Unit {
        diag.DiagnoseRefactor(
            DiagKindRefactor.parse_deprecated_invalid_target,
            node.begin,
            "${invalidTarget} can not be target of @Deprecated")
    }
}
