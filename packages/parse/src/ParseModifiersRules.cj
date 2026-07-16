package cjcj::parse

import std.collection.*

public class ConflictArray {
    public let data: ArrayList<TokenKind> = ArrayList<TokenKind>()
    public init() {}
    public init(items: Array<TokenKind>) {
        for (item in items) { data.add(item) }
    }
    public func size(): Int64 { return data.size }
}

private func NoConflicts(): Array<TokenKind> { return Array<TokenKind>() }
private func AccessPublic(): Array<TokenKind> { return [TokenKind.PRIVATE, TokenKind.INTERNAL, TokenKind.PROTECTED] }
private func AccessPrivate(): Array<TokenKind> { return [TokenKind.PUBLIC, TokenKind.INTERNAL, TokenKind.PROTECTED] }
private func AccessInternal(): Array<TokenKind> { return [TokenKind.PUBLIC, TokenKind.PRIVATE, TokenKind.PROTECTED] }
private func AccessProtected(): Array<TokenKind> { return [TokenKind.PUBLIC, TokenKind.PRIVATE, TokenKind.INTERNAL] }
private func CommonSpecific(): Array<TokenKind> { return [TokenKind.SPECIFIC] }
private func SpecificCommon(): Array<TokenKind> { return [TokenKind.COMMON] }
private func OverrideStaticRedef(): Array<TokenKind> { return [TokenKind.STATIC, TokenKind.REDEF] }
private func RedefOverrideOpenOperator(): Array<TokenKind> {
    return [TokenKind.OVERRIDE, TokenKind.OPEN, TokenKind.OPERATOR]
}
private func OpenStaticRedef(): Array<TokenKind> { return [TokenKind.STATIC, TokenKind.REDEF] }
private func OperatorStatic(): Array<TokenKind> { return [TokenKind.STATIC] }
private func MutStatic(): Array<TokenKind> { return [TokenKind.STATIC] }
private func StaticOverride(): Array<TokenKind> { return [TokenKind.OVERRIDE] }
private func StaticOverrideOpen(): Array<TokenKind> { return [TokenKind.OVERRIDE, TokenKind.OPEN] }
private func RedefOverride(): Array<TokenKind> { return [TokenKind.OVERRIDE] }
private func RedefOverrideOpen(): Array<TokenKind> { return [TokenKind.OVERRIDE, TokenKind.OPEN] }
private func PublicSealed(): Array<TokenKind> { return [TokenKind.SEALED] }
private func IllegalOnly(): Array<TokenKind> { return [TokenKind.ILLEGAL] }
private func AggPublic(): Array<TokenKind> {
    return [TokenKind.STATIC, TokenKind.PRIVATE, TokenKind.INTERNAL, TokenKind.PROTECTED]
}
private func AggPrivate(): Array<TokenKind> {
    return [TokenKind.STATIC, TokenKind.PUBLIC, TokenKind.INTERNAL, TokenKind.PROTECTED]
}
private func AggInternal(): Array<TokenKind> {
    return [TokenKind.STATIC, TokenKind.PUBLIC, TokenKind.PRIVATE, TokenKind.PROTECTED]
}
private func AggProtected(): Array<TokenKind> {
    return [TokenKind.STATIC, TokenKind.PUBLIC, TokenKind.PRIVATE, TokenKind.INTERNAL]
}

private func PackageRule(modifier: TokenKind): Option<Array<TokenKind>> {
    if (modifier == TokenKind.PUBLIC) { return [TokenKind.INTERNAL, TokenKind.PROTECTED] }
    if (modifier == TokenKind.INTERNAL) { return [TokenKind.PUBLIC, TokenKind.PROTECTED] }
    if (modifier == TokenKind.PROTECTED) { return [TokenKind.PUBLIC, TokenKind.INTERNAL] }
    return None
}

private func TopLevelCommonRule(modifier: TokenKind): Option<Array<TokenKind>> {
    if (modifier == TokenKind.PUBLIC) { return AccessPublic() }
    if (modifier == TokenKind.PRIVATE) { return AccessPrivate() }
    if (modifier == TokenKind.INTERNAL) { return AccessInternal() }
    if (modifier == TokenKind.PROTECTED) { return AccessProtected() }
    return None
}

