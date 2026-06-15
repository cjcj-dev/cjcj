package cangjie_compiler::ast

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
    public let dependencies: ArrayList<Decl> = ArrayList<Decl>()
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
        return GetMemberDecls()
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
                    out.add(interfaceTy)
                }
            }
        }
        return out
    }

    public func GetStableSuperInterfaceTys(): ArrayList<InterfaceTy> {
        return GetSuperInterfaceTys()
    }

    public func GetAllSuperDecls(): ArrayList<ClassLikeDecl> {
        let out = ArrayList<ClassLikeDecl>()
        if (let Some(selfClassLike) <- (this as ClassLikeDecl)) {
            out.add(selfClassLike)
        }
        return out
    }
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
        return identifier.GetRawText()
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
        return "type " + identifier.GetRawText()
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

    public override func IsOpen(): Bool {
        return TestAnyAttr(Attribute.OPEN, Attribute.ABSTRACT)
    }

    public override func ToString(): String {
        return "func " + identifier.GetRawText()
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

    public override func IsOpen(): Bool {
        return TestAnyAttr(Attribute.OPEN, Attribute.ABSTRACT)
    }
}

public class StructBody <: Node {
    public var leftCurlPos: Position = INVALID_POSITION
    public let decls: ArrayList<Decl> = ArrayList<Decl>()
    public var rightCurlPos: Position = INVALID_POSITION

    public init() {
        super(ASTKind.STRUCT_BODY)
    }
}

public class StructDecl <: InheritableDecl {
    public var body: Option<StructBody> = None

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
        if (let Some(value) <- body) {
            for (decl in value.decls) {
                if (decl.TestAttr(Attribute.CONSTRUCTOR) && (decl.IsConst() || decl.HasAnno(AnnotationKind.FROZEN))) {
                    return true
                }
            }
        }
        return false
    }
}

public class InterfaceBody <: Node {
    public var leftCurlPos: Position = INVALID_POSITION
    public let decls: ArrayList<Decl> = ArrayList<Decl>()
    public var rightCurlPos: Position = INVALID_POSITION

    public init() {
        super(ASTKind.INTERFACE_BODY)
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
}

public class ClassDecl <: ClassLikeDecl {
    public var body: Option<ClassBody> = None

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
        if (let Some(value) <- body) {
            for (decl in value.decls) {
                if (decl.TestAttr(Attribute.CONSTRUCTOR) && (decl.IsConst() || decl.HasAnno(AnnotationKind.FROZEN))) {
                    return true
                }
            }
        }
        return false
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
}

public class InvalidDecl <: Decl {
    public init(pos: Position) {
        super(ASTKind.INVALID_DECL)
        EnableAttr(Attribute.IS_BROKEN)
        begin = pos
        end = pos
        doNotExport = true
    }
}
