package cjcj::parse

import cjcj::ast.IsStaticInitializer
import cjcj::option.OutputModeIndex as OptionOutputModeIndex
import std.collection.*

public class MPParserImpl {
    public let parser: ParserImpl
    private var opts: Option<GlobalOptions> = None

    public init(parser: ParserImpl) {
        this.parser = parser
        this.opts = parser.compileOptions
    }

    public func SetCompileOptions(opts: GlobalOptions): Unit {
        this.opts = opts
    }

    public func ParseCJMPDecl(scopeKind: ScopeKind): Decl {
        let decl = parser.ParseDecl(scopeKind)
        CheckCJMPDecl(decl)
        return decl
    }

    public func CheckCJMPModifiers(modifiers: ArrayList<Modifier>): Bool {
        for (modifier in modifiers) {
            if (modifier.modifier == TokenKind.SPECIFIC) {
                let currentFile = parser.currentFile.getOrThrow()
                if (!CompilePlatform() && !CompileCommon()) {
                    parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_unexpected_cjmp_decl, currentFile).Emit()
                    return false
                }
                if (let Some(packageSpec) <- currentFile.packageSpec) {
                    packageSpec.hasSpecific = true
                }
                currentFile.isSpecific = true
                break
            }
        }
        for (modifier in modifiers) {
            if (modifier.modifier == TokenKind.COMMON) {
                let currentFile = parser.currentFile.getOrThrow()
                if (!CompilePlatform() && !CompileCommon()) {
                    parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_unexpected_cjmp_decl, currentFile).Emit()
                    return false
                }
                if (let Some(packageSpec) <- currentFile.packageSpec) {
                    packageSpec.hasCommon = true
                }
                currentFile.isCommon = true
                break
            }
        }
        return true
    }

    public func CheckCJMPDecl(decl: Decl): Unit {
        if (!CompileCommon() && !CompilePlatform()) {
            return
        }
        if (!CheckCJMPModifiersOf(decl)) {
            return
        }
        SetCJMPAttrs(decl)
        if (decl.TestAttr(Attribute.COMMON) && IsCJMPAggregateDecl(decl)) {
            var allMembersHaveDefault = true
            for (member in decl.GetMemberDecls()) {
                if (member.TestAttr(Attribute.COMMON) &&
                    !member.TestAttr(Attribute.COMMON_WITH_DEFAULT) &&
                    !member.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
                    allMembersHaveDefault = false
                    break
                }
            }
            if (allMembersHaveDefault) {
                decl.EnableAttr(Attribute.COMMON_WITH_DEFAULT)
            }
        }
        if (let Some(interfaceDecl) <- (decl as InterfaceDecl)) {
            CheckSpecificInterface(interfaceDecl)
        } else if ((decl.astKind == ASTKind.CLASS_DECL || decl.astKind == ASTKind.STRUCT_DECL) &&
            decl.TestAttr(Attribute.COMMON)) {
            CheckCJMPCtorPresence(decl)
        }
    }

    public func HasCJMPModifiers(modifier: Modifier): Bool {
        if (!CompileCommon() && !CompilePlatform()) {
            return false
        }
        return modifier.modifier == TokenKind.COMMON || modifier.modifier == TokenKind.SPECIFIC
    }

    public func CheckCJMPCtorPresence(decl: Decl): Unit {
        if (decl.astKind != ASTKind.CLASS_DECL && decl.astKind != ASTKind.STRUCT_DECL) {
            return
        }
        var hasCtor = false
        for (member in decl.GetMemberDecls()) {
            if (member.TestAttr(Attribute.CONSTRUCTOR) || member.TestAttr(Attribute.PRIMARY_CONSTRUCTOR)) {
                hasCtor = true
                break
            }
        }
        if (!hasCtor) {
            let declType = if (decl.astKind == ASTKind.CLASS_DECL) { "class" } else { "struct" }
            parser.ParseDiagnoseRefactor(
                DiagKindRefactor.parse_cjmp_in_common_ctor_required,
                MakeRange(decl.identifier.Begin(), decl.identifier.End()),
                declType,
                decl.identifier.Val()).Emit()
        }
    }

    private func CheckCJMPModifiersOf(decl: Decl): Bool {
        var ok = true
        if (decl.IsCommonOrSpecific()) {
            let kind = if (decl.TestAttr(Attribute.COMMON)) { "common" } else { "specific" }
            if (decl.TestAttr(Attribute.GENERIC) && !CheckGenericDeclFrozen(decl, parser)) {
                return false
            }
            if (decl.astKind == ASTKind.VAR_WITH_PATTERN_DECL && decl.TestAttr(Attribute.COMMON)) {
                if (let Some(varDecl) <- (decl as VarWithPatternDecl)) {
                    if (let Some(pattern) <- varDecl.irrefutablePattern) {
                        parser.ParseDiagnoseRefactor(
                            DiagKindRefactor.parse_cjmp_pattern_decl,
                            pattern,
                            GetDiagKind(pattern),
                            kind).Emit()
                    }
                }
                return false
            }
            if (IsStaticInitializer(decl)) {
                parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_cjmp_static_init, decl, kind).Emit()
                return false
            }
        }
        for (member in decl.GetMemberDecls()) {
            ok = CheckCJMPModifiersBetween(member, decl) && ok
            CheckCJMPDecl(member)
        }
        return ok
    }

    private func CheckCJMPModifiersBetween(inner: Decl, outer: Decl): Bool {
        let innerDesc = GetDiagKind(inner) + " " + inner.identifier.Val()
        if (inner.TestAttr(Attribute.COMMON) && !outer.TestAnyAttr(Attribute.COMMON, Attribute.SPECIFIC)) {
            DiagOuterDeclMissMatch(inner, innerDesc, "common", GetDiagKind(outer), "common")
            return false
        }
        if (inner.TestAttr(Attribute.SPECIFIC) && !outer.TestAttr(Attribute.SPECIFIC)) {
            DiagOuterDeclMissMatch(inner, innerDesc, "specific", GetDiagKind(outer), "specific")
            return false
        }
        return true
    }

    private func CheckSpecificInterface(decl: InterfaceDecl): Unit {
        if (!decl.TestAttr(Attribute.SPECIFIC)) {
            return
        }
        for (member in decl.GetMemberDecls()) {
            if (!HasDefault(member)) {
                parser.ParseDiagnoseRefactor(
                    DiagKindRefactor.parse_specific_member_must_have_implementation,
                    member,
                    member.identifier.Val(),
                    decl.identifier.Val()).Emit()
                member.EnableAttr(Attribute.IS_BROKEN)
            }
        }
    }

    private func DiagOuterDeclMissMatch(node: Decl, p0: String, p1: String, p2: String, p3: String): Unit {
        parser.ParseDiagnoseRefactor(
            DiagKindRefactor.parse_cjmp_outdecl_miss_match,
            node,
            arguments: [p0, p1, p2, p3]).Emit()
        node.EnableAttr(Attribute.IS_BROKEN)
    }

    private func CompileCommon(): Bool {
        if (let Some(options) <- opts) {
            return OptionOutputModeIndex(options.outputMode) == OptionOutputModeIndex(OutputMode.CHIR)
        }
        return false
    }

    private func CompilePlatform(): Bool {
        if (let Some(options) <- opts) {
            return options.commonPartCjos.size > 0
        }
        return false
    }
}

