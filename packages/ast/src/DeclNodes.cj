package cangjie_compiler::ast

import cangjie_compiler::utils.CJC_NULLPTR_CHECK
import std.collection.*

public class DeclHash {
    public var instVar: UInt64 = 0
    public var virt: UInt64 = 0
    public var sig: UInt64 = 0
    public var srcUse: UInt64 = 0
    public var bodyHash: UInt64 = 0
    public var gvid: Int64 = 0
    public init() {}
}

public open class Decl <: Node {
    public let modifiers: ArrayList<Modifier> = ArrayList<Modifier>()
    public let annotations: ArrayList<Annotation> = ArrayList<Annotation>()
    public var annotationsArray: Option<ArrayLit> = None
    public var identifier: SrcIdentifier = SrcIdentifier()
    public var generic: Option<Generic> = None
    public var identifierForLsp: String = ""
    public var keywordPos: Position = INVALID_POSITION
    public var rawMangleName: String = ""
    public var hash: DeclHash = DeclHash()
    public var toBeCompiled: Bool = false
    public var mangledName: String = ""
    public var moduleName: String = ""
    public var fullPackageName: String = ""
    public var outerDecl: Option<Decl> = None
    public var genericDecl: Option<Decl> = None
    public var linkage: Linkage = Linkage.EXTERNAL
    public var doNotExport: Bool = false
    public var isUsedImports: Bool = false
    public var specificImplementation: Option<Decl> = None
    public let dependencies: ArrayList<Option<Decl>> = ArrayList<Option<Decl>>()
    public var checkFlag: InheritanceVisitStatus = InheritanceVisitStatus.UNVISITED
    public var captureIndex: UInt64 = 0

    public init() {
        super(ASTKind.DECL)
    }

    public init(kind: ASTKind) {
        super(kind)
    }

    public func IsMemberDecl(): Bool {
        if (let Some(parent) <- outerDecl) {
            return parent.IsNominalDecl()
        }
        return false
    }

    public func HasAnno(anno: AnnotationKind): Bool {
        for (item in annotations) {
            if (item.kind == anno) {
                return true
            }
        }
        return false
    }

    public open override func Clear(): Unit {
        checkFlag = InheritanceVisitStatus.UNVISITED
        super.Clear()
    }

    public open func GetMemberDecls(): ArrayList<Decl> {
        return ArrayList<Decl>()
    }

    public func GetMemberDeclPtrs(): ArrayList<Decl> {
        let results = ArrayList<Decl>()
        if (let Some(classDecl) <- (this as ClassDecl)) {
            CJC_NULLPTR_CHECK(classDecl.body)
            for (decl in classDecl.body.getOrThrow().decls) { results.add(decl) }
        } else if (let Some(interfaceDecl) <- (this as InterfaceDecl)) {
            CJC_NULLPTR_CHECK(interfaceDecl.body)
            for (decl in interfaceDecl.body.getOrThrow().decls) { results.add(decl) }
        } else if (let Some(structDecl) <- (this as StructDecl)) {
            CJC_NULLPTR_CHECK(structDecl.body)
            for (decl in structDecl.body.getOrThrow().decls) { results.add(decl) }
        } else if (let Some(enumDecl) <- (this as EnumDecl)) {
            for (constructor in enumDecl.constructors) { results.add(constructor) }
            for (decl in enumDecl.members) { results.add(decl) }
        } else if (let Some(extendDecl) <- (this as ExtendDecl)) {
            for (decl in extendDecl.members) { results.add(decl) }
        }
        return results
    }

    public func IsBuiltIn(): Bool {
        return astKind == ASTKind.BUILTIN_DECL
    }

    public func GetGeneric(): Option<Generic> {
        if (let Some(funcDecl) <- (this as FuncDecl)) {
            if (let Some(body) <- funcDecl.funcBody) {
                if (let Some(_) <- body.generic) {
                    return body.generic
                }
                if (let Some(parentEnum) <- body.parentEnum) {
                    if (funcDecl.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
                        return parentEnum.generic
                    }
                }
            }
        }
        if (let Some(varDecl) <- (this as VarDecl)) {
            if (let Some(outer) <- varDecl.outerDecl) {
                if (outer.astKind == ASTKind.ENUM_DECL) {
                    if (let Some(enumOuter) <- (outer as EnumDecl)) {
                        return enumOuter.generic
                    }
                }
            }
        }
        return generic
    }