private func TopLevelEnumStructRule(modifier: TokenKind): Option<Array<TokenKind>> {
    if (modifier == TokenKind.PUBLIC) { return AccessPublic() }
    if (modifier == TokenKind.PRIVATE) {
        return [TokenKind.PUBLIC, TokenKind.INTERNAL, TokenKind.PROTECTED, TokenKind.COMMON, TokenKind.SPECIFIC]
    }
    if (modifier == TokenKind.INTERNAL) { return AccessInternal() }
    if (modifier == TokenKind.PROTECTED) { return AccessProtected() }
    if (modifier == TokenKind.COMMON) { return [TokenKind.PRIVATE, TokenKind.SPECIFIC] }
    if (modifier == TokenKind.SPECIFIC) { return [TokenKind.PRIVATE, TokenKind.COMMON] }
    return None
}

private func TopLevelClassRule(modifier: TokenKind): Option<Array<TokenKind>> {
    if (modifier == TokenKind.PUBLIC) {
        return [TokenKind.PRIVATE, TokenKind.INTERNAL, TokenKind.PROTECTED, TokenKind.FOREIGN]
    }
    if (modifier == TokenKind.PRIVATE) {
        return [
            TokenKind.PUBLIC, TokenKind.INTERNAL, TokenKind.PROTECTED, TokenKind.SEALED, TokenKind.COMMON,
            TokenKind.SPECIFIC
        ]
    }
    if (modifier == TokenKind.INTERNAL) {
        return [TokenKind.PUBLIC, TokenKind.PRIVATE, TokenKind.PROTECTED, TokenKind.SEALED]
    }
    if (modifier == TokenKind.PROTECTED) {
        return [TokenKind.PUBLIC, TokenKind.PRIVATE, TokenKind.INTERNAL, TokenKind.SEALED]
    }
    if (modifier == TokenKind.ABSTRACT) { return NoConflicts() }
    if (modifier == TokenKind.SEALED) { return [TokenKind.PRIVATE, TokenKind.INTERNAL, TokenKind.PROTECTED] }
    if (modifier == TokenKind.OPEN) { return NoConflicts() }
    if (modifier == TokenKind.FOREIGN) { return [TokenKind.PUBLIC] }
    if (modifier == TokenKind.COMMON) { return [TokenKind.PRIVATE, TokenKind.SPECIFIC] }
    if (modifier == TokenKind.SPECIFIC) { return [TokenKind.PRIVATE, TokenKind.COMMON] }
    return None
}

private func TopLevelInterfaceRule(modifier: TokenKind): Option<Array<TokenKind>> {
    if (modifier == TokenKind.PUBLIC) {
        return [TokenKind.PRIVATE, TokenKind.INTERNAL, TokenKind.PROTECTED, TokenKind.FOREIGN]
    }
    if (modifier == TokenKind.PRIVATE) {
        return [
            TokenKind.PUBLIC, TokenKind.INTERNAL, TokenKind.PROTECTED, TokenKind.SEALED, TokenKind.COMMON,
            TokenKind.SPECIFIC
        ]
    }
    if (modifier == TokenKind.INTERNAL) {
        return [TokenKind.PUBLIC, TokenKind.PRIVATE, TokenKind.PROTECTED, TokenKind.SEALED]
    }
    if (modifier == TokenKind.PROTECTED) {
        return [TokenKind.PUBLIC, TokenKind.PRIVATE, TokenKind.INTERNAL, TokenKind.SEALED]
    }
    if (modifier == TokenKind.SEALED) { return [TokenKind.PRIVATE, TokenKind.INTERNAL, TokenKind.PROTECTED] }
    if (modifier == TokenKind.OPEN) { return NoConflicts() }
    if (modifier == TokenKind.FOREIGN) { return [TokenKind.PUBLIC] }
    if (modifier == TokenKind.COMMON) { return [TokenKind.PRIVATE, TokenKind.SPECIFIC] }
    if (modifier == TokenKind.SPECIFIC) { return [TokenKind.PRIVATE, TokenKind.COMMON] }
    return None
}

