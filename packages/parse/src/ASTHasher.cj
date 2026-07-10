package cjcj::parse

import cjcj::ast.{LitConstKindIndex, OverloadableExpr, PointerExpr, TypeKindIndex}
import cjcj::utils.{CJC_ASSERT, FileUtil, OverflowStrategyIndex, SipHash}
import std.collection.*
import std.sort.*

private let ALL: Int64 = 0
private let ONLY_POSITION: Int64 = 1
private let NON_POSITION: Int64 = 2
private var g_needLineInfo: Bool = false
private var g_packagePath: Option<String> = None
private let g_trimPaths: ArrayList<String> = ArrayList<String>()
private var g_print: Bool = false

private func PrintDebug(v: UInt64, line!: Int64 = 0): Unit {
    if (!g_print) {
        return
    }
    println("${line}:${v}")
}

private class DebugWhen {
    public init(decl: Decl, m: String) {
        if (decl.rawMangleName == m) {
            g_print = true
        }
    }

    public init(v: Bool) {
        if (v) {
            g_print = true
        }
    }

    ~init() {
        g_print = false
    }
}

public func TrimPackagePath(path: String): String {
    if (!g_trimPaths.isEmpty()) {
        return FileUtil.RemovePathPrefix(path, g_trimPaths.toArray())
    }
    if (let Some(packagePath) <- g_packagePath) {
        if (path.startsWith(packagePath)) {
            if (path.size > packagePath.size && (path[packagePath.size] == b'/' || path[packagePath.size] == b'\\') &&
                !(packagePath[packagePath.size - 1] == b'/' || packagePath[packagePath.size - 1] == b'\\')) {
                return path[packagePath.size + 1..]
            }
            return path[packagePath.size..]
        }
    }
    return path
}

@When[os == "Windows"]
public func GetTrimmedPath(file: Option<File>): String {
    if (let None <- file) {
        return ""
    }
    let fileValue = file.getOrThrow()
    var path = fileValue.filePath
    if (let Some(pkg) <- fileValue.curPackage) {
        let pkgName = pkg.fullPackageName + "\\"
        if (path.startsWith(pkgName)) {
            path = path[pkgName.size..]
        }
    }
    return TrimPackagePath(path)
}

@When[os != "Windows"]
public func GetTrimmedPath(file: Option<File>): String {
    if (let None <- file) {
        return ""
    }
    let fileValue = file.getOrThrow()
    var path = fileValue.filePath
    if (let Some(pkg) <- fileValue.curPackage) {
        let pkgName = pkg.fullPackageName + "/"
        if (path.startsWith(pkgName)) {
            path = path[pkgName.size..]
        }
    }
    return TrimPackagePath(path)
}

private class ASTHasherImpl {
    public var value: UInt64 = 0u64

    public init() {}

    public func HashSpecs(pk: Package): UInt64 {
        HashPackage(pk, whatTypeToHash: NON_POSITION)
        return value
    }

    @OverflowWrapping
    public func CombineTwoHashes(ha: UInt64): UInt64 {
        value = ASTHasher.CombineHash(value, ha)
        return value
    }

    public func CombineHash(v: Bool): Unit {
        let _ = CombineTwoHashes(SipHash.GetHashValue(v))
    }

    public func CombineHash(v: UInt8): Unit {
        let _ = CombineTwoHashes(SipHash.GetHashValue(v))
    }

    public func CombineHash(v: UInt16): Unit {
        let _ = CombineTwoHashes(SipHash.GetHashValue(v))
    }

    public func CombineHash(v: UInt32): Unit {
        let _ = CombineTwoHashes(SipHash.GetHashValue(v))
    }

    public func CombineHash(v: UInt64): Unit {
        let _ = CombineTwoHashes(SipHash.GetHashValue(v))
    }

    public func CombineHash(v: Int64): Unit {
        let _ = CombineTwoHashes(SipHash.GetHashValue(v))
    }

    public func CombineHash(v: String): Unit {
        let _ = CombineTwoHashes(SipHash.GetHashValue(v))
    }

    public func CombineHash(pos: Position): Unit {
        match (pos.GetStatus()) {
            case PositionStatus.IGNORE => return
            case _ => ()
        }
        CombineHash(pos.line)
        CombineHash(pos.column)
        CombineHash(pos.isCurFile)
    }

    public func CombineHash(id: Identifier): Unit {
        CombineHash(id.Val())
        CombineHash(id.Begin())
    }

    public func CombineHash(id: SrcIdentifier): Unit {
        CombineHash((id as Identifier).getOrThrow())
        CombineHash(id.IsRaw())
    }

    public func CombineHash(attrs: AttributePack): Unit {
        for (attr in attrs.GetRawAttrs()) {
            CombineHash(attr)
        }
    }

    public func CombineHash(modifiers: ArrayList<Modifier>): Unit {
        let modifierVec = ArrayList<TokenKind>()
        for (modifier in modifiers) {
            modifierVec.add(modifier.modifier)
        }
        sort(modifierVec, by: { left: TokenKind, right: TokenKind =>
            if (TokenKindIndex(left) < TokenKindIndex(right)) {
                Ordering.LT
            } else if (TokenKindIndex(left) > TokenKindIndex(right)) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        }, stable: true)
        for (modifier in modifierVec) {
            CombineHash(Int64(TokenKindIndex(modifier)))
        }
    }

    public func CombineHash(tok: Token, whatTypeToHash!: Int64 = ALL): Unit {
        SuperHash(UInt8(TokenKindIndex(tok.kind)), whatTypeToHash: whatTypeToHash)
        SuperHash(tok.Begin(), whatTypeToHash: whatTypeToHash)
        SuperHash(tok.Value(), whatTypeToHash: whatTypeToHash)
    }

    public func CombineHash(sp: StringPart, whatTypeToHash!: Int64 = ALL): Unit {
        SuperHash(sp.begin, whatTypeToHash: whatTypeToHash)
        SuperHash(sp.end, whatTypeToHash: whatTypeToHash)
        SuperHash(Int64(StringPartKindIndex(sp.strKind)), whatTypeToHash: whatTypeToHash)
        SuperHash(sp.value, whatTypeToHash: whatTypeToHash)
    }

    public func CombineHash(kind: AnnotationKind): Unit {
        let value = match (kind) {
            case AnnotationKind.JAVA => 0
            case AnnotationKind.CALLING_CONV => 1
            case AnnotationKind.C => 2
            case AnnotationKind.JAVA_MIRROR => 3
            case AnnotationKind.JAVA_IMPL => 4
            case AnnotationKind.JAVA_HAS_DEFAULT => 5
            case AnnotationKind.OBJ_C_MIRROR => 6
            case AnnotationKind.OBJ_C_IMPL => 7
            case AnnotationKind.OBJ_C_INIT => 8
            case AnnotationKind.OBJ_C_OPTIONAL => 9
            case AnnotationKind.FOREIGN_NAME => 10
            case AnnotationKind.FOREIGN_GETTER_NAME => 11
            case AnnotationKind.FOREIGN_SETTER_NAME => 12
            case AnnotationKind.ATTRIBUTE => 13
            case AnnotationKind.NUMERIC_OVERFLOW => 14
            case AnnotationKind.INTRINSIC => 15
            case AnnotationKind.WHEN => 16
            case AnnotationKind.FASTNATIVE => 17
            case AnnotationKind.ANNOTATION => 18
            case AnnotationKind.CUSTOM => 19
            case AnnotationKind.CONSTSAFE => 20
            case AnnotationKind.DEPRECATED => 21
            case AnnotationKind.FROZEN => 22
            case AnnotationKind.ENSURE_PREPARED_TO_MOCK => 23
            case AnnotationKind.NON_PRODUCT => 24
            case AnnotationKind.UNKNOWN => 25
            case AnnotationKind.NO_HEAP_ALLOC => 26
            case AnnotationKind.NO_WRITE_BARRIER_REC => 27
            case AnnotationKind.NO_STACK_GROW => 28
        }
        CombineHash(Int64(value))
    }

    public func CombineHash(kind: ImportKind): Unit {
        let value = match (kind) {
            case ImportKind.IMPORT_SINGLE => 0u8
            case ImportKind.IMPORT_ALIAS => 1u8
            case ImportKind.IMPORT_ALL => 2u8
            case ImportKind.IMPORT_MULTI => 3u8
        }
        CombineHash(value)
    }

    public func CombineHash(kind: StringKind): Unit {
        let value = match (kind) {
            case StringKind.NORMAL => 0
            case StringKind.JSTRING => 1
            case StringKind.MULTILINE => 2
            case StringKind.MULTILINE_RAW => 3
        }
        CombineHash(Int64(value))
    }

    public func SuperHash(v: Bool, whatTypeToHash!: Int64 = ALL): Unit {
        if (whatTypeToHash != ONLY_POSITION) {
            CombineHash(v)
        }
    }

    public func SuperHash(v: UInt8, whatTypeToHash!: Int64 = ALL): Unit {
        if (whatTypeToHash != ONLY_POSITION) {
            CombineHash(v)
        }
    }

    public func SuperHash(v: UInt16, whatTypeToHash!: Int64 = ALL): Unit {
        if (whatTypeToHash != ONLY_POSITION) {
            CombineHash(v)
        }
    }

    public func SuperHash(v: UInt32, whatTypeToHash!: Int64 = ALL): Unit {
        if (whatTypeToHash != ONLY_POSITION) {
            CombineHash(v)
        }
    }

    public func SuperHash(v: UInt64, whatTypeToHash!: Int64 = ALL): Unit {
        if (whatTypeToHash != ONLY_POSITION) {
            CombineHash(v)
        }
    }

    public func SuperHash(v: Int64, whatTypeToHash!: Int64 = ALL): Unit {
        if (whatTypeToHash != ONLY_POSITION) {
            CombineHash(v)
        }
    }

    public func SuperHash(v: String, whatTypeToHash!: Int64 = ALL): Unit {
        if (whatTypeToHash != ONLY_POSITION) {
            CombineHash(v)
        }
    }

    public func SuperHash(kind: AnnotationKind, whatTypeToHash!: Int64 = ALL): Unit {
        if (whatTypeToHash != ONLY_POSITION) {
            CombineHash(kind)
        }
    }