    public func GetIdentifierPos(): Position {
        return GetMacroCallPos(identifier.Begin())
    }

    public open func IsExportedDecl(): Bool {
        if (TestAnyAttr(Attribute.PUBLIC, Attribute.PROTECTED)) {
            return true
        }
        if (TestAttr(Attribute.INTERNAL)) {
            if (let Some(file) <- curFile) {
                if (let Some(pkg) <- file.curPackage) {
                    return !pkg.noSubPkg
                }
            }
            return true
        }
        if (TestAttr(Attribute.PRIVATE)) {
            return false
        }
        return true
    }

    public func IsConst(): Bool {
        if (let Some(varDecl) <- (this as VarDeclAbstract)) {
            return varDecl.isConst
        }
        if (let Some(funcDecl) <- (this as FuncDecl)) {
            return funcDecl.isConst
        }
        if (let Some(primaryCtor) <- (this as PrimaryCtorDecl)) {
            return primaryCtor.isConst
        }
        return false
    }

    public func GetDesugarDecl(): Option<FuncDecl> {
        if (let Some(macroDecl) <- (this as MacroDecl)) {
            return macroDecl.desugarDecl
        }
        if (let Some(mainDecl) <- (this as MainDecl)) {
            return mainDecl.desugarDecl
        }
        if (let Some(funcParam) <- (this as FuncParam)) {
            return funcParam.desugarDecl
        }
        return None
    }

    public func IsCommonOrSpecific(): Bool {
        return TestAttr(Attribute.COMMON) || TestAttr(Attribute.SPECIFIC)
    }

    public func IsCommonMatchedWithSpecific(): Bool {
        if (!TestAttr(Attribute.COMMON)) {
            return false
        }
        if (let Some(_) <- specificImplementation) {
            return true
        }
        return false
    }

    public func GetGenericsCount(): Int64 {
        if (!TestAttr(Attribute.GENERIC)) {
            return 0
        }
        if (let Some(node) <- GetGeneric()) {
            return node.typeParameters.size
        }
        return 0
    }
}

public open class InheritableDecl <: Decl {
    public var upperBoundPos: Position = INVALID_POSITION
    public let inheritedTypes: ArrayList<Type> = ArrayList<Type>()

    public init(kind: ASTKind) {
        super(kind)
    }

    public func GetSuperInterfaceTys(): ArrayList<InterfaceTy> {
        let out = ArrayList<InterfaceTy>()
        for (typeNode in inheritedTypes) {
            if (let Some(ty) <- typeNode.GetTy()) {
                if (let Some(interfaceTy) <- (ty as InterfaceTy)) {
                    addInterfaceTyUnique(out, interfaceTy)
                }
            }
        }
        return out
    }

    public func GetStableSuperInterfaceTys(): ArrayList<InterfaceTy> {
        let out = ArrayList<InterfaceTy>()
        for (interfaceTy in GetSuperInterfaceTys()) {
            insertInterfaceTyByName(out, interfaceTy)
        }
        return out
    }

    public func GetAllSuperDecls(): ArrayList<ClassLikeDecl> {
        let out = ArrayList<ClassLikeDecl>()
        let workList = ArrayList<InheritableDecl>()
        if (let Some(selfClassLike) <- (this as ClassLikeDecl)) {
            out.add(selfClassLike)
            workList.add(selfClassLike)
        } else {
            workList.add(this)
        }
        var workIdx: Int64 = 0
        while (workIdx < workList.size) {
            let current = workList[workIdx]
            workIdx++
            for (typeNode in current.inheritedTypes) {
                if (let Some(ty) <- typeNode.GetTy()) {
                    if (let Some(classTy) <- (ty as ClassTy)) {
                        if (let Some(classDecl) <- classTy.declPtr) {
                            if (!containsClassLikeDecl(out, classDecl)) {
                                workList.add(classDecl)
                                out.add(classDecl)
                            }
                        }
                    } else if (let Some(interfaceTy) <- (ty as InterfaceTy)) {
                        if (let Some(interfaceDecl) <- interfaceTy.declPtr) {
                            if (!containsClassLikeDecl(out, interfaceDecl)) {
                                workList.add(interfaceDecl)
                                out.add(interfaceDecl)
                            }
                        }
                    }
                }
            }
        }
        return out
    }
}