private func CheckGenericDeclFrozen(decl: Decl, parser: ParserImpl): Bool {
    if (decl.HasAnno(AnnotationKind.FROZEN)) {
        var reportAt: Node = decl
        for (anno in decl.annotations) {
            if (anno.kind == AnnotationKind.FROZEN) {
                reportAt = anno
                break
            }
        }
        parser.ParseDiagnoseRefactor(
            DiagKindRefactor.sema_common_generic_frozen_not_supported,
            reportAt,
            decl.identifier.Val()).Emit()
        return false
    }
    return true
}

private func HasDefault(decl: Decl): Bool {
    if (decl.TestAttr(Attribute.SPECIFIC)) {
        return true
    }
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        if (let Some(body) <- funcDecl.funcBody) {
            if (let Some(_) <- body.body) {
                return true
            }
        }
    }
    if (let Some(propDecl) <- (decl as PropDecl)) {
        if (!propDecl.getters.isEmpty()) { return true }
        if (!propDecl.setters.isEmpty()) { return true }
    }
    if (let Some(varDecl) <- (decl as VarDeclAbstract)) {
        if (let Some(_) <- varDecl.initializer) {
            return true
        }
    }
    if (let Some(patternDecl) <- (decl as VarWithPatternDecl)) {
        if (let Some(_) <- patternDecl.initializer) {
            return true
        }
    }
    return false
}

private func SetCJMPAttrs(decl: Decl): Unit {
    if (!decl.TestAttr(Attribute.COMMON)) {
        return
    }
    if (HasDefault(decl)) {
        decl.EnableAttr(Attribute.COMMON_WITH_DEFAULT)
    }
}

private func IsCJMPAggregateDecl(decl: Decl): Bool {
    return decl.astKind == ASTKind.CLASS_DECL || decl.astKind == ASTKind.INTERFACE_DECL ||
        decl.astKind == ASTKind.STRUCT_DECL || decl.astKind == ASTKind.ENUM_DECL ||
        decl.astKind == ASTKind.EXTEND_DECL
}

private func GetDiagKind(node: Node): String {
    if (node.astKind == ASTKind.FUNC_DECL && node.TestAttr(Attribute.CONSTRUCTOR)) {
        return "constructor"
    }
    return match (node.astKind) {
        case ASTKind.VAR_DECL => "variable"
        case ASTKind.VAR_WITH_PATTERN_DECL => "variable"
        case ASTKind.PRIMARY_CTOR_DECL => "primary constructor"
        case ASTKind.FUNC_DECL => "function"
        case ASTKind.CLASS_DECL => "class"
        case ASTKind.INTERFACE_DECL => "interface"
        case ASTKind.STRUCT_DECL => "struct"
        case ASTKind.ENUM_DECL => "enum"
        case ASTKind.PROP_DECL => "property"
        case ASTKind.EXTEND_DECL => "extend"
        case ASTKind.ENUM_PATTERN => "enum"
        case ASTKind.TUPLE_PATTERN => "tuple"
        case ASTKind.WILDCARD_PATTERN => "wildcard"
        case ASTKind.FUNC_PARAM => "parameter"
        case ASTKind.TYPE_ALIAS_DECL => "type"
        case ASTKind.MACRO_EXPAND_DECL => "macro_expand_decl"
        case _ => "declaration"
    }
}