private func TopLevelVariableRule(modifier: TokenKind): Option<Array<TokenKind>> {
    if (modifier == TokenKind.CONST) { return [TokenKind.FOREIGN] }
    if (modifier == TokenKind.PUBLIC) {
        return [TokenKind.PRIVATE, TokenKind.INTERNAL, TokenKind.PROTECTED, TokenKind.FOREIGN]
    }
    if (modifier == TokenKind.PRIVATE) {
        return [TokenKind.PUBLIC, TokenKind.INTERNAL, TokenKind.PROTECTED, TokenKind.COMMON, TokenKind.SPECIFIC]
    }
    if (modifier == TokenKind.INTERNAL) { return AccessInternal() }
    if (modifier == TokenKind.PROTECTED) { return AccessProtected() }
    if (modifier == TokenKind.FOREIGN) {
        return [TokenKind.CONST, TokenKind.PUBLIC, TokenKind.UNSAFE, TokenKind.COMMON, TokenKind.SPECIFIC]
    }
    if (modifier == TokenKind.COMMON) {
        return [TokenKind.PRIVATE, TokenKind.FOREIGN, TokenKind.SPECIFIC]
    }
    if (modifier == TokenKind.SPECIFIC) {
        return [TokenKind.PRIVATE, TokenKind.FOREIGN, TokenKind.COMMON]
    }
    return None
}

private func TopLevelFuncRule(modifier: TokenKind): Option<Array<TokenKind>> {
    if (modifier == TokenKind.CONST) { return [TokenKind.FOREIGN] }
    if (modifier == TokenKind.PUBLIC) {
        return [TokenKind.PRIVATE, TokenKind.INTERNAL, TokenKind.PROTECTED, TokenKind.FOREIGN]
    }
    if (modifier == TokenKind.PRIVATE) {
        return [TokenKind.PUBLIC, TokenKind.INTERNAL, TokenKind.PROTECTED, TokenKind.FOREIGN, TokenKind.COMMON]
    }
    if (modifier == TokenKind.INTERNAL) {
        return [TokenKind.PUBLIC, TokenKind.PRIVATE, TokenKind.PROTECTED, TokenKind.FOREIGN]
    }
    if (modifier == TokenKind.PROTECTED) {
        return [TokenKind.PUBLIC, TokenKind.PRIVATE, TokenKind.INTERNAL, TokenKind.FOREIGN]
    }
    if (modifier == TokenKind.FOREIGN) {
        return [
            TokenKind.CONST, TokenKind.PUBLIC, TokenKind.PRIVATE, TokenKind.INTERNAL, TokenKind.PROTECTED,
            TokenKind.UNSAFE, TokenKind.COMMON
        ]
    }
    if (modifier == TokenKind.UNSAFE) { return [TokenKind.FOREIGN] }
    if (modifier == TokenKind.COMMON) {
        return [TokenKind.PRIVATE, TokenKind.FOREIGN, TokenKind.SPECIFIC]
    }
    if (modifier == TokenKind.SPECIFIC) { return [TokenKind.PRIVATE, TokenKind.COMMON] }
    return None
}

private func TopLevelMacroRule(modifier: TokenKind): Option<Array<TokenKind>> {
    return TopLevelCommonRule(modifier)
}

private func TopLevelMainRule(modifier: TokenKind): Option<Array<TokenKind>> {
    if (modifier == TokenKind.UNSAFE) { return NoConflicts() }
    return None
}

private func ClassBodyFuncRule(modifier: TokenKind): Option<Array<TokenKind>> {
    if (modifier == TokenKind.CONST) { return [TokenKind.OPEN] }
    if (modifier == TokenKind.STATIC) { return [TokenKind.OVERRIDE, TokenKind.OPEN, TokenKind.OPERATOR] }
    if (modifier == TokenKind.PUBLIC) { return AccessPublic() }
    if (modifier == TokenKind.PRIVATE) { return [TokenKind.PUBLIC, TokenKind.INTERNAL, TokenKind.PROTECTED, TokenKind.OPEN] }
    if (modifier == TokenKind.INTERNAL) { return [TokenKind.PUBLIC, TokenKind.PRIVATE, TokenKind.PROTECTED, TokenKind.OPEN] }
    if (modifier == TokenKind.PROTECTED) { return AccessProtected() }
    if (modifier == TokenKind.OVERRIDE) { return OverrideStaticRedef() }
    if (modifier == TokenKind.REDEF) { return RedefOverrideOpenOperator() }
    if (modifier == TokenKind.ABSTRACT) { return NoConflicts() }
    if (modifier == TokenKind.OPEN) {
        return [TokenKind.CONST, TokenKind.STATIC, TokenKind.PRIVATE, TokenKind.INTERNAL, TokenKind.REDEF]
    }
    if (modifier == TokenKind.UNSAFE) { return NoConflicts() }
    if (modifier == TokenKind.OPERATOR) { return OverrideStaticRedef() }
    if (modifier == TokenKind.COMMON) { return CommonSpecific() }
    if (modifier == TokenKind.SPECIFIC) { return SpecificCommon() }
    return None
}