private func addInterfaceTyUnique(values: ArrayList<InterfaceTy>, ty: InterfaceTy): Unit {
    for (value in values) {
        if (sameInterfaceTy(value, ty)) {
            return
        }
    }
    values.add(ty)
}

private func insertInterfaceTyByName(values: ArrayList<InterfaceTy>, ty: InterfaceTy): Unit {
    var idx: Int64 = 0
    while (idx < values.size) {
        if (sameInterfaceTyForStableOrder(values[idx], ty)) {
            return
        }
        if (CompTyByNames(ty, values[idx])) {
            values.add(ty, at: idx)
            return
        }
        idx++
    }
    values.add(ty)
}

private func sameInterfaceTy(left: InterfaceTy, right: InterfaceTy): Bool {
    return left.objectId == right.objectId
}

private func sameInterfaceTyForStableOrder(left: InterfaceTy, right: InterfaceTy): Bool {
    return !CompTyByNames(left, right) && !CompTyByNames(right, left)
}

private func containsClassLikeDecl(values: ArrayList<ClassLikeDecl>, decl: ClassLikeDecl): Bool {
    for (value in values) {
        if (SameDecl(value, decl)) {
            return true
        }
    }
    return false
}

private func extendTypeArgsAllExported(decl: ExtendDecl): Bool {
    if (let Some(extended) <- decl.extendedType) {
        for (typeArg in extended.GetTypeArgs()) {
            if (let Some(target) <- typeArg.GetTarget()) {
                if (!target.IsExportedDecl()) {
                    return false
                }
            }
        }
    }
    return true
}

private func extendUpperBoundsAllExported(decl: ExtendDecl): Bool {
    if (let Some(generic) <- decl.generic) {
        var allExported = true
        for (constraint in generic.genericConstraints) {
            for (upperBound in constraint.upperBounds) {
                if (let Some(target) <- upperBound.GetTarget()) {
                    allExported = target.IsExportedDecl() && allExported
                }
            }
        }
        return allExported
    }
    return true
}

private func hasExportedInheritedInterface(decl: ExtendDecl): Bool {
    for (inheritedType in decl.inheritedTypes) {
        if (let Some(target) <- inheritedType.GetTarget()) {
            if (target.IsExportedDecl()) {
                return true
            }
        }
    }
    return false
}

private func isExtendMemberExported(decl: Decl, baseExported: Bool): Bool {
    if (let Some(outer) <- decl.outerDecl) {
        if (outer.astKind != ASTKind.EXTEND_DECL) {
            return baseExported
        }
        if (let Some(extendDecl) <- (outer as ExtendDecl)) {
            if (let Some(extendedDecl) <- Ty.GetDeclPtrOfTy(extendDecl.GetTy())) {
                if (extendedDecl.fullPackageName == extendDecl.fullPackageName) {
                    return baseExported
                }
            } else {
                return baseExported
            }
            if (extendDecl.inheritedTypes.isEmpty()) {
                return false
            }
            return baseExported && decl.TestAttr(Attribute.INTERFACE_IMPL)
        }
    }
    return baseExported
}

private func isOpenMemberDecl(decl: Decl, hasBodyOrAccessor: Bool): Bool {
    if (let Some(outer) <- decl.outerDecl) {
        if (!outer.IsOpen() || decl.TestAttr(Attribute.STATIC)) {
            return false
        }
    } else {
        return false
    }
    if (decl.TestAnyAttr(Attribute.OPEN, Attribute.ABSTRACT)) {
        return true
    }
    return !decl.TestAttr(Attribute.IMPORTED) && !hasBodyOrAccessor
}

private func modifierPrefix(modifiers: ArrayList<Modifier>): String {
    var out = ""
    for (modifier in modifiers) {
        let text = modifier.ToString()
        if (!text.isEmpty()) {
            out += text + " "
        }
    }
    return out
}

private func joinFuncParamLists(values: ArrayList<FuncParamList>): String {
    let parts = ArrayList<String>()
    for (value in values) {
        parts.add(value.ToString())
    }
    return JoinStrings(parts, " ")
}

private func joinGenericConstraints(values: ArrayList<GenericConstraint>): String {
    let parts = ArrayList<String>()
    for (value in values) {
        parts.add(value.ToString())
    }
    return JoinStrings(parts, ", ")
}