    public func SuperHash(kind: ImportKind, whatTypeToHash!: Int64 = ALL): Unit {
        if (whatTypeToHash != ONLY_POSITION) {
            CombineHash(kind)
        }
    }

    public func SuperHash(kind: StringKind, whatTypeToHash!: Int64 = ALL): Unit {
        if (whatTypeToHash != ONLY_POSITION) {
            CombineHash(kind)
        }
    }

    public func SuperHash(pos: Position, whatTypeToHash!: Int64 = ALL): Unit {
        if (whatTypeToHash == NON_POSITION) {
            return
        }
        if (g_needLineInfo) {
            CombineHash(pos)
        }
    }

    public func SUPERHash(firstArg: Position, whatTypeToHash!: Int64 = ALL): Unit {
        SuperHash(firstArg, whatTypeToHash: whatTypeToHash)
    }

    public func SUPERHash(firstArg: Position, secondArg: Position, whatTypeToHash!: Int64 = ALL): Unit {
        SuperHash(firstArg, whatTypeToHash: whatTypeToHash)
        SUPERHash(secondArg, whatTypeToHash: whatTypeToHash)
    }

    public func SuperHash(id: Identifier, whatTypeToHash!: Int64 = ALL): Unit {
        if (whatTypeToHash != ONLY_POSITION) {
            CombineHash(id)
        }
    }

    public func SuperHash(id: SrcIdentifier, whatTypeToHash!: Int64 = ALL): Unit {
        if (whatTypeToHash != ONLY_POSITION) {
            CombineHash(id)
        }
    }

    public func SuperHash(attrs: AttributePack, whatTypeToHash!: Int64 = ALL): Unit {
        if (whatTypeToHash != ONLY_POSITION) {
            CombineHash(attrs)
        }
    }

    public func SuperHash(modifiers: ArrayList<Modifier>, whatTypeToHash!: Int64 = ALL): Unit {
        if (whatTypeToHash != ONLY_POSITION) {
            CombineHash(modifiers)
        }
    }

    public func SuperHash(tok: Token, whatTypeToHash!: Int64 = ALL): Unit {
        if (whatTypeToHash != ONLY_POSITION) {
            CombineHash(tok, whatTypeToHash: whatTypeToHash)
        }
    }

    public func SuperHash(sp: StringPart, whatTypeToHash!: Int64 = ALL): Unit {
        if (whatTypeToHash != ONLY_POSITION) {
            CombineHash(sp, whatTypeToHash: whatTypeToHash)
        }
    }

    public func SuperHash<T>(node: T, whatTypeToHash!: Int64 = ALL): Unit where T <: Node {
        if (whatTypeToHash != ONLY_POSITION) {
            let _ = Hash(node, whatTypeToHash: whatTypeToHash)
        }
    }

    public func SuperHash<T>(node: Option<T>, whatTypeToHash!: Int64 = ALL): Unit where T <: Node {
        if (whatTypeToHash == ONLY_POSITION) {
            return
        }
        if (let Some(valueNode) <- node) {
            let _ = Hash(valueNode, whatTypeToHash: whatTypeToHash)
        }
    }

    public func SuperHash<T>(nodes: ArrayList<T>, whatTypeToHash!: Int64 = ALL): Unit where T <: Node {
        if (whatTypeToHash == ONLY_POSITION) {
            return
        }
        for (node in nodes) {
            let _ = Hash(node, whatTypeToHash: whatTypeToHash)
        }
    }

    public func SuperHash(values: ArrayList<String>, whatTypeToHash!: Int64 = ALL): Unit {
        if (whatTypeToHash == ONLY_POSITION) {
            return
        }
        for (str in values) {
            SuperHash(str, whatTypeToHash: whatTypeToHash)
        }
    }

    public func SuperHash(values: ArrayList<Position>, whatTypeToHash!: Int64 = ALL): Unit {
        if (whatTypeToHash == ONLY_POSITION) {
            return
        }
        for (pos in values) {
            SuperHash(pos, whatTypeToHash: whatTypeToHash)
        }
    }

    public func SuperHash(values: ArrayList<StringPart>, whatTypeToHash!: Int64 = ALL): Unit {
        if (whatTypeToHash == ONLY_POSITION) {
            return
        }
        for (part in values) {
            SuperHash(part, whatTypeToHash: whatTypeToHash)
        }
    }

    public func SuperHash(values: ArrayList<Token>, whatTypeToHash!: Int64 = ALL): Unit {
        if (whatTypeToHash == ONLY_POSITION) {
            return
        }
        for (tok in values) {
            SuperHash(tok, whatTypeToHash: whatTypeToHash)
        }
    }

    private static func IsNonZero(pos: Position): Bool {
        return pos.line != 0
    }

    private func HashVarDeclAbstract(vda: VarDeclAbstract, whatTypeToHash!: Int64 = ALL): Unit {
        HashDecl(vda, whatTypeToHash: whatTypeToHash)
        SuperHash(vda.typeNode, whatTypeToHash: whatTypeToHash)
        SuperHash(vda.initializer, whatTypeToHash: whatTypeToHash)
        SuperHash(vda.isVar, whatTypeToHash: whatTypeToHash)
    }

    private func HashNode(node: Node, whatTypeToHash!: Int64 = ALL): Unit {
        SuperHash(Int64(ASTKindIndex(node.astKind)), whatTypeToHash: whatTypeToHash)
        SuperHash(node.scopeName, whatTypeToHash: whatTypeToHash)
        SuperHash(node.exportId, whatTypeToHash: whatTypeToHash)
        SuperHash(node.scopeLevel, whatTypeToHash: whatTypeToHash)

        let nonSemaAttr: Array<Attribute> = [
            Attribute.ABSTRACT, Attribute.CONSTRUCTOR, Attribute.DEFAULT, Attribute.ENUM_CONSTRUCTOR,
            Attribute.INTERNAL, Attribute.FOREIGN, Attribute.COMMON, Attribute.SPECIFIC, Attribute.GENERIC,
            Attribute.GLOBAL, Attribute.INTRINSIC, Attribute.JAVA_APP, Attribute.JAVA_MIRROR,
            Attribute.OBJ_C_MIRROR, Attribute.OBJ_C_MIRROR_SUBTYPE, Attribute.MACRO_FUNC, Attribute.MUT,
            Attribute.NUMERIC_OVERFLOW, Attribute.OPERATOR, Attribute.PRIVATE, Attribute.PUBLIC, Attribute.PROTECTED,
            Attribute.STATIC, Attribute.TOOL_ADD, Attribute.UNSAFE
        ]
        for (attr in nonSemaAttr) {
            SuperHash(node.TestAttr(attr))
        }
    }

    private func HashExpr(expr: Expr, whatTypeToHash!: Int64 = ALL): Unit {
        SUPERHash(expr.begin, expr.end, whatTypeToHash: whatTypeToHash)
        if (whatTypeToHash != NON_POSITION) {
            match (expr.begin.GetStatus()) {
                case PositionStatus.IGNORE => ()
                case _ =>
                    CJC_ASSERT(expr.curFile.isSome())
                    SuperHash(TrimPackagePath(expr.curFile.getOrThrow().filePath), whatTypeToHash: whatTypeToHash)
            }
        }
        HashNode(expr, whatTypeToHash: whatTypeToHash)
        SuperHash(expr.semiPos, whatTypeToHash: whatTypeToHash)
        SuperHash(expr.hasSemi, whatTypeToHash: whatTypeToHash)
    }

    private func HashIfExpr(ifExpr: IfExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(ifExpr, whatTypeToHash: whatTypeToHash)
        SuperHash(ifExpr.ifPos, whatTypeToHash: whatTypeToHash)
        SuperHash(ifExpr.leftParenPos, whatTypeToHash: whatTypeToHash)
        SuperHash(ifExpr.rightParenPos, whatTypeToHash: whatTypeToHash)
        SuperHash(ifExpr.condExpr, whatTypeToHash: whatTypeToHash)
        SuperHash(ifExpr.thenBody, whatTypeToHash: whatTypeToHash)
        SuperHash(ifExpr.elsePos, whatTypeToHash: whatTypeToHash)
        SuperHash(ifExpr.elseBody, whatTypeToHash: whatTypeToHash)
        SuperHash(ifExpr.isElseIf, whatTypeToHash: whatTypeToHash)
        SuperHash(ifExpr.hasElse, whatTypeToHash: whatTypeToHash)
    }

    public func HashAnnotation(anno: Annotation, whatTypeToHash!: Int64 = ALL): Unit {
        HashNode(anno, whatTypeToHash: whatTypeToHash)
        SuperHash(anno.kind, whatTypeToHash: NON_POSITION)
        SuperHash(anno.identifier.Val(), whatTypeToHash: NON_POSITION)
        SuperHash(anno.args, whatTypeToHash: NON_POSITION)
        SuperHash(Int64(OverflowStrategyIndex(anno.overflowStrategy)), whatTypeToHash: NON_POSITION)
        SuperHash(anno.definedPackage, whatTypeToHash: NON_POSITION)
        SuperHash(anno.condExpr, whatTypeToHash: NON_POSITION)
        SuperHash(anno.isCompileTimeVisible, whatTypeToHash: NON_POSITION)
        SuperHash(anno.attrCommas, whatTypeToHash: NON_POSITION)
        for (att in anno.attrs) {
            CombineHash(att)
        }
    }

    private func HashDecl(decl: Decl, whatTypeToHash!: Int64 = ALL): Unit {
        HashNode(decl, whatTypeToHash: whatTypeToHash)
        SuperHash(decl.modifiers, whatTypeToHash: whatTypeToHash)
        SuperHash(decl.annotations, whatTypeToHash: whatTypeToHash)
        SuperHash(decl.identifier.Val(), whatTypeToHash: whatTypeToHash)
        SuperHash(decl.generic, whatTypeToHash: whatTypeToHash)
        if (whatTypeToHash != NON_POSITION) {
            match (decl.begin.GetStatus()) {
                case PositionStatus.IGNORE => ()
                case _ =>
                    CJC_ASSERT(decl.curFile.isSome())
                    SuperHash(TrimPackagePath(decl.curFile.getOrThrow().filePath), whatTypeToHash: whatTypeToHash)
            }
        }
    }