private func InterfaceBodyFuncRule(modifier: TokenKind): Option<Array<TokenKind>> {
    if (modifier == TokenKind.CONST) { return NoConflicts() }
    if (modifier == TokenKind.STATIC) { return [TokenKind.OVERRIDE, TokenKind.OPEN, TokenKind.MUT, TokenKind.OPERATOR] }
    if (modifier == TokenKind.PUBLIC) { return NoConflicts() }
    if (modifier == TokenKind.OVERRIDE) { return OverrideStaticRedef() }
    if (modifier == TokenKind.REDEF) { return RedefOverrideOpenOperator() }
    if (modifier == TokenKind.OPEN) { return OpenStaticRedef() }
    if (modifier == TokenKind.MUT) { return MutStatic() }
    if (modifier == TokenKind.UNSAFE) { return NoConflicts() }
    if (modifier == TokenKind.OPERATOR) { return OperatorStatic() }
    if (modifier == TokenKind.COMMON) { return CommonSpecific() }
    if (modifier == TokenKind.SPECIFIC) { return SpecificCommon() }
    return None
}

private func StructBodyFuncRule(modifier: TokenKind): Option<Array<TokenKind>> {
    if (modifier == TokenKind.CONST) { return [TokenKind.MUT] }
    if (modifier == TokenKind.STATIC) { return [TokenKind.MUT, TokenKind.OPERATOR] }
    if (modifier == TokenKind.PUBLIC) { return AccessPublic() }
    if (modifier == TokenKind.PRIVATE) { return AccessPrivate() }
    if (modifier == TokenKind.INTERNAL) { return AccessInternal() }
    if (modifier == TokenKind.PROTECTED) { return AccessProtected() }
    if (modifier == TokenKind.OVERRIDE) { return OverrideStaticRedef() }
    if (modifier == TokenKind.REDEF) { return RedefOverrideOpenOperator() }
    if (modifier == TokenKind.MUT) { return [TokenKind.CONST, TokenKind.STATIC] }
    if (modifier == TokenKind.UNSAFE) { return NoConflicts() }
    if (modifier == TokenKind.OPERATOR) { return OperatorStatic() }
    if (modifier == TokenKind.COMMON) { return CommonSpecific() }
    if (modifier == TokenKind.SPECIFIC) { return SpecificCommon() }
    return None
}

private func EnumBodyFuncRule(modifier: TokenKind): Option<Array<TokenKind>> {
    if (modifier == TokenKind.CONST) { return NoConflicts() }
    if (modifier == TokenKind.STATIC) { return [TokenKind.OPERATOR] }
    if (modifier == TokenKind.PUBLIC) { return AccessPublic() }
    if (modifier == TokenKind.PRIVATE) { return AccessPrivate() }
    if (modifier == TokenKind.INTERNAL) { return AccessInternal() }
    if (modifier == TokenKind.PROTECTED) { return AccessProtected() }
    if (modifier == TokenKind.OVERRIDE) { return OverrideStaticRedef() }
    if (modifier == TokenKind.REDEF) { return [TokenKind.OVERRIDE, TokenKind.OPERATOR] }
    if (modifier == TokenKind.UNSAFE) { return NoConflicts() }
    if (modifier == TokenKind.OPERATOR) { return [TokenKind.STATIC] }
    if (modifier == TokenKind.COMMON) { return CommonSpecific() }
    if (modifier == TokenKind.SPECIFIC) { return SpecificCommon() }
    return None
}

private func FuncBodyFuncRule(modifier: TokenKind): Option<Array<TokenKind>> {
    if (modifier == TokenKind.CONST) { return NoConflicts() }
    if (modifier == TokenKind.UNSAFE) { return NoConflicts() }
    return None
}