private func declBlockString(values: ArrayList<Decl>): String {
    var out = "{"
    for (decl in values) {
        out += "\n" + decl.ToString()
    }
    if (!values.isEmpty()) {
        out += "\n"
    }
    out += "}"
    return out
}

public enum BuiltInType {
    | ARRAY
    | POINTER
    | CSTRING
    | CFUNC
    | VARRAY
}

public class BuiltInDecl <: Decl {
    public var builtinType: BuiltInType = BuiltInType.ARRAY

    public init(builtinType: BuiltInType) {
        super(ASTKind.BUILTIN_DECL)
        this.builtinType = builtinType
    }

    public func IsType(expected: BuiltInType): Bool {
        return builtinType == expected
    }
}

private func BuiltInTypeIndex(kind: BuiltInType): Int64 {
    return match (kind) {
        case BuiltInType.ARRAY => 0
        case BuiltInType.POINTER => 1
        case BuiltInType.CSTRING => 2
        case BuiltInType.CFUNC => 3
        case BuiltInType.VARRAY => 4
    }
}

extend BuiltInType <: Equatable<BuiltInType> {
    public operator func ==(right: BuiltInType): Bool {
        return BuiltInTypeIndex(this) == BuiltInTypeIndex(right)
    }

    public operator func !=(right: BuiltInType): Bool {
        return !(this == right)
    }
}

public class GenericParamDecl <: Decl {
    public var commaPos: Position = INVALID_POSITION

    public init() {
        super(ASTKind.GENERIC_PARAM_DECL)
    }

    public override func ToString(): String {
        return identifier.GetRawText()
    }
}

public open class VarDeclAbstract <: Decl {
    public var typeNode: Option<Type> = None
    public var colonPos: Position = INVALID_POSITION
    public var initializer: Option<Expr> = None
    public var assignPos: Position = INVALID_POSITION
    public var isVar: Bool = false
    public var isConst: Bool = false

    public init(kind: ASTKind) {
        super(kind)
    }
}

public open class VarDecl <: VarDeclAbstract {
    public var parentPattern: Option<Pattern> = None
    public var isIdentifierCompilerAdd: Bool = false
    public var isResourceVar: Bool = false
    public var isMemberParam: Bool = false

    public init() {
        super(ASTKind.VAR_DECL)
    }

    public init(kind: ASTKind) {
        super(kind)
    }

    public open override func ToString(): String {
        let keyword = if (isConst) { "const" } else if (isVar) { "var" } else { "let" }
        var out = keyword + " " + identifier.GetRawText()
        if (let Some(typeValue) <- typeNode) {
            out += ": " + typeValue.ToString()
        }
        if (let Some(initNode) <- initializer) {
            out += " = " + initNode.ToString()
        }
        return out
    }
}

public class VarWithPatternDecl <: VarDeclAbstract {
    public var irrefutablePattern: Option<Pattern> = None

    public init() {
        super(ASTKind.VAR_WITH_PATTERN_DECL)
    }
}

public open class FuncParam <: VarDecl {
    public var notMarkPos: Position = INVALID_POSITION
    public var assignment: Option<Expr> = None
    public var commaPos: Position = INVALID_POSITION
    public var desugarDecl: Option<FuncDecl> = None
    public var isNamedParam: Bool = false
    public var hasLetOrVar: Bool = false

    public init() {
        super(ASTKind.FUNC_PARAM)
    }

    public init(kind: ASTKind) {
        super(kind)
    }

    public open override func Clear(): Unit {
        super.Clear()
        DisableAttr(Attribute.HAS_INITIAL)
    }

    public open override func ToString(): String {
        var out = identifier.Val()
        if (isNamedParam) {
            out += "!"
        }
        if (let Some(value) <- typeNode) {
            out += ": " + value.ToString()
        }
        return out
    }
}

public class DummyBody <: Node {
    public init() {
        super(ASTKind.DUMMY_BODY)
    }
}

public class EnumDecl <: InheritableDecl {
    public var leftCurlPos: Position = INVALID_POSITION
    public var bodyScope: Option<DummyBody> = None
    public let constructors: ArrayList<Decl> = ArrayList<Decl>()
    public let bitOrPosVector: ArrayList<Position> = ArrayList<Position>()
    public let members: ArrayList<Decl> = ArrayList<Decl>()
    public var rightCurlPos: Position = INVALID_POSITION
    public var hasArguments: Bool = false
    public var hasEllipsis: Bool = false
    public var ellipsisPos: Position = INVALID_POSITION