    private func HashFuncArg(funcArg: FuncArg, whatTypeToHash!: Int64 = ALL): Unit {
        HashNode(funcArg, whatTypeToHash: whatTypeToHash)
        SuperHash(funcArg.name, whatTypeToHash: whatTypeToHash)
        SuperHash(funcArg.expr, whatTypeToHash: whatTypeToHash)
        SuperHash(funcArg.withInout, whatTypeToHash: whatTypeToHash)
    }

    private func HashFuncBody(funcBody: FuncBody, whatTypeToHash!: Int64 = ALL): Unit {
        HashNode(funcBody, whatTypeToHash: whatTypeToHash)
        SuperHash(funcBody.paramLists, whatTypeToHash: whatTypeToHash)
        SuperHash(funcBody.retType, whatTypeToHash: whatTypeToHash)
        SuperHash(funcBody.body, whatTypeToHash: whatTypeToHash)
        SuperHash(funcBody.generic, whatTypeToHash: whatTypeToHash)
    }

    private func HashFuncParamList(fpl: FuncParamList, whatTypeToHash!: Int64 = ALL): Unit {
        HashNode(fpl, whatTypeToHash: whatTypeToHash)
        SuperHash(fpl.params, whatTypeToHash: whatTypeToHash)
        SuperHash(fpl.variadicArgIndex, whatTypeToHash: whatTypeToHash)
        SuperHash(fpl.hasVariableLenArg, whatTypeToHash: whatTypeToHash)
    }

    private func HashGeneric(ge: Generic, whatTypeToHash!: Int64 = ALL): Unit {
        HashNode(ge, whatTypeToHash: whatTypeToHash)
        SuperHash(ge.typeParameters, whatTypeToHash: whatTypeToHash)
        SuperHash(ge.genericConstraints, whatTypeToHash: whatTypeToHash)
    }

    private func HashGenericConstraint(gc: GenericConstraint, whatTypeToHash!: Int64 = ALL): Unit {
        HashNode(gc, whatTypeToHash: whatTypeToHash)
        SuperHash(gc.refType, whatTypeToHash: whatTypeToHash)
        SuperHash(gc.upperBounds, whatTypeToHash: whatTypeToHash)
    }

    private func HashImportSpec(importSpecValue: ImportSpec, whatTypeToHash!: Int64 = ALL): Unit {
        HashNode(importSpecValue, whatTypeToHash: whatTypeToHash)
        let im = importSpecValue.content
        if (im.kind != ImportKind.IMPORT_MULTI) {
            SuperHash(im.kind, whatTypeToHash: whatTypeToHash)
            SuperHash(im.prefixPaths, whatTypeToHash: whatTypeToHash)
            SuperHash(im.identifier.Val(), whatTypeToHash: whatTypeToHash)
            SuperHash(im.aliasName, whatTypeToHash: whatTypeToHash)
        } else {
            SuperHash(im.kind, whatTypeToHash: whatTypeToHash)
            SuperHash(im.prefixPaths, whatTypeToHash: whatTypeToHash)
            SuperHash(im.leftCurlPos, whatTypeToHash: whatTypeToHash)
            SuperHash(im.rightCurlPos, whatTypeToHash: whatTypeToHash)
            for (item in im.items) {
                SuperHash(item.kind, whatTypeToHash: whatTypeToHash)
                SuperHash(item.prefixPaths, whatTypeToHash: whatTypeToHash)
                SuperHash(item.identifier.Val(), whatTypeToHash: whatTypeToHash)
                SuperHash(item.aliasName.Val(), whatTypeToHash: whatTypeToHash)
            }
        }
        SuperHash(im.hasDoubleColon, whatTypeToHash: whatTypeToHash)
    }

    private func HashPackageSpec(ps: PackageSpec, whatTypeToHash!: Int64 = ALL): Unit {
        HashNode(ps, whatTypeToHash: whatTypeToHash)
        SuperHash(ps.prefixPaths, whatTypeToHash: whatTypeToHash)
        SuperHash(ps.packageName, whatTypeToHash: whatTypeToHash)
        SuperHash(ps.hasMacro, whatTypeToHash: whatTypeToHash)
        SuperHash(ps.hasDoubleColon, whatTypeToHash: whatTypeToHash)
    }

    private func HashMatchCase(mc: MatchCase, whatTypeToHash!: Int64 = ALL): Unit {
        HashNode(mc, whatTypeToHash: whatTypeToHash)
        SuperHash(mc.patterns, whatTypeToHash: whatTypeToHash)
        SuperHash(mc.patternGuard, whatTypeToHash: whatTypeToHash)
        SuperHash(mc.wherePos, whatTypeToHash: whatTypeToHash)
        SuperHash(mc.arrowPos, whatTypeToHash: whatTypeToHash)
        SuperHash(mc.exprOrDecls, whatTypeToHash: whatTypeToHash)
    }

    private func HashMatchCaseOther(mco: MatchCaseOther, whatTypeToHash!: Int64 = ALL): Unit {
        HashNode(mco, whatTypeToHash: whatTypeToHash)
        SuperHash(mco.matchExpr, whatTypeToHash: whatTypeToHash)
        SuperHash(mco.arrowPos, whatTypeToHash: whatTypeToHash)
        SuperHash(mco.exprOrDecls, whatTypeToHash: whatTypeToHash)
    }

    public func HashPackage(p: Package, whatTypeToHash!: Int64 = ALL): Unit {
        for (file in p.files) {
            for (importSpec in file.imports) {
                if (!importSpec.TestAttr(Attribute.IMPLICIT_ADD)) {
                    HashImportSpec(importSpec, whatTypeToHash: whatTypeToHash)
                }
            }
            if (let Some(pkgSpec) <- file.packageSpec) {
                HashPackageSpec(pkgSpec, whatTypeToHash: NON_POSITION)
            }
        }
    }

    private func HashFuncDecl(fd: FuncDecl, whatTypeToHash!: Int64 = ALL): Unit {
        HashDecl(fd, whatTypeToHash: whatTypeToHash)
        SuperHash(fd.funcBody, whatTypeToHash: whatTypeToHash)
        SuperHash(Int64(TokenKindIndex(fd.op)), whatTypeToHash: whatTypeToHash)
    }

    private func HashVarWithPatternDecl(vwp: VarWithPatternDecl, whatTypeToHash!: Int64 = ALL): Unit {
        HashVarDeclAbstract(vwp, whatTypeToHash: whatTypeToHash)
        SuperHash(vwp.irrefutablePattern, whatTypeToHash: whatTypeToHash)
    }

    private func HashFuncParam(fp: FuncParam, whatTypeToHash!: Int64 = ALL): Unit {
        HashVarDecl(fp, whatTypeToHash: whatTypeToHash)
        SuperHash(fp.assignment, whatTypeToHash: whatTypeToHash)
        SuperHash(fp.isNamedParam, whatTypeToHash: whatTypeToHash)
        SuperHash(fp.hasLetOrVar, whatTypeToHash: whatTypeToHash)
    }

    private func HashArrayExpr(ae: ArrayExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(ae, whatTypeToHash: whatTypeToHash)
        SuperHash(ae.typeNode, whatTypeToHash: whatTypeToHash)
        SuperHash(ae.args, whatTypeToHash: whatTypeToHash)
    }

    private func HashArrayLit(al: ArrayLit, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(al, whatTypeToHash: whatTypeToHash)
        SuperHash(al.children, whatTypeToHash: whatTypeToHash)
    }

    private func HashAsExpr(ae: AsExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(ae, whatTypeToHash: whatTypeToHash)
        SuperHash(ae.leftExpr, whatTypeToHash: whatTypeToHash)
        SuperHash(ae.asType, whatTypeToHash: whatTypeToHash)
    }

    private func HashBlock(ae: Block, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(ae, whatTypeToHash: whatTypeToHash)
        if (ASTHasherImpl.IsNonZero(ae.unsafePos)) {
            SuperHash(ae.leftCurlPos, whatTypeToHash: whatTypeToHash)
            SuperHash(ae.body, whatTypeToHash: whatTypeToHash)
            SuperHash(ae.rightCurlPos, whatTypeToHash: whatTypeToHash)
        } else {
            SuperHash(ae.body, whatTypeToHash: whatTypeToHash)
        }
        SuperHash(ae.unsafePos, whatTypeToHash: whatTypeToHash)
    }

    private func HashCallExpr(ce: CallExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(ce, whatTypeToHash: whatTypeToHash)
        SuperHash(ce.baseFunc, whatTypeToHash: whatTypeToHash)
        SuperHash(ce.args, whatTypeToHash: whatTypeToHash)
    }

    private func HashDoWhileExpr(dwe: DoWhileExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(dwe, whatTypeToHash: whatTypeToHash)
        SuperHash(dwe.body, whatTypeToHash: whatTypeToHash)
        SuperHash(dwe.condExpr, whatTypeToHash: whatTypeToHash)
    }

    private func HashForInExpr(fie: ForInExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(fie, whatTypeToHash: whatTypeToHash)
        SuperHash(fie.pattern, whatTypeToHash: whatTypeToHash)
        SuperHash(fie.inPos, whatTypeToHash: whatTypeToHash)
        SuperHash(fie.inExpression, whatTypeToHash: whatTypeToHash)
        SuperHash(fie.patternGuard, whatTypeToHash: whatTypeToHash)
        SuperHash(fie.body, whatTypeToHash: whatTypeToHash)
    }

    private func HashIsExpr(ie: IsExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(ie, whatTypeToHash: whatTypeToHash)
        SuperHash(ie.leftExpr, whatTypeToHash: whatTypeToHash)
        SuperHash(ie.isType, whatTypeToHash: whatTypeToHash)
    }

    private func HashLambdaExpr(le: LambdaExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(le, whatTypeToHash: whatTypeToHash)
        SuperHash(le.funcBody, whatTypeToHash: whatTypeToHash)
    }

    private func HashLetPatternDestructor(lpd: LetPatternDestructor, whatTypeToHash!: Int64 = ALL): Unit {
        SuperHash(lpd.patterns, whatTypeToHash: whatTypeToHash)
        SuperHash(lpd.orPos, whatTypeToHash: whatTypeToHash)
        SuperHash(lpd.initializer, whatTypeToHash: whatTypeToHash)
        SuperHash(lpd.backarrowPos, whatTypeToHash: whatTypeToHash)
    }