private func ExtendBodyFuncRule(modifier: TokenKind): Option<Array<TokenKind>> {
    if (modifier == TokenKind.CONST) { return NoConflicts() }
    if (modifier == TokenKind.STATIC) { return [TokenKind.MUT, TokenKind.OPERATOR] }
    if (modifier == TokenKind.PUBLIC) { return AccessPublic() }
    if (modifier == TokenKind.PRIVATE) { return AccessPrivate() }
    if (modifier == TokenKind.INTERNAL) { return AccessInternal() }
    if (modifier == TokenKind.PROTECTED) { return AccessProtected() }
    if (modifier == TokenKind.MUT) { return MutStatic() }
    if (modifier == TokenKind.UNSAFE) { return NoConflicts() }
    if (modifier == TokenKind.OPERATOR) { return OperatorStatic() }
    if (modifier == TokenKind.COMMON) { return CommonSpecific() }
    if (modifier == TokenKind.SPECIFIC) { return SpecificCommon() }
    return None
}

private func ClassStructBodyVarRule(modifier: TokenKind): Option<Array<TokenKind>> {
    if (modifier == TokenKind.CONST) { return NoConflicts() }
    if (modifier == TokenKind.STATIC) { return NoConflicts() }
    if (modifier == TokenKind.PUBLIC) { return AccessPublic() }
    if (modifier == TokenKind.PRIVATE) { return AccessPrivate() }
    if (modifier == TokenKind.INTERNAL) { return AccessInternal() }
    if (modifier == TokenKind.PROTECTED) { return AccessProtected() }
    if (modifier == TokenKind.COMMON) { return CommonSpecific() }
    if (modifier == TokenKind.SPECIFIC) { return SpecificCommon() }
    return None
}

private func FuncBodyVarRule(modifier: TokenKind): Option<Array<TokenKind>> {
    if (modifier == TokenKind.CONST) { return NoConflicts() }
    return None
}

private func ClassBodyPropRule(modifier: TokenKind): Option<Array<TokenKind>> {
    if (modifier == TokenKind.STATIC) { return StaticOverrideOpen() }
    if (modifier == TokenKind.PUBLIC) { return AccessPublic() }
    if (modifier == TokenKind.PRIVATE) { return [TokenKind.PUBLIC, TokenKind.INTERNAL, TokenKind.PROTECTED, TokenKind.OPEN] }
    if (modifier == TokenKind.INTERNAL) { return [TokenKind.PUBLIC, TokenKind.PRIVATE, TokenKind.PROTECTED, TokenKind.OPEN] }
    if (modifier == TokenKind.PROTECTED) { return AccessProtected() }
    if (modifier == TokenKind.OVERRIDE) { return OverrideStaticRedef() }
    if (modifier == TokenKind.REDEF) { return RedefOverrideOpen() }
    if (modifier == TokenKind.ABSTRACT) { return NoConflicts() }
    if (modifier == TokenKind.OPEN) { return [TokenKind.STATIC, TokenKind.PRIVATE, TokenKind.INTERNAL, TokenKind.REDEF] }
    if (modifier == TokenKind.MUT) { return NoConflicts() }
    if (modifier == TokenKind.COMMON) { return CommonSpecific() }
    if (modifier == TokenKind.SPECIFIC) { return SpecificCommon() }
    return None
}

private func InterfaceBodyPropRule(modifier: TokenKind): Option<Array<TokenKind>> {
    if (modifier == TokenKind.STATIC) { return StaticOverrideOpen() }
    if (modifier == TokenKind.PUBLIC) { return NoConflicts() }
    if (modifier == TokenKind.OVERRIDE) { return OverrideStaticRedef() }
    if (modifier == TokenKind.REDEF) { return RedefOverrideOpen() }
    if (modifier == TokenKind.OPEN) { return OpenStaticRedef() }
    if (modifier == TokenKind.MUT) { return NoConflicts() }
    if (modifier == TokenKind.COMMON) { return CommonSpecific() }
    if (modifier == TokenKind.SPECIFIC) { return SpecificCommon() }
    return None
}

