package cangjie_compiler::ast

import std.collection.*

public func AddMacroAttr(node: Node): Unit {
    if (let Some(macroCall) <- node.curMacroCall) {
        let curFile = node.curFile
        let walker = Walker(node, visitPre: { curNode: Node =>
            curNode.curMacroCall = macroCall
            curNode.curFile = curFile
            curNode.EnableAttr(Attribute.MACRO_EXPANDED_NODE)
            VisitAction.WALK_CHILDREN
        })
        walker.Walk()
    }
}

public func AddCurFile(root: Node, file!: Option<File> = None): Unit {
    if (let Some(pkg) <- (root as Package)) {
        for (pkgFile in pkg.files) {
            pkgFile.curPackage = pkg
            assignCurFile(pkgFile, pkgFile)
        }
        return
    }
    if (let Some(fileNode) <- (root as File)) {
        assignCurFile(fileNode, fileNode)
        return
    }
    if (let Some(value) <- file) {
        assignCurFile(root, value)
    }
}

private func assignCurFile(root: Node, file: File): Unit {
    let walker = Walker(root, visitPre: { curNode: Node =>
        curNode.curFile = file
        if (let Some(_) <- curNode.curMacroCall) {
            AddMacroAttr(curNode)
            return VisitAction.SKIP_CHILDREN
        }
        VisitAction.WALK_CHILDREN
    })
    walker.Walk()
}

public func SortModifierByPos(modifiers: ArrayList<Modifier>): ArrayList<Modifier> {
    let out = ArrayList<Modifier>()
    for (modifier in modifiers) {
        var inserted = false
        var idx: Int64 = 0
        while (idx < out.size) {
            if (modifier.begin < out[idx].begin) {
                out.add(modifier, at: idx)
                inserted = true
                break
            }
            idx++
        }
        if (!inserted) {
            out.add(modifier)
        }
    }
    return out
}

public func IsInstanceConstructor(node: Node): Bool {
    return node.TestAttr(Attribute.CONSTRUCTOR) && !node.TestAttr(Attribute.STATIC)
}

public func IsStaticInitializer(decl: Decl): Bool {
    return decl.TestAttr(Attribute.STATIC) && decl.TestAttr(Attribute.CONSTRUCTOR)
}

public func IsClassOrEnumConstructor(decl: Decl): Bool {
    return IsInstanceConstructor(decl) || decl.TestAttr(Attribute.ENUM_CONSTRUCTOR)
}

public func IsGlobalOrMember(node: Node): Bool {
    return node.TestAnyAttr(Attribute.GLOBAL, Attribute.IN_CLASSLIKE, Attribute.IN_ENUM) ||
        node.TestAnyAttr(Attribute.IN_STRUCT, Attribute.IN_EXTEND)
}

public func IsInstanceMember(decl: Decl): Bool {
    if (let Some(outer) <- decl.outerDecl) {
        return outer.IsNominalDecl() && !decl.TestAttr(Attribute.STATIC)
    }
    return false
}

public func IsGlobalOrStaticVar(decl: Decl): Bool {
    return decl.astKind == ASTKind.VAR_DECL && decl.TestAnyAttr(Attribute.STATIC, Attribute.GLOBAL)
}

public func IsInheritableClass(decl: Decl): Bool {
    return decl.astKind == ASTKind.CLASS_DECL && decl.TestAnyAttr(Attribute.OPEN, Attribute.ABSTRACT)
}

public func IsMemberParam(decl: Decl): Bool {
    if (let Some(param) <- (decl as FuncParam)) {
        return param.isMemberParam
    }
    return false
}

public func IsSingleRuneStringLiteral(expr: Expr): Bool {
    if (let Some(lit) <- (expr as LitConstExpr)) {
        return lit.kind == LitConstKind.STRING && lit.codepoint.size == 1
    }
    return false
}

public func IsSingleByteStringLiteral(expr: Expr): Bool {
    if (let Some(lit) <- (expr as LitConstExpr)) {
        return IsSingleRuneStringLiteral(expr) && lit.codepoint[0] <= 255u32
    }
    return false
}

