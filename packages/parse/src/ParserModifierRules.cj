package cjcj::parse

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
            DiagIllegalModifierInScope(modifiers[0])
            return attrs
        }
        if (!MPParserImpl(this).CheckCJMPModifiers(modifiers)) {
            return attrs
        }
        let validModifiers = ArrayList<Modifier>()
        for (modifier in modifiers) {
            if (!IsModifierAllowed(defKind, scopeKind, modifier.modifier)) {
                DiagIllegalModifierInScope(modifier)
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
                            DiagConflictedModifier(other, modifier)
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

    public func GetModifierAttr(modifier: Option<Modifier>, kind: ASTKind): Attribute {
        if (let Some(it) <- modifier) {
            if (let Some(attr) <- GetAttributeByModifier(it.modifier)) {
                return attr
            }
        }
        if (kind == ASTKind.PACKAGE_SPEC) {
            return Attribute.PUBLIC
        }
        if (kind == ASTKind.IMPORT_SPEC) {
            return Attribute.PRIVATE
        }
        return Attribute.INTERNAL
    }

    private func ReportModifierWarning(defKind: DefKind, scopeKind: ScopeKind, modifiers: ArrayList<Modifier>): Unit {
        if (!HasWarningRules(defKind, scopeKind)) {
            return
        }
        for (modifier in modifiers) {
            let conflicts = GetWarningConflicts(defKind, scopeKind, modifier.modifier)
            for (higher in conflicts.data) {
                if (higher == TokenKind.ILLEGAL) {
                    DiagRedundantModifiers(modifier)
                    break
                }
                var foundHigher: Option<Modifier> = None
                for (candidate in modifiers) {
                    if (candidate.modifier == higher) {
                        foundHigher = candidate
                        break
                    }
                }
                if (let Some(higherModifier) <- foundHigher) {
                    DiagRedundantModifiers(modifier, higherModifier)
                    break
                }
            }
        }
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
