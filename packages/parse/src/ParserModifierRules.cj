package cangjie_compiler::parse

import std.collection.*

extend ParserImpl {
    public func CheckDeclModifiers(modifiers: ArrayList<Modifier>, scopeKind: ScopeKind, defKind: DefKind): ArrayList<Attribute> {
        let attrs = ArrayList<Attribute>()
        for (modifier in modifiers) {
            if (!IsModifierAllowed(defKind, scopeKind, modifier.tokenKind)) {
                diag.DiagnoseRefactor(DiagKindRefactor.INVALID_MODIFIER, modifier.begin, "modifier is not allowed here")
            }
            let conflicts = GetConflictingModifiers(defKind, scopeKind, modifier.tokenKind)
            for (other in modifiers) {
                if (other.begin != modifier.begin) {
                    for (conflict in conflicts.data) {
                        if (other.tokenKind == conflict) {
                            diag.DiagnoseRefactor(DiagKindRefactor.CONFLICTING_MODIFIER, other.begin, "conflicting modifier")
                        }
                    }
                }
            }
            if (let Some(attr) <- GetAttributeByModifier(modifier.tokenKind)) {
                attrs.add(attr)
            }
        }
        return attrs
    }
}