    private func HashLitConstExpr(lce: LitConstExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(lce, whatTypeToHash: whatTypeToHash)
        SuperHash(lce.rawString, whatTypeToHash: whatTypeToHash)
        SuperHash(lce.siExpr, whatTypeToHash: whatTypeToHash)
        SuperHash(lce.stringValue, whatTypeToHash: whatTypeToHash)
        for (cp in lce.codepoint) {
            SuperHash(UInt64(cp), whatTypeToHash: whatTypeToHash)
        }
        SuperHash(Int64(LitConstKindIndex(lce.kind)), whatTypeToHash: whatTypeToHash)
        SuperHash(lce.stringKind, whatTypeToHash: whatTypeToHash)
        SuperHash(lce.delimiterNum, whatTypeToHash: whatTypeToHash)
    }

    private func HashMatchExpr(me: MatchExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(me, whatTypeToHash: whatTypeToHash)
        SuperHash(me.matchMode, whatTypeToHash: whatTypeToHash)
        SuperHash(me.selector, whatTypeToHash: whatTypeToHash)
        SuperHash(me.leftCurlPos, whatTypeToHash: whatTypeToHash)
        SuperHash(me.matchCases, whatTypeToHash: whatTypeToHash)
        SuperHash(me.matchCaseOthers, whatTypeToHash: whatTypeToHash)
        SuperHash(me.rightCurlPos, whatTypeToHash: whatTypeToHash)
    }

    private func HashMemberAccess(ma: MemberAccess, whatTypeToHash!: Int64 = ALL): Unit {
        SuperHash(ma.baseExpr, whatTypeToHash: whatTypeToHash)
        SuperHash(ma.field, whatTypeToHash: whatTypeToHash)
        SuperHash(ma.typeArguments, whatTypeToHash: whatTypeToHash)
        SuperHash(ma.isPattern, whatTypeToHash: whatTypeToHash)
        if (let Some(maTarget) <- ma.target) {
            SuperHash(maTarget.rawMangleName, whatTypeToHash: whatTypeToHash)
            CJC_ASSERT(maTarget.GetTy().isSome())
            SuperHash(maTarget.GetTy().getOrThrow().String(), whatTypeToHash: whatTypeToHash)
        }
    }

    private func HashTypeConvExpr(ntc: TypeConvExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(ntc, whatTypeToHash: whatTypeToHash)
        SuperHash(ntc.typeNode, whatTypeToHash: whatTypeToHash)
        SuperHash(ntc.leftParenPos, whatTypeToHash: whatTypeToHash)
        SuperHash(ntc.expr, whatTypeToHash: whatTypeToHash)
        SuperHash(ntc.rightParenPos, whatTypeToHash: whatTypeToHash)
    }

    private func HashParenExpr(pe: ParenExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(pe, whatTypeToHash: whatTypeToHash)
        SuperHash(pe.expr, whatTypeToHash: whatTypeToHash)
    }

    private func HashPointerExpr(pe: PointerExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(pe, whatTypeToHash: whatTypeToHash)
        SuperHash(pe.typeNode, whatTypeToHash: whatTypeToHash)
        SuperHash(pe.arg, whatTypeToHash: whatTypeToHash)
    }

    private func HashQuoteExpr(qe: QuoteExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(qe, whatTypeToHash: whatTypeToHash)
        SuperHash(qe.quotePos, whatTypeToHash: whatTypeToHash)
    }

    private func HashRangeExpr(re: RangeExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(re, whatTypeToHash: whatTypeToHash)
        SuperHash(re.startExpr, whatTypeToHash: whatTypeToHash)
        SuperHash(re.rangePos, whatTypeToHash: whatTypeToHash)
        SuperHash(re.stopExpr, whatTypeToHash: whatTypeToHash)
        SuperHash(re.colonPos, whatTypeToHash: whatTypeToHash)
        SuperHash(re.stepExpr, whatTypeToHash: whatTypeToHash)
        SuperHash(re.isClosed, whatTypeToHash: whatTypeToHash)
    }

    private func HashRefExpr(re: RefExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(re, whatTypeToHash: whatTypeToHash)
        SuperHash(re.ref.identifier.Val(), whatTypeToHash: whatTypeToHash)
        SuperHash(re.typeArguments, whatTypeToHash: whatTypeToHash)
        SuperHash(re.isThis, whatTypeToHash: whatTypeToHash)
        SuperHash(re.isSuper, whatTypeToHash: whatTypeToHash)
        SuperHash(re.isQuoteDollar, whatTypeToHash: whatTypeToHash)
        if (let Some(refTarget) <- re.ref.target) {
            SuperHash(refTarget.rawMangleName, whatTypeToHash: whatTypeToHash)
            CJC_ASSERT(refTarget.GetTy().isSome())
            SuperHash(refTarget.GetTy().getOrThrow().String(), whatTypeToHash: whatTypeToHash)
        }
    }

    private func HashReturnExpr(re: ReturnExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(re, whatTypeToHash: whatTypeToHash)
        SuperHash(re.expr, whatTypeToHash: whatTypeToHash)
    }

    private func HashSpawnExpr(se: SpawnExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(se, whatTypeToHash: whatTypeToHash)
        SuperHash(se.spawnPos, whatTypeToHash: whatTypeToHash)
        SuperHash(se.futureObj, whatTypeToHash: whatTypeToHash)
        SuperHash(se.task, whatTypeToHash: whatTypeToHash)
        SuperHash(se.arg, whatTypeToHash: whatTypeToHash)
    }

    private func HashSynchronizedExpr(se: SynchronizedExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(se, whatTypeToHash: whatTypeToHash)
        SuperHash(se.syncPos, whatTypeToHash: whatTypeToHash)
        SuperHash(se.leftParenPos, whatTypeToHash: whatTypeToHash)
        SuperHash(se.mutex, whatTypeToHash: whatTypeToHash)
        SuperHash(se.rightParenPos, whatTypeToHash: whatTypeToHash)
        SuperHash(se.body, whatTypeToHash: whatTypeToHash)
    }

    private func HashThrowExpr(te: ThrowExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(te, whatTypeToHash: whatTypeToHash)
        SuperHash(te.throwPos, whatTypeToHash: whatTypeToHash)
        SuperHash(te.expr, whatTypeToHash: whatTypeToHash)
    }

    private func HashPerformExpr(pe: PerformExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(pe, whatTypeToHash: whatTypeToHash)
        SuperHash(pe.performPos, whatTypeToHash: whatTypeToHash)
        SuperHash(pe.expr, whatTypeToHash: whatTypeToHash)
    }

    private func HashResumeExpr(re: ResumeExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(re, whatTypeToHash: whatTypeToHash)
        SuperHash(re.resumePos, whatTypeToHash: whatTypeToHash)
    }

    private func HashTrailingClosureExpr(tce: TrailingClosureExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(tce, whatTypeToHash: whatTypeToHash)
        SuperHash(tce.leftLambda, whatTypeToHash: whatTypeToHash)
        SuperHash(tce.expr, whatTypeToHash: whatTypeToHash)
        SuperHash(tce.lambda, whatTypeToHash: whatTypeToHash)
        SuperHash(tce.rightLambda, whatTypeToHash: whatTypeToHash)
    }

    private func HashTryExpr(te: TryExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(te, whatTypeToHash: whatTypeToHash)
        SuperHash(te.lParen, whatTypeToHash: whatTypeToHash)
        SuperHash(te.resourceSpec, whatTypeToHash: whatTypeToHash)
        SuperHash(te.tryBlock, whatTypeToHash: whatTypeToHash)
        SuperHash(te.catchPosVector, whatTypeToHash: whatTypeToHash)
        SuperHash(te.catchBlocks, whatTypeToHash: whatTypeToHash)
        SuperHash(te.catchPatterns, whatTypeToHash: whatTypeToHash)
        SuperHash(te.finallyPos, whatTypeToHash: whatTypeToHash)
        SuperHash(te.finallyBlock, whatTypeToHash: whatTypeToHash)
        SuperHash(te.isDesugaredFromTryWithResources, whatTypeToHash: whatTypeToHash)
    }

    private func HashTupleLit(te: TupleLit, whatTypeToHash!: Int64 = ALL): Unit {
        SuperHash(te.children, whatTypeToHash: whatTypeToHash)
    }

    private func HashWhileExpr(we: WhileExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(we, whatTypeToHash: whatTypeToHash)
        SuperHash(we.whilePos, whatTypeToHash: whatTypeToHash)
        SuperHash(we.condExpr, whatTypeToHash: whatTypeToHash)
        SuperHash(we.body, whatTypeToHash: whatTypeToHash)
    }

    private func HashOverloadableExpr(oe: OverloadableExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(oe, whatTypeToHash: whatTypeToHash)
        SuperHash(UInt8(TokenKindIndex(oe.op)), whatTypeToHash: whatTypeToHash)
    }

    private func HashAssignExpr(ae: AssignExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashOverloadableExpr(ae, whatTypeToHash: whatTypeToHash)
        SuperHash(ae.leftValue, whatTypeToHash: whatTypeToHash)
        SuperHash(ae.assignPos, whatTypeToHash: whatTypeToHash)
        SuperHash(ae.rightExpr, whatTypeToHash: whatTypeToHash)
        SuperHash(ae.isCompound, whatTypeToHash: whatTypeToHash)
    }

    private func HashBinaryExpr(be: BinaryExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashOverloadableExpr(be, whatTypeToHash: whatTypeToHash)
        SuperHash(be.leftExpr, whatTypeToHash: whatTypeToHash)
        SuperHash(be.rightExpr, whatTypeToHash: whatTypeToHash)
        SuperHash(be.operatorPos, whatTypeToHash: whatTypeToHash)
    }

    private func HashIncOrDecExpr(iod: IncOrDecExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashOverloadableExpr(iod, whatTypeToHash: whatTypeToHash)
        SuperHash(iod.operatorPos, whatTypeToHash: whatTypeToHash)
        SuperHash(iod.expr, whatTypeToHash: whatTypeToHash)
    }

    private func HashSubscriptExpr(se: SubscriptExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(se, whatTypeToHash: whatTypeToHash)
        SuperHash(se.baseExpr, whatTypeToHash: whatTypeToHash)
        SuperHash(se.leftParenPos, whatTypeToHash: whatTypeToHash)
        SuperHash(se.indexExprs, whatTypeToHash: whatTypeToHash)
    }