private func StructBodyPropRule(modifier: TokenKind): Option<Array<TokenKind>> {
    if (modifier == TokenKind.STATIC) { return StaticOverride() }
    if (modifier == TokenKind.PUBLIC) { return AccessPublic() }
    if (modifier == TokenKind.PRIVATE) { return AccessPrivate() }
    if (modifier == TokenKind.INTERNAL) { return AccessInternal() }
    if (modifier == TokenKind.PROTECTED) { return AccessProtected() }
    if (modifier == TokenKind.OVERRIDE) { return OverrideStaticRedef() }
    if (modifier == TokenKind.REDEF) { return RedefOverride() }
    if (modifier == TokenKind.MUT) { return NoConflicts() }
    if (modifier == TokenKind.COMMON) { return CommonSpecific() }
    if (modifier == TokenKind.SPECIFIC) { return SpecificCommon() }
    return None
}

private func EnumBodyPropRule(modifier: TokenKind): Option<Array<TokenKind>> {
    if (modifier == TokenKind.STATIC) { return StaticOverride() }
    if (modifier == TokenKind.PUBLIC) { return AccessPublic() }
    if (modifier == TokenKind.PRIVATE) { return AccessPrivate() }
    if (modifier == TokenKind.INTERNAL) { return AccessInternal() }
    if (modifier == TokenKind.PROTECTED) { return AccessProtected() }
    if (modifier == TokenKind.OVERRIDE) { return OverrideStaticRedef() }
    if (modifier == TokenKind.REDEF) { return RedefOverride() }
    if (modifier == TokenKind.COMMON) { return CommonSpecific() }
    if (modifier == TokenKind.SPECIFIC) { return SpecificCommon() }
    return None
}

private func ExtendBodyPropRule(modifier: TokenKind): Option<Array<TokenKind>> {
    if (modifier == TokenKind.STATIC) { return NoConflicts() }
    if (modifier == TokenKind.PUBLIC) { return AccessPublic() }
    if (modifier == TokenKind.PRIVATE) { return AccessPrivate() }
    if (modifier == TokenKind.INTERNAL) { return AccessInternal() }
    if (modifier == TokenKind.PROTECTED) { return AccessProtected() }
    if (modifier == TokenKind.MUT) { return NoConflicts() }
    if (modifier == TokenKind.COMMON) { return CommonSpecific() }
    if (modifier == TokenKind.SPECIFIC) { return SpecificCommon() }
    return None
}

private func AggregateBodyInstanceInitRule(modifier: TokenKind): Option<Array<TokenKind>> {
    if (modifier == TokenKind.CONST) { return NoConflicts() }
    if (modifier == TokenKind.PUBLIC) { return AggPublic() }
    if (modifier == TokenKind.PRIVATE) { return AggPrivate() }
    if (modifier == TokenKind.INTERNAL) { return AggInternal() }
    if (modifier == TokenKind.PROTECTED) { return AggProtected() }
    return None
}

private func AggregateBodyInitRule(modifier: TokenKind): Option<Array<TokenKind>> {
    if (modifier == TokenKind.CONST) { return NoConflicts() }
    if (modifier == TokenKind.STATIC) {
        return [TokenKind.PUBLIC, TokenKind.PRIVATE, TokenKind.INTERNAL, TokenKind.PROTECTED]
    }
    if (modifier == TokenKind.PUBLIC) { return AggPublic() }
    if (modifier == TokenKind.PRIVATE) { return AggPrivate() }
    if (modifier == TokenKind.INTERNAL) { return AggInternal() }
    if (modifier == TokenKind.PROTECTED) { return AggProtected() }
    if (modifier == TokenKind.COMMON) { return CommonSpecific() }
    if (modifier == TokenKind.SPECIFIC) { return SpecificCommon() }
    return None
}

private func EmptyScopeRule(defKind: DefKind, scopeKind: ScopeKind): Bool {
    return (defKind == DefKind.EXTEND && ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) ||
        (defKind == DefKind.FINALIZER && ScopeKindEquals(scopeKind, ScopeKind.CLASS_BODY))
}

