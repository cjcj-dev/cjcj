package cangjie_compiler::parse

import cangjie_compiler::option.BackendToString as OptionBackendToString

extend ParserImpl {
    public func DiagExpectedIdentifier(pos: Position): Unit {
        diag.DiagnoseRefactor(DiagKindRefactor.parse_diag_error, pos, "expected identifier")
    }

    public func DiagExpectedExpression(): Unit {
        diag.DiagnoseRefactor(DiagKindRefactor.parse_diag_error, Peek().Begin(), "expected expression")
    }

    public func DiagExpectedDeclaration(_: ScopeKind): Unit {
        diag.DiagnoseRefactor(DiagKindRefactor.parse_diag_error, Peek().Begin(), "expected declaration")
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
            bodyName)
        builder.AddMainHintArguments(str)
    }

    public func DiagNamedParameterAfterUnnamed(param: FuncParam, pre: FuncParam): Unit {
        let builder = ParseDiagnoseRefactor(
            DiagKindRefactor.parse_named_parameter_after_unnamed,
            param)
        builder.AddHint(MakeRange(pre.begin, pre.end))
    }

    public func DiagMemberParameterAfterRegular(param: FuncParam, pre: FuncParam): Unit {
        let builder = ParseDiagnoseRefactor(
            DiagKindRefactor.parse_member_parameter_after_regular,
            param)
        builder.AddHint(MakeRange(pre.begin, pre.end))
    }

    public func DiagExpectNoModifier(mod: Modifier): Unit {
        diag.DiagnoseRefactor(
            DiagKindRefactor.parse_diag_error,
            mod.begin,
            "expected no modifier here")
    }

    public func DiagUnExpectedModifierOnDeclaration(decl: Decl): Unit {
        for (modifier in decl.modifiers) {
            if (modifier.modifier == TokenKind.CONST) {
                let builder = diag.DiagnoseRefactor(
                    DiagKindRefactor.parse_unexpected_const_modifier_on_variable,
                    MakeRange(modifier.begin, modifier.end))
                builder.AddHint(MakeRange(decl.keywordPos, decl.keywordPos + 3))
                return
            }
        }
        diag.DiagnoseRefactor(DiagKindRefactor.parse_unexpected_const_modifier_on_variable, decl.begin)
    }

    public func DiagDeprecatedInvalidTarget(node: Node, invalidTarget: String): Unit {
        diag.DiagnoseRefactor(
            DiagKindRefactor.parse_deprecated_invalid_target,
            node.begin,
            invalidTarget)
    }
}
