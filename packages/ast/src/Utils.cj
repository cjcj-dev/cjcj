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
    lce.isConst = true
    let primitiveKind = getPrimitiveLiteralKind(lce)
    if (lce.kind == LitConstKind.BOOL) {
        lce.constNumValue.asBoolean = lce.stringValue == "true"
        return
    }
    if (lce.kind == LitConstKind.UNIT || lce.kind == LitConstKind.NONE) {
        return
    }
    if (TypeKindInRange(primitiveKind, TypeKind.TYPE_INT8, TypeKind.TYPE_UINT_NATIVE) ||
        primitiveKind == TypeKind.TYPE_IDEAL_INT || lce.kind == LitConstKind.RUNE_BYTE ||
        lce.kind == LitConstKind.RUNE) {
        let value = if ((lce.kind == LitConstKind.STRING || lce.kind == LitConstKind.RUNE_BYTE ||
            lce.kind == LitConstKind.RUNE) && lce.codepoint.size == 1) {
            "${lce.codepoint[0]}"
        } else {
            lce.stringValue
        }
        lce.constNumValue.asInt.InitIntLiteral(value, primitiveKind)
        return
    }
    if (TypeKindInRange(primitiveKind, TypeKind.TYPE_FLOAT16, TypeKind.TYPE_IDEAL_FLOAT)) {
        lce.constNumValue.asFloat.value = parseFloatLiteral(lce.stringValue)
        lce.constNumValue.asFloat.flowStatus = FlowStatus.NORMAL
    }
}

private func getPrimitiveLiteralKind(lce: LitConstExpr): TypeKind {
    if (let Some(ty) <- lce.GetTy()) {
        if (let Some(primitive) <- (ty as PrimitiveTy)) {
            if (primitive.kind == TypeKind.TYPE_INT_NATIVE) {
                return if (primitive.bitness == 32) { TypeKind.TYPE_INT32 } else { TypeKind.TYPE_INT64 }
            }
            if (primitive.kind == TypeKind.TYPE_UINT_NATIVE) {
                return if (primitive.bitness == 32) { TypeKind.TYPE_UINT32 } else { TypeKind.TYPE_UINT64 }
            }
            return primitive.kind
        }
        if (let Some(genericTy) <- (ty as GenericsTy)) {
            if (let Some(lower) <- genericTy.lowerBound) {
                if (let Some(primitive) <- (lower as PrimitiveTy)) {
                    return primitive.kind
                }
            }
        }
    }
    if (lce.kind == LitConstKind.BOOL) {
        return TypeKind.TYPE_BOOLEAN
    }
    if (lce.kind == LitConstKind.RUNE) {
        return TypeKind.TYPE_RUNE
    }
    return lce.GetNumLitTypeKind()
}

private func parseFloatLiteral(value: String): Float64 {
    let text = removeNumericSeparators(value)
    var idx: Int64 = 0
    var sign = 1.0
    if (idx < text.size && text[idx] == b'-') {
        sign = -1.0
        idx++
    } else if (idx < text.size && text[idx] == b'+') {
        idx++
    }
    var result = 0.0
    while (idx < text.size && text[idx] >= b'0' && text[idx] <= b'9') {
        result = result * 10.0 + Float64(text[idx] - b'0')
        idx++
    }
    if (idx < text.size && text[idx] == b'.') {
        idx++
        var scale = 0.1
        while (idx < text.size && text[idx] >= b'0' && text[idx] <= b'9') {
            result += Float64(text[idx] - b'0') * scale
            scale /= 10.0
            idx++
        }
    }
    if (idx < text.size && (text[idx] == b'e' || text[idx] == b'E')) {
        idx++
        var expSign: Int64 = 1
        if (idx < text.size && text[idx] == b'-') {
            expSign = -1
            idx++
        } else if (idx < text.size && text[idx] == b'+') {
            idx++
        }
        var exp: Int64 = 0
        while (idx < text.size && text[idx] >= b'0' && text[idx] <= b'9') {
            exp = exp * 10 + Int64(text[idx] - b'0')
            idx++
        }
        result *= pow10(exp * expSign)
    }
    return sign * result
}

private func removeNumericSeparators(value: String): String {
    let out = StringBuilder()
    for (byte in value.toArray()) {
        if (byte == b'f' || byte == b'F' || byte == b'i' || byte == b'u' || byte == b'U') {
            break
        }
        if (byte != b'_') {
            out.append(String.fromUtf8([byte]))
        }
    }
    return out.toString()
}

private func pow10(exp: Int64): Float64 {
    var result = 1.0
    if (exp >= 0) {
        for (_ in 0..exp) {
            result *= 10.0
        }
    } else {
        var idx: Int64 = 0
        while (idx < -exp) {
            result /= 10.0
            idx++
        }
    }
    return result
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