private func FindRule(defKind: DefKind, scopeKind: ScopeKind, modifier: TokenKind): Option<Array<TokenKind>> {
    if (defKind == DefKind.FUNC) {
        if (ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) { return TopLevelFuncRule(modifier) }
        if (ScopeKindEquals(scopeKind, ScopeKind.CLASS_BODY)) { return ClassBodyFuncRule(modifier) }
        if (ScopeKindEquals(scopeKind, ScopeKind.INTERFACE_BODY)) { return InterfaceBodyFuncRule(modifier) }
        if (ScopeKindEquals(scopeKind, ScopeKind.STRUCT_BODY)) { return StructBodyFuncRule(modifier) }
        if (ScopeKindEquals(scopeKind, ScopeKind.EXTEND_BODY)) { return ExtendBodyFuncRule(modifier) }
        if (ScopeKindEquals(scopeKind, ScopeKind.FUNC_BODY)) { return FuncBodyFuncRule(modifier) }
        if (ScopeKindEquals(scopeKind, ScopeKind.ENUM_BODY)) { return EnumBodyFuncRule(modifier) }
        return None
    }
    if (defKind == DefKind.MAIN) {
        if (ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) { return TopLevelMainRule(modifier) }
        return None
    }
    if (defKind == DefKind.MACRO) {
        if (ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) { return TopLevelMacroRule(modifier) }
        return None
    }
    if (defKind == DefKind.CLASS) {
        if (ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) { return TopLevelClassRule(modifier) }
        return None
    }
    if (defKind == DefKind.INTERFACE) {
        if (ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) { return TopLevelInterfaceRule(modifier) }
        return None
    }
    if (defKind == DefKind.VARIABLE) {
        if (ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) { return TopLevelVariableRule(modifier) }
        if (ScopeKindEquals(scopeKind, ScopeKind.CLASS_BODY) || ScopeKindEquals(scopeKind, ScopeKind.STRUCT_BODY)) {
            return ClassStructBodyVarRule(modifier)
        }
        if (ScopeKindEquals(scopeKind, ScopeKind.FUNC_BODY) || ScopeKindEquals(scopeKind, ScopeKind.MACRO_BODY)) {
            return FuncBodyVarRule(modifier)
        }
        if (ScopeKindEquals(scopeKind, ScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_CLASS) ||
            ScopeKindEquals(scopeKind, ScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_STRUCT)) {
            return AggregateBodyInstanceInitRule(modifier)
        }
        return None
    }
    if (defKind == DefKind.ENUM) {
        if (ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) { return TopLevelEnumStructRule(modifier) }
        return None
    }
    if (defKind == DefKind.STRUCT) {
        if (ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) { return TopLevelEnumStructRule(modifier) }
        return None
    }
    if (defKind == DefKind.TYPE) {
        if (ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) { return TopLevelCommonRule(modifier) }
        return None
    }
    if (defKind == DefKind.CONSTRUCTOR) {
        if (ScopeKindEquals(scopeKind, ScopeKind.CLASS_BODY) || ScopeKindEquals(scopeKind, ScopeKind.STRUCT_BODY)) {
            return AggregateBodyInitRule(modifier)
        }
        return None
    }
    if (defKind == DefKind.PRIMARY_CONSTRUCTOR) {
        if (ScopeKindEquals(scopeKind, ScopeKind.CLASS_BODY) || ScopeKindEquals(scopeKind, ScopeKind.STRUCT_BODY)) {
            return AggregateBodyInstanceInitRule(modifier)
        }
        return None
    }
    if (defKind == DefKind.PROPERTY) {
        if (ScopeKindEquals(scopeKind, ScopeKind.CLASS_BODY)) { return ClassBodyPropRule(modifier) }
        if (ScopeKindEquals(scopeKind, ScopeKind.INTERFACE_BODY)) { return InterfaceBodyPropRule(modifier) }
        if (ScopeKindEquals(scopeKind, ScopeKind.STRUCT_BODY)) { return StructBodyPropRule(modifier) }
        if (ScopeKindEquals(scopeKind, ScopeKind.EXTEND_BODY)) { return ExtendBodyPropRule(modifier) }
        if (ScopeKindEquals(scopeKind, ScopeKind.ENUM_BODY)) { return EnumBodyPropRule(modifier) }
        return None
    }
    if (defKind == DefKind.PACKAGE) {
        if (ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) { return PackageRule(modifier) }
        return None
    }
    return None
}

public func HasScopeRules(defKind: DefKind, scopeKind: ScopeKind): Bool {
    if (EmptyScopeRule(defKind, scopeKind)) { return true }
    for (modifier in [
        TokenKind.CONST, TokenKind.STATIC, TokenKind.PUBLIC, TokenKind.PRIVATE, TokenKind.INTERNAL,
        TokenKind.PROTECTED, TokenKind.OVERRIDE, TokenKind.REDEF, TokenKind.ABSTRACT, TokenKind.SEALED,
        TokenKind.OPEN, TokenKind.FOREIGN, TokenKind.INOUT, TokenKind.MUT, TokenKind.UNSAFE, TokenKind.OPERATOR,
        TokenKind.COMMON, TokenKind.SPECIFIC
    ]) {
        if (FindRule(defKind, scopeKind, modifier).isSome()) { return true }
    }
    return false
}