    public init() {
        super(ASTKind.ENUM_DECL)
    }

    public override func GetMemberDecls(): ArrayList<Decl> {
        return members
    }
}

public class TypeAliasDecl <: Decl {
    public var assignPos: Position = INVALID_POSITION
    public var typeNode: Option<Type> = None

    public init() {
        super(ASTKind.TYPE_ALIAS_DECL)
    }

    public override func ToString(): String {
        var out = modifierPrefix(modifiers) + "type " + identifier.Val()
        if (let Some(value) <- generic) {
            out += value.ToString()
        }
        CJC_NULLPTR_CHECK(typeNode)
        out += " = " + typeNode.getOrThrow().ToString()
        return out
    }
}

public class FuncParamList <: Node {
    public var leftParenPos: Position = INVALID_POSITION
    public let params: ArrayList<FuncParam> = ArrayList<FuncParam>()
    public var rightParenPos: Position = INVALID_POSITION
    public var variadicArgIndex: UInt64 = 0
    public var hasVariableLenArg: Bool = false

    public init() {
        super(ASTKind.FUNC_PARAM_LIST)
    }

    public override func ToString(): String {
        let parts = ArrayList<String>()
        for (param in params) {
            parts.add(param.ToString())
        }
        return "(" + JoinStrings(parts, ", ") + ")"
    }
}

public enum CaptureKind {
    | NO_CAPTURE
    | CAPTURE_VAR
    | TRANSITIVE_CAPTURE
}

public class FuncBody <: Node {
    public let paramLists: ArrayList<FuncParamList> = ArrayList<FuncParamList>()
    public var doubleArrowPos: Position = INVALID_POSITION
    public var colonPos: Position = INVALID_POSITION
    public var retType: Option<Type> = None
    public var body: Option<Block> = None
    public var generic: Option<Generic> = None
    public var funcDecl: Option<FuncDecl> = None
    public let capturedVars: ArrayList<NameReferenceExpr> = ArrayList<NameReferenceExpr>()
    public var outerFunc: Option<FuncBody> = None
    public var parentClassLike: Option<ClassLikeDecl> = None
    public var parentStruct: Option<StructDecl> = None
    public var parentEnum: Option<EnumDecl> = None
    public var captureKind: CaptureKind = CaptureKind.NO_CAPTURE

    public init() {
        super(ASTKind.FUNC_BODY)
    }

    public override func Clear(): Unit {
        super.Clear()
        capturedVars.clear()
    }

    public override func ToString(): String {
        var out = ""
        if (let Some(value) <- generic) {
            out += value.ToString()
        }
        out += joinFuncParamLists(paramLists)
        if (let Some(value) <- retType) {
            if (!colonPos.IsZero()) {
                out += ": "
            } else if (!doubleArrowPos.IsZero()) {
                out += " => "
            }
            out += value.ToString()
        }
        if (let Some(value) <- generic) {
            if (!value.genericConstraints.isEmpty()) {
                out += " where " + joinGenericConstraints(value.genericConstraints)
            }
        }
        if (let Some(value) <- body) {
            out += " " + value.ToString()
        }
        return out
    }
}

public enum ConstructorCall {
    | NONE
    | OTHER_INIT
    | SUPER
}

public class FuncDecl <: Decl {
    public var leftParenPos: Position = INVALID_POSITION
    public var rightParenPos: Position = INVALID_POSITION
    public var funcBody: Option<FuncBody> = None
    public var ownerFunc: Option<FuncDecl> = None
    public var propDecl: Option<PropDecl> = None
    public var overflowStrategy: OverflowStrategy = OverflowStrategy.NA
    public var constructorCall: ConstructorCall = ConstructorCall.NONE
    public var op: TokenKind = TokenKind.ILLEGAL
    public var variadicArgIndex: UInt64 = 0
    public var hasVariableLenArg: Bool = false
    public var isConst: Bool = false
    public var isSetter: Bool = false
    public var isGetter: Bool = false
    public var isInline: Bool = false
    public var isFastNative: Bool = false
    public var isReExportedOrRenamed: Bool = false
    public var isFrozen: Bool = false

