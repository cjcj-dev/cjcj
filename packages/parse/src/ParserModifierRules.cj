package cangjie_compiler::parse

import std.collection.*

extend ParserImpl {
    public func CheckDeclModifiers(modifiers: ArrayList<Modifier>, scopeKind: ScopeKind, defKind: DefKind): ArrayList<Attribute> {
        let attrs = ArrayList<Attribute>()
        if (ScopeKindEquals(scopeKind, ScopeKind.UNKNOWN_SCOPE)) {
            for (modifier in modifiers) {
                if (let Some(attr) <- GetAttributeByModifier(modifier.modifier)) {
                    AddAttrIfAbsent(attrs, attr)
                }
            }
            return attrs
        }
        if (!HasScopeRules(defKind, scopeKind)) {
            return attrs
        }
        if (modifiers.isEmpty()) {
            if (ScopeKindEquals(scopeKind, ScopeKind.CLASS_BODY) || ScopeKindEquals(scopeKind, ScopeKind.INTERFACE_BODY)) {
                attrs.add(Attribute.IN_CLASSLIKE)
            }
            return attrs
        }
        if (IsScopeRulesEmpty(defKind, scopeKind)) {
            diag.DiagnoseRefactor(DiagKindRefactor.INVALID_MODIFIER, modifiers[0].begin, "modifier is not allowed here")
            return attrs
        }
        if (!MPParserImpl(this).CheckCJMPModifiers(modifiers)) {
            return attrs
        }
        let validModifiers = ArrayList<Modifier>()
        for (modifier in modifiers) {
            if (!IsModifierAllowed(defKind, scopeKind, modifier.modifier)) {
                diag.DiagnoseRefactor(DiagKindRefactor.INVALID_MODIFIER, modifier.begin, "modifier is not allowed here")
                if (let Some(attr) <- GetAttributeByModifier(modifier.modifier)) {
                    AddAttrIfAbsent(attrs, attr)
                }
                continue
            }
            var hasCollision = false
            let conflicts = GetConflictingModifiers(defKind, scopeKind, modifier.modifier)
            for (other in modifiers) {
                if (other.begin < modifier.begin) {
                    for (conflict in conflicts.data) {
                        if (other.modifier == conflict) {
                            diag.DiagnoseRefactor(DiagKindRefactor.CONFLICTING_MODIFIER, modifier.begin, "conflicting modifier")
                            hasCollision = true
                            RemoveModifierKind(validModifiers, conflict)
                        }
                    }
                }
            }
            if (!hasCollision) {
                validModifiers.add(modifier)
            }
            if (let Some(attr) <- GetAttributeByModifier(modifier.modifier)) {
                AddAttrIfAbsent(attrs, attr)
            }
        }
        ReportModifierWarning(defKind, scopeKind, validModifiers)
        return attrs
    }

    private func ReportModifierWarning(defKind: DefKind, scopeKind: ScopeKind, modifiers: ArrayList<Modifier>): Unit {
        if (!HasWarningRules(defKind, scopeKind)) {
            return
        }
        for (modifier in modifiers) {
            let conflicts = GetWarningConflicts(defKind, scopeKind, modifier.modifier)
            for (higher in conflicts.data) {
                if (higher == TokenKind.ILLEGAL) {
                    diag.Warning(DiagKindRefactor.INVALID_MODIFIER, modifier.begin, "redundant modifier")
                    break
                }
                if (HasModifierKind(modifiers, higher)) {
                    diag.Warning(DiagKindRefactor.CONFLICTING_MODIFIER, modifier.begin, "redundant modifier")
                    break
                }
            }
        }
    }

    private func HasModifierKind(modifiers: ArrayList<Modifier>, kind: TokenKind): Bool {
        for (modifier in modifiers) {
            if (modifier.modifier == kind) {
                return true
            }
        }
        return false
    }

    private func RemoveModifierKind(modifiers: ArrayList<Modifier>, kind: TokenKind): Unit {
        var index: Int64 = modifiers.size - 1
        while (index >= 0) {
            if (modifiers[index].modifier == kind) {
                modifiers.remove(at: index)
            }
            index--
        }
    }

    private func AddAttrIfAbsent(attrs: ArrayList<Attribute>, attr: Attribute): Unit {
        for (item in attrs) {
            if (item == attr) {
                return
            }
        }
        attrs.add(attr)
    }
}