public func IsScopeRulesEmpty(defKind: DefKind, scopeKind: ScopeKind): Bool {
    if (EmptyScopeRule(defKind, scopeKind)) { return true }
    return !HasScopeRules(defKind, scopeKind)
}

public func IsModifierAllowed(defKind: DefKind, scopeKind: ScopeKind, modifier: TokenKind): Bool {
    return FindRule(defKind, scopeKind, modifier).isSome()
}

public func GetConflictingModifiers(defKind: DefKind, scopeKind: ScopeKind, modifier: TokenKind): ConflictArray {
    if (let Some(conflicts) <- FindRule(defKind, scopeKind, modifier)) {
        return ConflictArray(conflicts)
    }
    return ConflictArray()
}

public func HasWarningRules(defKind: DefKind, scopeKind: ScopeKind): Bool {
    return (defKind == DefKind.FUNC && ScopeKindEquals(scopeKind, ScopeKind.INTERFACE_BODY)) ||
        (defKind == DefKind.CLASS && ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) ||
        (defKind == DefKind.INTERFACE && ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) ||
        (defKind == DefKind.PROPERTY && ScopeKindEquals(scopeKind, ScopeKind.INTERFACE_BODY))
}

public func GetWarningConflicts(defKind: DefKind, scopeKind: ScopeKind, modifier: TokenKind): ConflictArray {
    if (defKind == DefKind.CLASS && ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) {
        if (modifier == TokenKind.PUBLIC) { return ConflictArray(PublicSealed()) }
        if (modifier == TokenKind.OPEN) { return ConflictArray([TokenKind.SEALED, TokenKind.ABSTRACT]) }
    }
    if (defKind == DefKind.INTERFACE && ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) {
        if (modifier == TokenKind.PUBLIC) { return ConflictArray(PublicSealed()) }
        if (modifier == TokenKind.OPEN) { return ConflictArray([TokenKind.SEALED, TokenKind.ILLEGAL]) }
    }
    if ((defKind == DefKind.FUNC || defKind == DefKind.PROPERTY) &&
        ScopeKindEquals(scopeKind, ScopeKind.INTERFACE_BODY)) {
        if (modifier == TokenKind.PUBLIC) { return ConflictArray(IllegalOnly()) }
        if (modifier == TokenKind.OPEN) { return ConflictArray(IllegalOnly()) }
    }
    return ConflictArray()
}

public func GetAttributeByModifier(tokenKind: TokenKind): Option<Attribute> {
    if (tokenKind == TokenKind.PUBLIC) { return Attribute.PUBLIC }
    if (tokenKind == TokenKind.PROTECTED) { return Attribute.PROTECTED }
    if (tokenKind == TokenKind.INTERNAL) { return Attribute.INTERNAL }
    if (tokenKind == TokenKind.PRIVATE) { return Attribute.PRIVATE }
    if (tokenKind == TokenKind.STATIC) { return Attribute.STATIC }
    if (tokenKind == TokenKind.ABSTRACT) { return Attribute.ABSTRACT }
    if (tokenKind == TokenKind.OPEN) { return Attribute.OPEN }
    if (tokenKind == TokenKind.SEALED) { return Attribute.SEALED }
    if (tokenKind == TokenKind.OVERRIDE) { return Attribute.OVERRIDE }
    if (tokenKind == TokenKind.REDEF) { return Attribute.REDEF }
    if (tokenKind == TokenKind.FOREIGN) { return Attribute.FOREIGN }
    if (tokenKind == TokenKind.INOUT) { return None }
    if (tokenKind == TokenKind.MUT) { return Attribute.MUT }
    if (tokenKind == TokenKind.UNSAFE) { return Attribute.UNSAFE }
    if (tokenKind == TokenKind.OPERATOR) { return Attribute.OPERATOR }
    if (tokenKind == TokenKind.CONST) { return None }
    if (tokenKind == TokenKind.COMMON) { return Attribute.COMMON }
    if (tokenKind == TokenKind.SPECIFIC) { return Attribute.SPECIFIC }
    return None
}