    private func HashUnaryExpr(ue: UnaryExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashOverloadableExpr(ue, whatTypeToHash: whatTypeToHash)
        SuperHash(ue.expr, whatTypeToHash: whatTypeToHash)
        SuperHash(ue.operatorPos, whatTypeToHash: whatTypeToHash)
    }

    private func HashConstPattern(cp: ConstPattern, whatTypeToHash!: Int64 = ALL): Unit {
        HashPattern(cp, whatTypeToHash: whatTypeToHash)
        SuperHash(cp.literal, whatTypeToHash: whatTypeToHash)
    }

    private func HashEnumPattern(ep: EnumPattern, whatTypeToHash!: Int64 = ALL): Unit {
        HashPattern(ep, whatTypeToHash: whatTypeToHash)
        SuperHash(ep.constructor, whatTypeToHash: whatTypeToHash)
        SuperHash(ep.patterns, whatTypeToHash: whatTypeToHash)
    }

    private func HashExceptTypePattern(etp: ExceptTypePattern, whatTypeToHash!: Int64 = ALL): Unit {
        HashPattern(etp, whatTypeToHash: whatTypeToHash)
        SuperHash(etp.pattern, whatTypeToHash: whatTypeToHash)
        SuperHash(etp.patternPos, whatTypeToHash: whatTypeToHash)
        SuperHash(etp.colonPos, whatTypeToHash: whatTypeToHash)
        SuperHash(etp.types, whatTypeToHash: whatTypeToHash)
        SuperHash(etp.bitOrPosVector, whatTypeToHash: whatTypeToHash)
    }

    private func HashTuplePattern(tp: TuplePattern, whatTypeToHash!: Int64 = ALL): Unit {
        HashPattern(tp, whatTypeToHash: whatTypeToHash)
        SuperHash(tp.leftBracePos, whatTypeToHash: whatTypeToHash)
        SuperHash(tp.patterns, whatTypeToHash: whatTypeToHash)
        SuperHash(tp.rightBracePos, whatTypeToHash: whatTypeToHash)
    }

    private func HashTypePattern(tp: TypePattern, whatTypeToHash!: Int64 = ALL): Unit {
        HashPattern(tp, whatTypeToHash: whatTypeToHash)
        SuperHash(tp.pattern, whatTypeToHash: whatTypeToHash)
        SuperHash(tp.typeNode, whatTypeToHash: whatTypeToHash)
    }

    private func HashVarOrEnumPattern(voe: VarOrEnumPattern, whatTypeToHash!: Int64 = ALL): Unit {
        HashPattern(voe, whatTypeToHash: whatTypeToHash)
        SuperHash(voe.identifier.Val(), whatTypeToHash: whatTypeToHash)
    }

    private func HashVarPattern(vp: VarPattern, whatTypeToHash!: Int64 = ALL): Unit {
        HashPattern(vp, whatTypeToHash: whatTypeToHash)
        SuperHash(vp.varDecl, whatTypeToHash: whatTypeToHash)
    }

    private func HashFuncType(ft: FuncType, whatTypeToHash!: Int64 = ALL): Unit {
        HashType(ft, whatTypeToHash: whatTypeToHash)
        SuperHash(ft.paramTypes, whatTypeToHash: whatTypeToHash)
        SuperHash(ft.retType, whatTypeToHash: whatTypeToHash)
        SuperHash(ft.isC, whatTypeToHash: whatTypeToHash)
    }

    private func HashOptionType(ot: OptionType, whatTypeToHash!: Int64 = ALL): Unit {
        HashType(ot, whatTypeToHash: whatTypeToHash)
        SuperHash(ot.componentType, whatTypeToHash: whatTypeToHash)
        SuperHash(ot.questNum, whatTypeToHash: whatTypeToHash)
    }

    private func HashConstantType(ct: ConstantType, whatTypeToHash!: Int64 = ALL): Unit {
        HashType(ct, whatTypeToHash: whatTypeToHash)
        SuperHash(ct.constantExpr, whatTypeToHash: whatTypeToHash)
    }

    private func HashVArrayType(vt: VArrayType, whatTypeToHash!: Int64 = ALL): Unit {
        HashType(vt, whatTypeToHash: whatTypeToHash)
        SuperHash(vt.typeArgument, whatTypeToHash: whatTypeToHash)
        SuperHash(vt.constantType, whatTypeToHash: whatTypeToHash)
    }

    private func HashParenType(pt: ParenType, whatTypeToHash!: Int64 = ALL): Unit {
        HashType(pt, whatTypeToHash: whatTypeToHash)
        SuperHash(pt.innerType, whatTypeToHash: whatTypeToHash)
    }

    private func HashPrimitiveType(pt: PrimitiveType, whatTypeToHash!: Int64 = ALL): Unit {
        HashType(pt, whatTypeToHash: whatTypeToHash)
        SuperHash(Int64(TypeKindIndex(pt.kind)), whatTypeToHash: whatTypeToHash)
    }

    private func HashQualifiedType(qt: QualifiedType, whatTypeToHash!: Int64 = ALL): Unit {
        HashType(qt, whatTypeToHash: whatTypeToHash)
        SuperHash(qt.baseType, whatTypeToHash: whatTypeToHash)
        SuperHash(qt.field, whatTypeToHash: whatTypeToHash)
        SuperHash(qt.typeArguments, whatTypeToHash: whatTypeToHash)
        if (let Some(refTarget) <- qt.target) {
            SuperHash(refTarget.rawMangleName, whatTypeToHash: whatTypeToHash)
            CJC_ASSERT(refTarget.GetTy().isSome())
            SuperHash(refTarget.GetTy().getOrThrow().String(), whatTypeToHash: whatTypeToHash)
        }
    }

    private func HashRefType(rt: RefType, whatTypeToHash!: Int64 = ALL): Unit {
        HashType(rt, whatTypeToHash: whatTypeToHash)
        SuperHash(rt.ref.identifier.Val(), whatTypeToHash: whatTypeToHash)
        SuperHash(rt.typeArguments, whatTypeToHash: whatTypeToHash)
        if (let Some(refTarget) <- rt.ref.target) {
            SuperHash(refTarget.rawMangleName, whatTypeToHash: whatTypeToHash)
            CJC_ASSERT(refTarget.GetTy().isSome())
            SuperHash(refTarget.GetTy().getOrThrow().String(), whatTypeToHash: whatTypeToHash)
        }
    }

    private func HashTupleType(tt: TupleType, whatTypeToHash!: Int64 = ALL): Unit {
        HashType(tt, whatTypeToHash: whatTypeToHash)
        SuperHash(tt.fieldTypes, whatTypeToHash: whatTypeToHash)
    }

    private func HashVarDecl(vd: VarDecl, whatTypeToHash!: Int64 = ALL): Unit {
        HashVarDeclAbstract(vd, whatTypeToHash: whatTypeToHash)
        SuperHash(vd.isIdentifierCompilerAdd, whatTypeToHash: whatTypeToHash)
        SuperHash(vd.isResourceVar, whatTypeToHash: whatTypeToHash)
        SuperHash(vd.isMemberParam, whatTypeToHash: whatTypeToHash)
    }

    private func HashGenericParamDecl(gpd: GenericParamDecl, whatTypeToHash!: Int64 = ALL): Unit {
        HashDecl(gpd, whatTypeToHash: whatTypeToHash)
    }

    private func HashPattern(pattern: Pattern, whatTypeToHash!: Int64 = ALL): Unit {
        HashNode(pattern, whatTypeToHash: whatTypeToHash)
    }

    private func HashWildcardPattern(wp: WildcardPattern, whatTypeToHash!: Int64 = ALL): Unit {
        HashPattern(wp, whatTypeToHash: whatTypeToHash)
    }

    private func HashType(typeNode: Type, whatTypeToHash!: Int64 = ALL): Unit {
        SuperHash(typeNode.typeParameterName, whatTypeToHash: whatTypeToHash)
    }

    private func HashThisType(tt: ThisType, whatTypeToHash!: Int64 = ALL): Unit {
        HashType(tt, whatTypeToHash: whatTypeToHash)
    }

    private func HashOptionalExpr(oe: OptionalExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(oe, whatTypeToHash: whatTypeToHash)
        SuperHash(oe.baseExpr, whatTypeToHash: whatTypeToHash)
    }

    private func HashOptionalChainExpr(oce: OptionalChainExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(oce, whatTypeToHash: whatTypeToHash)
        SuperHash(oce.expr, whatTypeToHash: whatTypeToHash)
    }

    private func HashPrimitiveTypeExpr(pte: PrimitiveTypeExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(pte, whatTypeToHash: whatTypeToHash)
        SuperHash(Int64(TypeKindIndex(pte.typeKind)), whatTypeToHash: whatTypeToHash)
    }

    private func HashInterpolationExpr(ie: InterpolationExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(ie, whatTypeToHash: whatTypeToHash)
        SuperHash(ie.rawString, whatTypeToHash: whatTypeToHash)
        SuperHash(ie.dollarPos, whatTypeToHash: whatTypeToHash)
        SuperHash(ie.block, whatTypeToHash: whatTypeToHash)
    }

    private func HashStrInterpolationExpr(sie: StrInterpolationExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(sie, whatTypeToHash: whatTypeToHash)
        SuperHash(sie.rawString, whatTypeToHash: whatTypeToHash)
        SuperHash(sie.strParts, whatTypeToHash: whatTypeToHash)
        SuperHash(sie.strPartExprs, whatTypeToHash: whatTypeToHash)
    }

    private func HashJumpExpr(je: JumpExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(je, whatTypeToHash: whatTypeToHash)
        SuperHash(je.isBreak, whatTypeToHash: whatTypeToHash)
    }

    private func HashWildcardExpr(we: WildcardExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(we, whatTypeToHash: whatTypeToHash)
    }

    private func HashInvalidExpr(_: InvalidExpr, whatTypeToHash!: Int64 = ALL): Unit {
        let _ = whatTypeToHash
    }