public class FloatTypeInfo {
    public var inf: UInt64 = 0
    public var min: String = ""
    public var max: String = ""

    public init() {}

    public init(inf: UInt64, min: String, max: String) {
        this.inf = inf
        this.min = min
        this.max = max
    }
}

public func GetFloatTypeInfoByKind(kind: TypeKind): FloatTypeInfo {
    if (kind == TypeKind.TYPE_FLOAT16) {
        return FloatTypeInfo(0xF800, "5.960464477539063E-8", "6.5504E4")
    }
    if (kind == TypeKind.TYPE_FLOAT32) {
        return FloatTypeInfo(0xFF000000, "1.40129846E-45", "3.40282347E38")
    }
    return FloatTypeInfo(0xFFE0000000000000, "4.9406564584124654E-324", "1.7976931348623157E308")
}

public func InitializeLitConstValue(lce: LitConstExpr): Unit {
    // TODO(selfhost:AST): finish exact C++ literal constant initialization after Sema type manager is available.
    lce.isConst = true
    if (lce.kind == LitConstKind.INTEGER || lce.kind == LitConstKind.RUNE_BYTE) {
        lce.constNumValue.asInt.InitIntLiteral(lce.stringValue, lce.GetNumLitTypeKind())
    }
}

public func FlattenVarWithPatternDecl(vwpDecl: VarWithPatternDecl): ArrayList<Pattern> {
    let out = ArrayList<Pattern>()
    if (let Some(pattern) <- vwpDecl.irrefutablePattern) {
        out.add(pattern)
    }
    return out
}

public func GetAnnotatedDeclKindString(decl: Decl): String {
    return ASTKindName(decl.astKind)
}

public func GetAccessLevel(node: Node): AccessLevel {
    if (node.TestAttr(Attribute.PRIVATE)) { return AccessLevel.PRIVATE }
    if (node.TestAttr(Attribute.PROTECTED)) { return AccessLevel.PROTECTED }
    if (node.TestAttr(Attribute.PUBLIC)) { return AccessLevel.PUBLIC }
    return AccessLevel.INTERNAL
}

public func GetAttrByAccessLevel(level: AccessLevel): Attribute {
    return match (level) {
        case AccessLevel.PRIVATE => Attribute.PRIVATE
        case AccessLevel.INTERNAL => Attribute.INTERNAL
        case AccessLevel.PROTECTED => Attribute.PROTECTED
        case AccessLevel.PUBLIC => Attribute.PUBLIC
    }
}

public func GetAccessLevelStr(node: Node): String {
    return match (GetAccessLevel(node)) {
        case AccessLevel.PRIVATE => "private"
        case AccessLevel.INTERNAL => "internal"
        case AccessLevel.PROTECTED => "protected"
        case AccessLevel.PUBLIC => "public"
    }
}

public func GetImportedItemFullName(content: ImportContent, commonPrefix!: String = ""): String {
    let item = content.GetImportedPackageName()
    if (commonPrefix.isEmpty()) {
        return item
    }
    return commonPrefix + "." + item
}

public func IsCondition(expr: Expr): Bool {
    if (let Some(_) <- (expr as LetPatternDestructor)) {
        return true
    }
    if (let Some(block) <- (expr as Block)) {
        for (node in block.body) {
            if (let Some(childExpr) <- (node as Expr)) {
                if (IsCondition(childExpr)) {
                    return true
                }
            }
        }
    }
    return false
}

public func IsNestedFunc(fd: FuncDecl): Bool {
    if (fd.TestAttr(Attribute.GLOBAL)) {
        return false
    }
    if (let Some(outer) <- fd.outerDecl) {
        return outer.IsFunc()
    }
    return true
}

public func IsDefaultImplementation(decl: Decl): Bool {
    if (!decl.TestAttr(Attribute.DEFAULT)) {
        return false
    }
    if (let Some(outer) <- decl.outerDecl) {
        return outer.astKind == ASTKind.INTERFACE_DECL
    }
    return false
}

public func IsStaticVar(decl: Decl): Bool {
    return decl.astKind == ASTKind.VAR_DECL && decl.TestAttr(Attribute.STATIC)
}
