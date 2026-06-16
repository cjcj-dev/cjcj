package cangjie_compiler::parse

import cangjie_compiler::option.OutputModeIndex as OptionOutputModeIndex
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
        var ok = true
        for (modifier in modifiers) {
            if (HasCJMPModifiers(modifier) && !CompilePlatform() && !CompileCommon()) {
                parser.diag.DiagnoseRefactor(
                    DiagKindRefactor.INVALID_MODIFIER,
                    modifier.begin,
                    "unexpected CJMP modifier '${TokenKindName(modifier.tokenKind)}' outside common/platform compilation")
                ok = false
            }
        }
        return ok
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
        return modifier.kind == ModifierKind.COMMON || modifier.kind == ModifierKind.SPECIFIC
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
            parser.diag.DiagnoseRefactor(
                DiagKindRefactor.PARSE_ERROR,
                decl.identifier.Begin(),
                "common ${declType} '${decl.identifier.Val()}' must declare a constructor")
        }
    }

    private func CheckCJMPModifiersOf(decl: Decl): Bool {
        var ok = true
        if (decl.IsCommonOrSpecific()) {
            let kind = if (decl.TestAttr(Attribute.COMMON)) { "common" } else { "specific" }
            if (decl.TestAttr(Attribute.GENERIC) && decl.HasAnno(AnnotationKind.FROZEN)) {
                parser.diag.DiagnoseRefactor(
                    DiagKindRefactor.INVALID_ANNOTATION,
                    decl.identifier.Begin(),
                    "${kind} generic declaration '${decl.identifier.Val()}' cannot use @Frozen")
                decl.EnableAttr(Attribute.IS_BROKEN)
                ok = false
            }
            if (decl.astKind == ASTKind.VAR_WITH_PATTERN_DECL && decl.TestAttr(Attribute.COMMON)) {
                parser.diag.DiagnoseRefactor(
                    DiagKindRefactor.INVALID_MODIFIER,
                    decl.begin,
                    "common modifier is not allowed on pattern variable declarations")
                decl.EnableAttr(Attribute.IS_BROKEN)
                ok = false
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
                parser.diag.DiagnoseRefactor(
                    DiagKindRefactor.PARSE_ERROR,
                    member.begin,
                    "specific interface member '${member.identifier.Val()}' in '${decl.identifier.Val()}' must have an implementation")
                member.EnableAttr(Attribute.IS_BROKEN)
            }
        }
    }

    private func DiagOuterDeclMissMatch(node: Decl, p0: String, p1: String, p2: String, p3: String): Unit {
        parser.diag.DiagnoseRefactor(
            DiagKindRefactor.INVALID_MODIFIER,
            node.begin,
            "${p0} is marked ${p1}, but enclosing ${p2} is not marked ${p3}")
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
        if (let Some(_) <- propDecl.getter) { return true }
        if (let Some(_) <- propDecl.setter) { return true }
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

private func GetDiagKind(node: Decl): String {
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
        case ASTKind.TYPE_ALIAS_DECL => "type"
        case ASTKind.MACRO_EXPAND_DECL => "macro_expand_decl"
        case _ => "declaration"
    }
}