    public init() {
        super(ASTKind.FUNC_DECL)
    }

    public func IsFinalizer(): Bool {
        return identifier == "~init"
    }

    public override func IsExportedDecl(): Bool {
        return isExtendMemberExported(this, super.IsExportedDecl())
    }

    public override func IsOpen(): Bool {
        if (let Some(outer) <- outerDecl) {
            if (!outer.IsOpen() || TestAttr(Attribute.STATIC)) {
                return false
            }
        } else {
            return false
        }
        if (TestAnyAttr(Attribute.OPEN, Attribute.ABSTRACT)) {
            return true
        }
        if (TestAttr(Attribute.IMPORTED)) {
            return false
        }
        if (let Some(_) <- funcBody.getOrThrow().body) {
            return false
        }
        return true
    }

    public override func ToString(): String {
        var out = modifierPrefix(modifiers) + "func " + identifier.Val()
        if (let Some(body) <- funcBody) {
            out += body.ToString()
        }
        return out
    }
}

public class MacroDecl <: Decl {
    public var funcBody: Option<FuncBody> = None
    public var desugarDecl: Option<FuncDecl> = None

    public init() {
        super(ASTKind.MACRO_DECL)
    }
}

public class MainDecl <: Decl {
    public var funcBody: Option<FuncBody> = None
    public var desugarDecl: Option<FuncDecl> = None
    public var overflowStrategy: OverflowStrategy = OverflowStrategy.NA
    public var isFastNative: Bool = false

    public init() {
        super(ASTKind.MAIN_DECL)
    }
}

public class PrimaryCtorDecl <: Decl {
    public var funcBody: Option<FuncBody> = None
    public var overflowStrategy: OverflowStrategy = OverflowStrategy.NA
    public var hasVariableLenArg: Bool = false
    public var isFastNative: Bool = false
    public var isConst: Bool = false

    public init() {
        super(ASTKind.PRIMARY_CTOR_DECL)
        doNotExport = true
    }
}

public class PropDecl <: VarDecl {
    public var leftCurlPos: Position = INVALID_POSITION
    public let getters: ArrayList<FuncDecl> = ArrayList<FuncDecl>()
    public let setters: ArrayList<FuncDecl> = ArrayList<FuncDecl>()
    public var rightCurlPos: Position = INVALID_POSITION

    public init() {
        super(ASTKind.PROP_DECL)
    }

    public override func IsExportedDecl(): Bool {
        return isExtendMemberExported(this, super.IsExportedDecl())
    }

    public override func IsOpen(): Bool {
        return isOpenMemberDecl(this, !getters.isEmpty() || !setters.isEmpty())
    }
}

public class StructBody <: Node {
    public var leftCurlPos: Position = INVALID_POSITION
    public let decls: ArrayList<Decl> = ArrayList<Decl>()
    public var rightCurlPos: Position = INVALID_POSITION

    public init() {
        super(ASTKind.STRUCT_BODY)
    }

    public override func ToString(): String {
        return declBlockString(decls)
    }
}

public class StructDecl <: InheritableDecl {
    public var body: Option<StructBody> = None
    private var hasConstOrFrozenInit: Option<Bool> = None

    public init() {
        super(ASTKind.STRUCT_DECL)
    }

    public override func GetMemberDecls(): ArrayList<Decl> {
        if (let Some(value) <- body) {
            return value.decls
        }
        return super.GetMemberDecls()
    }

    public func HasConstOrFrozenInit(): Bool {
        if (let Some(value) <- hasConstOrFrozenInit) {
            return value
        }
        CJC_NULLPTR_CHECK(body)
        let decls = body.getOrThrow().decls
        var has = false
        for (decl in decls) {
            if (decl.TestAttr(Attribute.CONSTRUCTOR) && (decl.IsConst() || decl.HasAnno(AnnotationKind.FROZEN))) {
                has = true
                break
            }
        }
        hasConstOrFrozenInit = has
        return has
    }
}

public class InterfaceBody <: Node {
    public var leftCurlPos: Position = INVALID_POSITION
    public let decls: ArrayList<Decl> = ArrayList<Decl>()
    public var rightCurlPos: Position = INVALID_POSITION

    public init() {
        super(ASTKind.INTERFACE_BODY)
    }

    public override func ToString(): String {
        return declBlockString(decls)
    }
}