    private func HashIfAvailableExpr(expr: IfAvailableExpr, whatTypeToHash!: Int64 = ALL): Unit {
        HashExpr(expr, whatTypeToHash: whatTypeToHash)
        SuperHash(expr.GetArg(), whatTypeToHash: whatTypeToHash)
        SuperHash(expr.GetLambda1(), whatTypeToHash: whatTypeToHash)
        SuperHash(expr.GetLambda2(), whatTypeToHash: whatTypeToHash)
    }

    public func Hash<T>(node: Option<T>, whatTypeToHash!: Int64 = ALL): UInt64 where T <: Node {
        if (let Some(valueNode) <- node) {
            return Hash(valueNode, whatTypeToHash: whatTypeToHash)
        }
        return value
    }

    public func Hash(node: Node, whatTypeToHash!: Int64 = ALL): UInt64 {
        match (node.astKind) {
            case ASTKind.ARRAY_EXPR => HashArrayExpr((node as ArrayExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.ARRAY_LIT => HashArrayLit((node as ArrayLit).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.AS_EXPR => HashAsExpr((node as AsExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.ASSIGN_EXPR => HashAssignExpr((node as AssignExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.BINARY_EXPR => HashBinaryExpr((node as BinaryExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.BLOCK => HashBlock((node as Block).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.CALL_EXPR => HashCallExpr((node as CallExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.CONST_PATTERN => HashConstPattern((node as ConstPattern).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.CONSTANT_TYPE => HashConstantType((node as ConstantType).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.DO_WHILE_EXPR => HashDoWhileExpr((node as DoWhileExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.ENUM_PATTERN => HashEnumPattern((node as EnumPattern).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.EXCEPT_TYPE_PATTERN => HashExceptTypePattern((node as ExceptTypePattern).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.FOR_IN_EXPR => HashForInExpr((node as ForInExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.FUNC_ARG => HashFuncArg((node as FuncArg).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.FUNC_BODY => HashFuncBody((node as FuncBody).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.FUNC_DECL => HashFuncDecl((node as FuncDecl).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.FUNC_PARAM => HashFuncParam((node as FuncParam).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.FUNC_PARAM_LIST => HashFuncParamList((node as FuncParamList).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.FUNC_TYPE => HashFuncType((node as FuncType).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.GENERIC => HashGeneric((node as Generic).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.GENERIC_CONSTRAINT => HashGenericConstraint((node as GenericConstraint).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.GENERIC_PARAM_DECL => HashGenericParamDecl((node as GenericParamDecl).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.IF_AVAILABLE_EXPR => HashIfAvailableExpr((node as IfAvailableExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.IF_EXPR => HashIfExpr((node as IfExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.IMPORT_SPEC => HashImportSpec((node as ImportSpec).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.INC_OR_DEC_EXPR => HashIncOrDecExpr((node as IncOrDecExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.INTERPOLATION_EXPR => HashInterpolationExpr((node as InterpolationExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.INVALID_EXPR => HashInvalidExpr((node as InvalidExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.IS_EXPR => HashIsExpr((node as IsExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.JUMP_EXPR => HashJumpExpr((node as JumpExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.LAMBDA_EXPR => HashLambdaExpr((node as LambdaExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.LET_PATTERN_DESTRUCTOR => HashLetPatternDestructor((node as LetPatternDestructor).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.LIT_CONST_EXPR => HashLitConstExpr((node as LitConstExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.MATCH_CASE => HashMatchCase((node as MatchCase).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.MATCH_CASE_OTHER => HashMatchCaseOther((node as MatchCaseOther).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.MATCH_EXPR => HashMatchExpr((node as MatchExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.MEMBER_ACCESS => HashMemberAccess((node as MemberAccess).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.OPTION_TYPE => HashOptionType((node as OptionType).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.OPTIONAL_CHAIN_EXPR => HashOptionalChainExpr((node as OptionalChainExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.OPTIONAL_EXPR => HashOptionalExpr((node as OptionalExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.PACKAGE_SPEC => HashPackageSpec((node as PackageSpec).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.PAREN_EXPR => HashParenExpr((node as ParenExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.PAREN_TYPE => HashParenType((node as ParenType).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.PERFORM_EXPR => HashPerformExpr((node as PerformExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.POINTER_EXPR => HashPointerExpr((node as PointerExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.PRIMITIVE_TYPE => HashPrimitiveType((node as PrimitiveType).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.PRIMITIVE_TYPE_EXPR => HashPrimitiveTypeExpr((node as PrimitiveTypeExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.QUALIFIED_TYPE => HashQualifiedType((node as QualifiedType).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.QUOTE_EXPR => HashQuoteExpr((node as QuoteExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.RANGE_EXPR => HashRangeExpr((node as RangeExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.REF_EXPR => HashRefExpr((node as RefExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.REF_TYPE => HashRefType((node as RefType).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.RESUME_EXPR => HashResumeExpr((node as ResumeExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.RETURN_EXPR => HashReturnExpr((node as ReturnExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.SPAWN_EXPR => HashSpawnExpr((node as SpawnExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.STR_INTERPOLATION_EXPR => HashStrInterpolationExpr((node as StrInterpolationExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.SUBSCRIPT_EXPR => HashSubscriptExpr((node as SubscriptExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.SYNCHRONIZED_EXPR => HashSynchronizedExpr((node as SynchronizedExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.THIS_TYPE => HashThisType((node as ThisType).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.THROW_EXPR => HashThrowExpr((node as ThrowExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.TRAIL_CLOSURE_EXPR => HashTrailingClosureExpr((node as TrailingClosureExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.TRY_EXPR => HashTryExpr((node as TryExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.TUPLE_LIT => HashTupleLit((node as TupleLit).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.TUPLE_PATTERN => HashTuplePattern((node as TuplePattern).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.TUPLE_TYPE => HashTupleType((node as TupleType).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.TYPE_CONV_EXPR => HashTypeConvExpr((node as TypeConvExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.TYPE_PATTERN => HashTypePattern((node as TypePattern).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.UNARY_EXPR => HashUnaryExpr((node as UnaryExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.VARRAY_TYPE => HashVArrayType((node as VArrayType).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.VAR_DECL => HashVarDecl((node as VarDecl).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.VAR_OR_ENUM_PATTERN => HashVarOrEnumPattern((node as VarOrEnumPattern).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.VAR_PATTERN => HashVarPattern((node as VarPattern).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.VAR_WITH_PATTERN_DECL => HashVarWithPatternDecl((node as VarWithPatternDecl).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.WHILE_EXPR => HashWhileExpr((node as WhileExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.WILDCARD_EXPR => HashWildcardExpr((node as WildcardExpr).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case ASTKind.WILDCARD_PATTERN => HashWildcardPattern((node as WildcardPattern).getOrThrow(), whatTypeToHash: whatTypeToHash)
            case _ =>
                CJC_ASSERT(false)
        }
        return value
    }

    public static func IsConsideredInSignatureHash(anno: Annotation): Bool {
        match (anno.kind) {
            case AnnotationKind.C | AnnotationKind.CALLING_CONV | AnnotationKind.INTRINSIC |
                AnnotationKind.JAVA | AnnotationKind.JAVA_MIRROR | AnnotationKind.JAVA_IMPL |
                AnnotationKind.OBJ_C_MIRROR | AnnotationKind.OBJ_C_IMPL | AnnotationKind.FOREIGN_NAME |
                AnnotationKind.WHEN | AnnotationKind.DEPRECATED => return true
            case AnnotationKind.ATTRIBUTE | AnnotationKind.NUMERIC_OVERFLOW | AnnotationKind.FASTNATIVE |
                AnnotationKind.ANNOTATION | AnnotationKind.CUSTOM | AnnotationKind.FROZEN |
                AnnotationKind.NO_HEAP_ALLOC | AnnotationKind.NO_WRITE_BARRIER_REC |
                AnnotationKind.NO_STACK_GROW => return false
            case _ =>
                CJC_ASSERT(false)
                return false
        }
    }

    public static func IsConsideredInBodyHash(anno: Annotation): Bool {
        match (anno.kind) {
            case AnnotationKind.ATTRIBUTE => return false
            case AnnotationKind.NUMERIC_OVERFLOW | AnnotationKind.FASTNATIVE | AnnotationKind.ANNOTATION |
                AnnotationKind.CUSTOM | AnnotationKind.DEPRECATED | AnnotationKind.FROZEN |
                AnnotationKind.NO_HEAP_ALLOC | AnnotationKind.NO_WRITE_BARRIER_REC |
                AnnotationKind.NO_STACK_GROW => return true
            case AnnotationKind.C | AnnotationKind.CALLING_CONV | AnnotationKind.INTRINSIC |
                AnnotationKind.JAVA | AnnotationKind.JAVA_MIRROR | AnnotationKind.JAVA_IMPL |
                AnnotationKind.OBJ_C_MIRROR | AnnotationKind.OBJ_C_IMPL | AnnotationKind.FOREIGN_NAME |
                AnnotationKind.WHEN => return !anno.args.isEmpty()
            case _ =>
                CJC_ASSERT(false)
                return false
        }
    }

    public func HashAnnotationsDeclBody(annos: ArrayList<Annotation>): Unit {
        let sigAnnos = ArrayList<Annotation>()
        var overflowAnnotationIndex = Int64.Max
        for (i in 0..annos.size) {
            let anno = annos[i]
            if (!ASTHasherImpl.IsConsideredInBodyHash(anno)) {
                continue
            }
            if (anno.kind == AnnotationKind.NUMERIC_OVERFLOW) {
                if (overflowAnnotationIndex == Int64.Max) {
                    overflowAnnotationIndex = i
                } else {
                    sigAnnos[overflowAnnotationIndex] = anno
                    continue
                }
            }
            sigAnnos.add(anno)
        }
        sort(sigAnnos, by: { left: Annotation, right: Annotation =>
            if (left.identifier.Val() < right.identifier.Val()) {
                Ordering.LT
            } else if (left.identifier.Val() > right.identifier.Val()) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        }, stable: true)
        for (anno in sigAnnos) {
            HashAnnotation(anno, whatTypeToHash: NON_POSITION)
        }
    }

    public func HashDeclBody(decl: Decl): Unit {
        if (let Some(generic) <- decl.generic) {
            if (decl.astKind != ASTKind.EXTEND_DECL) {
                HashConstraints(generic)
                let constraints = ArrayList<(String, GenericConstraint)>()
                for (constraintNode in generic.genericConstraints) {
                    constraints.add((constraintNode.refType.getOrThrow().ToString(), constraintNode))
                }
                sort(constraints, by: { left: (String, GenericConstraint), right: (String, GenericConstraint) =>
                    if (left[0] < right[0]) {
                        Ordering.LT
                    } else if (left[0] > right[0]) {
                        Ordering.GT
                    } else {
                        Ordering.EQ
                    }
                }, stable: true)
                for (constraint in constraints) {
                    HashGenericConstraints(constraint[1])
                }
            }
        }
        HashAnnotationsDeclBody(decl.annotations)
    }

    public static func SortTypes(upperBounds: ArrayList<Type>): ArrayList<Type> {
        let uppers = ArrayList<Type>()
        for (upper in upperBounds) {
            uppers.add(upper)
        }
        sort(uppers, by: { left: Type, right: Type =>
            if (left.ToString() < right.ToString()) {
                Ordering.LT
            } else if (left.ToString() > right.ToString()) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        }, stable: true)
        return uppers
    }

    public func HashGenericConstraints(gc: GenericConstraint): Unit {
        SuperHash(gc.refType, whatTypeToHash: NON_POSITION)
        SuperHash(ASTHasherImpl.SortTypes(gc.upperBounds), whatTypeToHash: NON_POSITION)
    }

    public func HashTypeAlias(decl: TypeAliasDecl): Unit {
        HashDeclBody(decl)
        SuperHash(decl.typeNode, whatTypeToHash: NON_POSITION)
    }

    public func HashConstraints(g: Generic): Unit {
        let constraints = ArrayList<(String, GenericConstraint)>()
        for (constraintNode in g.genericConstraints) {
            constraints.add((constraintNode.refType.getOrThrow().ToString(), constraintNode))
        }
        sort(constraints, by: { left: (String, GenericConstraint), right: (String, GenericConstraint) =>
            if (left[0] < right[0]) {
                Ordering.LT
            } else if (left[0] > right[0]) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        }, stable: true)
        for (constraint in constraints) {
            HashGenericConstraints(constraint[1])
        }
    }

    public func HashSpecificModifiers(decl: Decl, kinds: Array<TokenKind>): Unit {
        let mods = ArrayList<Int64>()
        var impliedOpen = false
        var hasOpen = false
        var hashVisibilityModifier = false
        for (mod in decl.modifiers) {
            if (In(kinds, mod.modifier)) {
                mods.add(TokenKindIndex(mod.modifier))
                if (mod.modifier == TokenKind.ABSTRACT) {
                    impliedOpen = true
                } else if (mod.modifier == TokenKind.OPEN) {
                    hasOpen = true
                } else if (mod.modifier == TokenKind.SEALED) {
                    impliedOpen = true
                }
            }
            if (mod.modifier == TokenKind.PUBLIC || mod.modifier == TokenKind.PROTECTED ||
                mod.modifier == TokenKind.PRIVATE || mod.modifier == TokenKind.INTERNAL) {
                hashVisibilityModifier = true
            }
        }
        if (In(kinds, TokenKind.PUBLIC)) {
            if (let Some(outer) <- decl.outerDecl) {
                if (outer.astKind == ASTKind.INTERFACE_DECL) {
                    hashVisibilityModifier = true
                    mods.add(TokenKindIndex(TokenKind.PUBLIC))
                }
            }
        }
        if (In(kinds, TokenKind.INTERNAL) && !hashVisibilityModifier) {
            mods.add(TokenKindIndex(TokenKind.INTERNAL))
        }
        if (In(kinds, TokenKind.OPEN) && impliedOpen && !hasOpen) {
            mods.add(TokenKindIndex(TokenKind.OPEN))
        }
        sort(mods, by: { left: Int64, right: Int64 =>
            if (left < right) {
                Ordering.LT
            } else if (left > right) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        }, stable: true)
        for (mod in mods) {
            CombineHash(mod)
        }
    }

    public func HashVirtual(decl: Decl): Unit {
        if (let None <- decl.outerDecl) {
            return
        }
        if (let Some(outer) <- decl.outerDecl) {
            if (let None <- (outer as InheritableDecl)) {
                return
            }
            if (!outer.IsOpen()) {
                return
            }
        }
        HashSpecificModifiers(decl, [TokenKind.OPEN, TokenKind.ABSTRACT])
    }

    public func HashBodyOfFuncLike(funcBody: FuncBody, srcInfo: (Bool, Bool)): Unit {
        for (param in funcBody.paramLists[0].params) {
            if (!param.isNamedParam && !param.hasLetOrVar) {
                CombineHash(param.identifier.Val())
            }
            if (srcInfo[0] || srcInfo[1]) {
                let _ = CombineTwoHashes(Hash(param.assignment, whatTypeToHash: ALL))
            } else {
                let _ = CombineTwoHashes(Hash(param.assignment, whatTypeToHash: NON_POSITION))
            }
            if (srcInfo[0]) {
                CombineHash(param.begin)
            }
        }
        if (let Some(body) <- funcBody.body) {
            if (srcInfo[0] || srcInfo[1]) {
                let _ = CombineTwoHashes(Hash(body, whatTypeToHash: ALL))
            } else {
                let _ = CombineTwoHashes(Hash(body, whatTypeToHash: NON_POSITION))
            }
        }
    }

    public func BodyHashAnnotations(annos: ArrayList<Annotation>): Unit {
        let cons = ArrayList<Annotation>()
        var overflowAnnotation: Option<Annotation> = None
        for (anno in annos) {
            if (anno.kind == AnnotationKind.NUMERIC_OVERFLOW) {
                overflowAnnotation = anno
                continue
            }
            if (anno.kind != AnnotationKind.ANNOTATION) {
                cons.add(anno)
            }
        }
        if (let Some(overflowValue) <- overflowAnnotation) {
            cons.add(overflowValue)
        }
        HashAnnotationsNoOrder(cons)
    }

    public func HashAnnotationsNoOrder(annos: ArrayList<Annotation>): Unit {
        let hashes = ArrayList<UInt64>()
        for (anno in annos) {
            let p = ASTHasherImpl()
            p.HashAnnotation(anno, whatTypeToHash: NON_POSITION)
            hashes.add(p.value)
        }
        sort(hashes, by: { left: UInt64, right: UInt64 =>
            if (left < right) {
                Ordering.LT
            } else if (left > right) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        }, stable: true)
        for (hashValue in hashes) {
            let _ = CombineTwoHashes(hashValue)
        }
    }

    public func SrcUseHashAnnotations(annos: ArrayList<Annotation>): Unit {
        let cons = ArrayList<Annotation>()
        for (anno in annos) {
            if (anno.kind == AnnotationKind.ANNOTATION) {
                cons.add(anno)
            }
        }
        HashAnnotationsNoOrder(cons)
    }

    public func HashMemberSignature(decl: Decl): Unit {
        SuperHash(decl.identifier.Val(), whatTypeToHash: NON_POSITION)
        SuperHash(decl.generic, whatTypeToHash: NON_POSITION)
        if (let Some(funcDeclValue) <- (decl as FuncDecl)) {
            SuperHash(funcDeclValue.funcBody.getOrThrow().paramLists[0].params, whatTypeToHash: NON_POSITION)
            if (let Some(retType) <- funcDeclValue.funcBody.getOrThrow().retType) {
                SuperHash(retType, whatTypeToHash: NON_POSITION)
            } else {
                SuperHash(funcDeclValue.funcBody.getOrThrow().body, whatTypeToHash: NON_POSITION)
            }
        } else if (let Some(propDeclValue) <- (decl as PropDecl)) {
            SuperHash(propDeclValue.typeNode, whatTypeToHash: NON_POSITION)
            HashSpecificModifiers(decl, [TokenKind.MUT])
        } else {
            CJC_ASSERT(false)
        }
    }
}

public class ASTHasher {
    public static func Init(op: GlobalOptions): Unit {
        g_needLineInfo = op.enableCompileDebug || op.displayLineInfo
        g_packagePath = None
        if (!op.packagePaths.isEmpty()) {
            g_packagePath = Some(op.packagePaths[0])
        }
        g_trimPaths.clear()
        for (path in op.removedPathPrefix) {
            g_trimPaths.add(path)
        }
    }

    @OverflowWrapping
    public static func CombineHash(acc: UInt64, value: UInt64): UInt64 {
        return acc ^ (value + 0x9e3779b9u64 + (acc << 6) + (acc >> 2))
    }

    public static func HashDeclBody(decl: Option<Decl>): UInt64 {
        if (let Some(value) <- decl) {
            let a = ASTHasherImpl()
            a.HashDeclBody(value)
            return a.value
        }
        return 0u64
    }

    public static func HashDeclSignature(decl: Option<Decl>): UInt64 {
        if (let Some(value) <- decl) {
            return SigHash(value)
        }
        return 0u64
    }

    public static func HashSpecs(pk: Package): UInt64 {
        let a = ASTHasherImpl()
        return a.HashSpecs(pk)
    }

    public static func HashSpecs(file: File): UInt64 {
        let a = ASTHasherImpl()
        for (importSpec in file.imports) {
            if (!importSpec.TestAttr(Attribute.IMPLICIT_ADD)) {
                a.Hash(importSpec, whatTypeToHash: NON_POSITION)
            }
        }
        if (let Some(pkgSpec) <- file.packageSpec) {
            a.Hash(pkgSpec, whatTypeToHash: NON_POSITION)
        }
        return a.value
    }

    public static func SigHash(decl: Decl): UInt64 {
        let a = ASTHasherImpl()
        a.HashSpecificModifiers(decl, [TokenKind.PUBLIC, TokenKind.PROTECTED, TokenKind.PRIVATE, TokenKind.INTERNAL])
        if (!IsClassOrEnumConstructor(decl) && decl.astKind != ASTKind.EXTEND_DECL) {
            if (let Some(generic) <- decl.GetGeneric()) {
                a.SuperHash(generic.typeParameters, whatTypeToHash: NON_POSITION)
                a.HashConstraints(generic)
            }
        }
        if (let Some(typeAlias) <- (decl as TypeAliasDecl)) {
            a.HashTypeAlias(typeAlias)
        }
        if (let Some(typeDecl) <- (decl as InheritableDecl)) {
            if (typeDecl.astKind != ASTKind.EXTEND_DECL) {
                for (parent in SortParentTypes(typeDecl)) {
                    let _ = a.Hash(parent, whatTypeToHash: NON_POSITION)
                }
            }
        }
        return a.value
    }

    public static func SrcUseHash(decl: Decl): UInt64 {
        let a = ASTHasherImpl()
        a.HashSpecificModifiers(decl, [
            TokenKind.OPEN, TokenKind.ABSTRACT, TokenKind.SEALED, TokenKind.MUT, TokenKind.STATIC, TokenKind.CONST,
            TokenKind.FOREIGN
        ])
        a.SrcUseHashAnnotations(decl.annotations)
        if (decl.astKind == ASTKind.VAR_DECL || decl.astKind == ASTKind.FUNC_PARAM) {
            let varDecl = (decl as VarDecl).getOrThrow()
            a.CombineHash(varDecl.isVar)
            a.CombineHash(varDecl.isConst)
        }
        if (let Some(propDeclValue) <- (decl as PropDecl)) {
            a.SuperHash(propDeclValue.typeNode, whatTypeToHash: NON_POSITION)
        }
        return a.value
    }

    public static func HashMemberAPIs(memberAPIs: ArrayList<Decl>): UInt64 {
        let hasher = ASTHasherImpl()
        let sortedMembers = ArrayList<Decl>()
        for (member in memberAPIs) {
            sortedMembers.add(member)
        }
        sort(sortedMembers, by: { left: Decl, right: Decl =>
            if (left.rawMangleName < right.rawMangleName) {
                Ordering.LT
            } else if (left.rawMangleName > right.rawMangleName) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        }, stable: true)
        for (memberAPI in sortedMembers) {
            hasher.HashMemberSignature(memberAPI)
            hasher.HashSpecificModifiers(memberAPI, [
                TokenKind.PUBLIC, TokenKind.PROTECTED, TokenKind.PRIVATE, TokenKind.INTERNAL, TokenKind.MUT,
                TokenKind.STATIC
            ])
        }
        return hasher.value
    }

    public static func BodyHash(decl: Decl, srcInfo!: (Bool, Bool) = (false, false),
        hashAnnos!: Bool = true): UInt64 {
        let a = ASTHasherImpl()
        a.HashSpecificModifiers(decl, [TokenKind.OVERRIDE, TokenKind.REDEF, TokenKind.UNSAFE])
        if (hashAnnos) {
            a.BodyHashAnnotations(decl.annotations)
        }

        if (let Some(outer) <- decl.outerDecl) {
            if (outer.astKind == ASTKind.ENUM_DECL && decl.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
                return a.value
            }
        }

        if (let Some(varDecl) <- (decl as VarDeclAbstract)) {
            if (varDecl.astKind == ASTKind.PROP_DECL) {
                return a.value
            }
            if (let Some(initExprValue) <- varDecl.initializer) {
                if (srcInfo[0] || srcInfo[1]) {
                    let _ = a.Hash(initExprValue, whatTypeToHash: ALL)
                } else {
                    let _ = a.Hash(initExprValue, whatTypeToHash: NON_POSITION)
                }
            }
            if (let Some(outer) <- varDecl.outerDecl) {
                if (outer.astKind == ASTKind.STRUCT_DECL || outer.astKind == ASTKind.CLASS_DECL) {
                    return a.value
                }
            }
            if (srcInfo[0] || srcInfo[1]) {
                a.CombineHash(decl.begin)
            }
        }
        if (let Some(funcBody) <- GetFuncBody(decl)) {
            a.HashBodyOfFuncLike(funcBody, srcInfo)
        }

        if (let Some(classDecl) <- (decl as ClassDecl)) {
            for (member in classDecl.GetMemberDeclPtrs()) {
                if (let Some(memberFunc) <- (member as FuncDecl)) {
                    if (memberFunc.IsFinalizer()) {
                        a.HashMemberSignature(memberFunc)
                    }
                }
            }
        }

        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            if (extendDecl.inheritedTypes.isEmpty()) {
                return a.value
            }
        }

        if (let Some(typeDecl) <- (decl as InheritableDecl)) {
            let visibleAPIs = GetVisibleAPIs(typeDecl.GetMemberDeclPtrs())
            sort(visibleAPIs, by: { left: Decl, right: Decl =>
                if (left.rawMangleName < right.rawMangleName) {
                    Ordering.LT
                } else if (left.rawMangleName > right.rawMangleName) {
                    Ordering.GT
                } else {
                    Ordering.EQ
                }
            }, stable: true)
            for (visibleAPI in visibleAPIs) {
                a.HashMemberSignature(visibleAPI)
                a.HashSpecificModifiers(visibleAPI, [
                    TokenKind.PUBLIC, TokenKind.PROTECTED, TokenKind.INTERNAL, TokenKind.PRIVATE, TokenKind.MUT,
                    TokenKind.STATIC
                ])
            }
        }
        return a.value
    }

    public static func ImportedDeclBodyHash(decl: Decl): UInt64 {
        let originalBodyHash = decl.hash.bodyHash
        let a = ASTHasherImpl()
        let newBodyHash = ASTHasher.BodyHash(decl, srcInfo: (false, false))
        let _ = a.CombineTwoHashes(originalBodyHash)
        let _ = a.CombineTwoHashes(newBodyHash)
        return a.value
    }

    public static func VirtualHash(decl: Decl): UInt64 {
        CJC_ASSERT(decl.astKind != ASTKind.INTERFACE_DECL)
        let virtuals = ArrayList<Decl>()
        for (member in decl.GetMemberDeclPtrs()) {
            if (IsVirtual(member)) {
                virtuals.add(member)
            }
        }
        let a = ASTHasherImpl()
        for (member in virtuals) {
            a.HashMemberSignature(member)
        }
        return a.value
    }
}

private func SortParentTypes(decl: InheritableDecl): ArrayList<Type> {
    let parents = ArrayList<Type>()
    let beginIndex: Int64 = if (decl.astKind == ASTKind.CLASS_DECL) { 1 } else { 0 }
    var idx = beginIndex
    while (idx < decl.inheritedTypes.size) {
        parents.add(decl.inheritedTypes[idx])
        idx++
    }
    sort(parents, by: { left: Type, right: Type =>
        if (left.ToString() < right.ToString()) {
            Ordering.LT
        } else if (left.ToString() > right.ToString()) {
            Ordering.GT
        } else {
            Ordering.EQ
        }
    }, stable: true)
    if (decl.astKind == ASTKind.CLASS_DECL && !decl.inheritedTypes.isEmpty()) {
        parents.add(decl.inheritedTypes[0])
    }
    return parents
}

private func IsVisibleAPI(member: Decl): Bool {
    return member.TestAttr(Attribute.PUBLIC) ||
        (member.outerDecl.getOrThrow().astKind != ASTKind.EXTEND_DECL && member.TestAttr(Attribute.PROTECTED))
}

private func GetVisibleAPIs(allMembers: ArrayList<Decl>): ArrayList<Decl> {
    let ret = ArrayList<Decl>()
    for (member in allMembers) {
        if (let Some(memberFunc) <- (member as FuncDecl)) {
            if (memberFunc.TestAnyAttr(Attribute.OPEN, Attribute.ABSTRACT, Attribute.CONSTRUCTOR) ||
                memberFunc.TestAnyAttr(Attribute.ENUM_CONSTRUCTOR, Attribute.PRIMARY_CONSTRUCTOR)) {
                continue
            }
            if (memberFunc.IsFinalizer()) {
                continue
            }
            if (IsVisibleAPI(memberFunc)) {
                ret.add(memberFunc)
            }
        }
        if (let Some(memberProp) <- (member as PropDecl)) {
            if (memberProp.TestAnyAttr(Attribute.OPEN, Attribute.ABSTRACT)) {
                continue
            }
            if (IsVisibleAPI(memberProp)) {
                ret.add(memberProp)
            }
        }
    }
    return ret
}

private func GetFuncBody(decl: Decl): Option<FuncBody> {
    match (decl.astKind) {
        case ASTKind.FUNC_DECL => return (decl as FuncDecl).getOrThrow().funcBody
        case ASTKind.PRIMARY_CTOR_DECL => return (decl as PrimaryCtorDecl).getOrThrow().funcBody
        case ASTKind.MAIN_DECL => return (decl as MainDecl).getOrThrow().funcBody
        case ASTKind.MACRO_DECL => return (decl as MacroDecl).getOrThrow().funcBody
        case _ => return None
    }
}

private func IsVirtual(decl: Decl): Bool {
    if (decl.TestAttr(Attribute.IMPORTED)) {
        return decl.TestAttr(Attribute.OPEN) || decl.TestAttr(Attribute.ABSTRACT)
    }
    if (let None <- decl.outerDecl) {
        return false
    }
    let outer = decl.outerDecl.getOrThrow()
    if (outer.astKind != ASTKind.CLASS_DECL && outer.astKind != ASTKind.INTERFACE_DECL) {
        return false
    }
    if (outer.astKind == ASTKind.INTERFACE_DECL && !decl.TestAttr(Attribute.STATIC)) {
        return true
    }
    if (decl.TestAnyAttr(Attribute.CONSTRUCTOR, Attribute.ENUM_CONSTRUCTOR)) {
        return false
    }
    if (outer.TestAttr(Attribute.ABSTRACT) && !decl.TestAttr(Attribute.STATIC)) {
        if (let Some(funcDeclValue) <- (decl as FuncDecl)) {
            if (let None <- funcDeclValue.funcBody.getOrThrow().body) {
                return true
            }
        }
        if (let Some(propDeclValue) <- (decl as PropDecl)) {
            if (propDeclValue.getters.isEmpty() && propDeclValue.setters.isEmpty()) {
                return true
            }
        }
    }
    return decl.TestAttr(Attribute.OPEN) || decl.TestAttr(Attribute.ABSTRACT)
}

private func IsClassOrEnumConstructor(decl: Decl): Bool {
    return decl.TestAttr(Attribute.CONSTRUCTOR) || decl.TestAttr(Attribute.ENUM_CONSTRUCTOR)
}

private func In(kinds: Array<TokenKind>, kind: TokenKind): Bool {
    for (value in kinds) {
        if (value == kind) {
            return true
        }
    }
    return false
}