public open class ClassLikeDecl <: InheritableDecl {
    public let subDecls: ArrayList<Decl> = ArrayList<Decl>()

    public init(kind: ASTKind) {
        super(kind)
    }
}

public class InterfaceDecl <: ClassLikeDecl {
    public var body: Option<InterfaceBody> = None

    public init() {
        super(ASTKind.INTERFACE_DECL)
    }

    public override func GetMemberDecls(): ArrayList<Decl> {
        if (let Some(value) <- body) {
            return value.decls
        }
        return super.GetMemberDecls()
    }

    public override func IsOpen(): Bool {
        return true
    }
}

public class ClassBody <: Node {
    public var leftCurlPos: Position = INVALID_POSITION
    public let decls: ArrayList<Decl> = ArrayList<Decl>()
    public var rightCurlPos: Position = INVALID_POSITION

    public init() {
        super(ASTKind.CLASS_BODY)
    }

    public override func ToString(): String {
        return declBlockString(decls)
    }
}

public class ClassDecl <: ClassLikeDecl {
    public var body: Option<ClassBody> = None
    private var hasConstOrFrozenInit: Option<Bool> = None

    public init() {
        super(ASTKind.CLASS_DECL)
    }

    public func GetSuperClassDecl(): Option<ClassDecl> {
        for (typeNode in inheritedTypes) {
            if (let Some(ty) <- typeNode.GetTy()) {
                if (let Some(classTy) <- (ty as ClassTy)) {
                    return classTy.decl
                }
            }
        }
        return None
    }

    public override func GetMemberDecls(): ArrayList<Decl> {
        if (let Some(value) <- body) {
            return value.decls
        }
        return super.GetMemberDecls()
    }

    public override func IsOpen(): Bool {
        return TestAnyAttr(Attribute.OPEN, Attribute.ABSTRACT)
    }

    public func HasConstOrFrozenInit(): Bool {
        if (let Some(value) <- hasConstOrFrozenInit) {
            return value
        }
        CJC_NULLPTR_CHECK(body)
        let decls = body.getOrThrow().decls
        var has = false
        for (decl in decls) {
            if (decl.TestAttr(Attribute.CONSTRUCTOR) && (decl.IsConst() || decl.HasAnno(AnnotationKind.FROZEN))) {
                has = true
                break
            }
        }
        hasConstOrFrozenInit = has
        return has
    }
}

public class ExtendDecl <: InheritableDecl {
    public var extendedType: Option<Type> = None
    public var wherePos: Position = INVALID_POSITION
    public var bodyScope: Option<DummyBody> = None
    public var leftCurlPos: Position = INVALID_POSITION
    public let members: ArrayList<Decl> = ArrayList<Decl>()
    public var rightCurlPos: Position = INVALID_POSITION

    public init() {
        super(ASTKind.EXTEND_DECL)
    }

    public override func GetMemberDecls(): ArrayList<Decl> {
        return members
    }

    public override func IsExportedDecl(): Bool {
        if (!extendTypeArgsAllExported(this)) {
            return false
        }
        let extendedDecl = Ty.GetInheritableDeclPtrOfTy(GetTy())
        let isInSamePkg = if (let Some(value) <- extendedDecl) {
            value.fullPackageName == fullPackageName
        } else {
            false
        }
        if (inheritedTypes.isEmpty()) {
            if (fullPackageName == "std.core") {
                return true
            }
            if (isInSamePkg) {
                if (let Some(value) <- extendedDecl) {
                    if (let Some(_) <- generic) {
                        return value.IsExportedDecl() && extendUpperBoundsAllExported(this)
                    }
                    return value.IsExportedDecl()
                }
            }
            return false
        }
        if (isInSamePkg) {
            if (let Some(value) <- extendedDecl) {
                return value.IsExportedDecl()
            }
        }
        let inheritedExported = hasExportedInheritedInterface(this)
        if (let Some(_) <- generic) {
            return inheritedExported && extendUpperBoundsAllExported(this)
        }
        return inheritedExported
    }
}

public class InvalidDecl <: Decl {
    public init(pos: Position) {
        super(ASTKind.INVALID_DECL)
        EnableAttr(Attribute.IS_BROKEN)
        begin = pos
        end = pos
        doNotExport = true
    }

    public override func ToString(): String {
        return "<invalid>"
    }
}
