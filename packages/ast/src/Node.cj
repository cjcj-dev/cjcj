package cjcj::ast

import std.collection.*
import std.sync.AtomicInt64

public enum ForInKind {
    | FORIN_INVALID
    | FORIN_RANGE
    | FORIN_STRING
    | FORIN_ITER
}

public enum StringKind {
    | NORMAL
    | JSTRING
    | MULTILINE
    | MULTILINE_RAW
}

public func StringKindIndex(kind: StringKind): Int64 {
    return match (kind) {
        case StringKind.NORMAL => 0
        case StringKind.JSTRING => 1
        case StringKind.MULTILINE => 2
        case StringKind.MULTILINE_RAW => 3
    }
}

public enum SuffixKind {
    | NONE
    | QUEST
}

private func GetOutermostMacroInvocation(node: Node): Option<MacroInvocation> {
    var cur = node
    while (let Some(parent) <- cur.curMacroCall) {
        cur = parent
    }
    return cur.GetInvocation()
}

private func FindPositionByUInt64Key(entries: ArrayList<(UInt64, Position)>, key: UInt64): Option<Position> {
    for (entry in entries) {
        if (entry[0] == key) {
            return entry[1]
        }
    }
    return None
}

private class AstObjectIdAllocator {
    private static let nextId = AtomicInt64(1)

    public static func Next(): Int64 {
        return nextId.fetchAdd(1)
    }
}

public open class Node <: Hashable & Equatable<Node> {
    public var begin: Position = INVALID_POSITION
    public var end: Position = INVALID_POSITION
    public var comments: CommentGroups = CommentGroups()
    public var symbol: Option<Symbol> = None
    public var scopeName: String = ""
    public var exportId: String = ""
    public var curFile: Option<File> = None
    public var curMacroCall: Option<Node> = None
    public var scopeLevel: UInt32 = 0u32
    public var visitedByWalkerID: UInt32 = 0u32
    public var mangleAdapterId: Int64 = -1
    public var isInMacroCall: Bool = false
    public let objectId: Int64
    public let astKind: ASTKind
    private var attributes: AttributePack = AttributePack()
    private var ty: Option<Ty> = Ty.GetInitialTy()

    public init() {
        objectId = AstObjectIdAllocator.Next()
        astKind = ASTKind.NODE
    }

    public init(kind: ASTKind) {
        objectId = AstObjectIdAllocator.Next()
        astKind = kind
    }

    public operator func ==(right: Node): Bool {
        return objectId == right.objectId
    }

    public operator func !=(right: Node): Bool {
        return objectId != right.objectId
    }

    public func hashCode(): Int64 {
        return objectId.hashCode()
    }

    public func GetTy(): Option<Ty> {
        return ty
    }

    public func TyKind(): TypeKind {
        if (let Some(value) <- ty) {
            return value.kind
        }
        return TypeKind.TYPE_INITIAL
    }

    public func SetTy(newTy: Ty): Unit {
        ty = newTy
    }

    public open func ToString(): String {
        return ""
    }

    public func GetAttrs(): AttributePack {
        return attributes.Clone()
    }

    public func CopyAttrs(attrs: AttributePack): Unit {
        attributes = attrs.Clone()
    }

    public func CloneAttrs(other: Node): Unit {
        attributes = other.attributes.Clone()
    }

    public func EnableAttr(attr: Attribute): Unit {
        attributes.SetAttr(attr, true)
    }

    public func DisableAttr(attr: Attribute): Unit {
        attributes.SetAttr(attr, false)
    }

    public func TestAttr(attr: Attribute): Bool {
        return attributes.TestAttr(attr)
    }

    public func TestAnyAttr(attr: Attribute): Bool {
        return TestAttr(attr)
    }

    public func TestAnyAttr(first: Attribute, second: Attribute): Bool {
        return TestAttr(first) || TestAttr(second)
    }

    public func TestAnyAttr(first: Attribute, second: Attribute, third: Attribute): Bool {
        return TestAttr(first) || TestAttr(second) || TestAttr(third)
    }

    public mut prop isBroken: Bool {
        get() { return TestAttr(Attribute.IS_BROKEN) }
        set(value) { if (value) { EnableAttr(Attribute.IS_BROKEN) } else { DisableAttr(Attribute.IS_BROKEN) } }
    }

    public mut prop hasBroken: Bool {
        get() { return TestAttr(Attribute.HAS_BROKEN) }
        set(value) { if (value) { EnableAttr(Attribute.HAS_BROKEN) } else { DisableAttr(Attribute.HAS_BROKEN) } }
    }

    public open func Clear(): Unit {
        DisableAttr(Attribute.INITIALIZED)
        DisableAttr(Attribute.INITIALIZATION_CHECKED)
        DisableAttr(Attribute.IS_CHECK_VISITED)
        ty = Ty.GetInitialTy()
    }

    public func IsStructOrClassDecl(): Bool {
        return astKind == ASTKind.CLASS_DECL || astKind == ASTKind.STRUCT_DECL
    }

    public func IsNominalDecl(): Bool {
        return astKind == ASTKind.CLASS_DECL || astKind == ASTKind.INTERFACE_DECL ||
            astKind == ASTKind.STRUCT_DECL || astKind == ASTKind.EXTEND_DECL || astKind == ASTKind.ENUM_DECL
    }

    public func IsNominalDeclBody(): Bool {
        return astKind == ASTKind.CLASS_BODY || astKind == ASTKind.INTERFACE_BODY ||
            astKind == ASTKind.STRUCT_BODY || astKind == ASTKind.DUMMY_BODY
    }

    public func IsClassLikeDecl(): Bool {
        return astKind == ASTKind.CLASS_DECL || astKind == ASTKind.INTERFACE_DECL
    }

    public func IsInterfaceDecl(): Bool {
        return astKind == ASTKind.INTERFACE_DECL
    }

    public func IsAbstractClass(): Bool {
        return astKind == ASTKind.CLASS_DECL && TestAttr(Attribute.ABSTRACT)
    }

    public func IsClassLikeDeclBody(): Bool {
        return astKind == ASTKind.CLASS_BODY || astKind == ASTKind.INTERFACE_BODY
    }

    public func IsFuncLike(): Bool {
        return astKind == ASTKind.FUNC_DECL || astKind == ASTKind.LAMBDA_EXPR ||
            astKind == ASTKind.PRIMARY_CTOR_DECL || astKind == ASTKind.MACRO_DECL
    }

    public func IsFunc(): Bool {
        return astKind == ASTKind.FUNC_DECL
    }

    public func IsFuncOrProp(): Bool {
        return astKind == ASTKind.FUNC_DECL || astKind == ASTKind.PROP_DECL
    }

    public func IsDecl(): Bool {
        return ASTKindIndex(astKind) >= ASTKindIndex(ASTKind.DECL) &&
            ASTKindIndex(astKind) <= ASTKindIndex(ASTKind.INVALID_DECL)
    }

    public func IsExpr(): Bool {
        return ASTKindIndex(astKind) >= ASTKindIndex(ASTKind.EXPR) &&
            ASTKindIndex(astKind) <= ASTKindIndex(ASTKind.INVALID_EXPR)
    }

    public func IsInvalid(): Bool {
        return astKind == ASTKind.INVALID_DECL || astKind == ASTKind.INVALID_EXPR || astKind == ASTKind.INVALID_TYPE
    }

    public func IsLoopExpr(): Bool {
        return astKind == ASTKind.FOR_IN_EXPR || astKind == ASTKind.WHILE_EXPR || astKind == ASTKind.DO_WHILE_EXPR
    }

    public func IsStaticOrGlobal(): Bool {
        return TestAttr(Attribute.GLOBAL) || TestAttr(Attribute.STATIC)
    }

    public func IsTypeDecl(): Bool {
        return astKind == ASTKind.CLASS_DECL || astKind == ASTKind.INTERFACE_DECL ||
            astKind == ASTKind.STRUCT_DECL || astKind == ASTKind.ENUM_DECL || astKind == ASTKind.TYPE_ALIAS_DECL ||
            astKind == ASTKind.GENERIC_PARAM_DECL || astKind == ASTKind.BUILTIN_DECL
    }

    public func IsMacroCallNode(): Bool {
        return astKind == ASTKind.MACRO_EXPAND_DECL || astKind == ASTKind.MACRO_EXPAND_EXPR ||
            astKind == ASTKind.MACRO_EXPAND_PARAM
    }

    public open func IsOpen(): Bool {
        return false
    }

    public open func Children(): ArrayList<Node> {
        return ArrayList<Node>()
    }

    public func ShouldDiagnose(allowCompilerAdd!: Bool = false): Bool {
        if (!allowCompilerAdd && TestAttr(Attribute.COMPILER_ADD) && !TestAttr(Attribute.IS_CLONED_SOURCE_CODE)) {
            return false
        }
        if (allowCompilerAdd && TestAttr(Attribute.COMPILER_ADD) && begin.IsZero()) {
            return false
        }
        if (TestAttr(Attribute.MACRO_INVOKE_FUNC) || TestAttr(Attribute.MACRO_INVOKE_BODY)) {
            return false
        }
        if (let Some(exprNode) <- (this as Expr)) {
            if (let Some(_) <- exprNode.sourceExpr) {
                return false
            }
        }
        return true
    }

    public func IsSamePackage(other: Node): Bool {
        let otherFile = other.curFile
        if (let None <- curFile) {
            return true
        }
        if (let None <- otherFile) {
            return true
        }
        if (let Some(file) <- curFile) {
            if (let Some(rightFile) <- otherFile) {
                let curPackage = file.curPackage
                let otherPackage = rightFile.curPackage
                if (let None <- curPackage) {
                    return true
                }
                if (let None <- otherPackage) {
                    return true
                }
                if (let Some(leftPkg) <- curPackage) {
                    if (let Some(rightPkg) <- otherPackage) {
                        return refEq(leftPkg, rightPkg)
                    }
                }
            }
        }
        return true
    }

    public func GetTargets(): ArrayList<Decl> {
        let out = ArrayList<Decl>()
        if (let Some(refType) <- (this as RefType)) {
            for (target in refType.ref.targets) { out.add(target) }
        } else if (let Some(refExpr) <- (this as RefExpr)) {
            for (target in refExpr.ref.targets) { out.add(target) }
        } else if (let Some(member) <- (this as MemberAccess)) {
            for (target in member.targets) { out.add(target) }
        }
        return out
    }

    public func GetTarget(): Option<Decl> {
        if (let Some(refType) <- (this as RefType)) {
            return refType.ref.target
        }
        if (let Some(refExpr) <- (this as RefExpr)) {
            return refExpr.ref.target
        }
        if (let Some(qualified) <- (this as QualifiedType)) {
            return qualified.target
        }
        if (let Some(member) <- (this as MemberAccess)) {
            return member.target
        }
        if (let Some(expandDecl) <- (this as MacroExpandDecl)) {
            return expandDecl.invocation.target
        }
        if (let Some(expandExpr) <- (this as MacroExpandExpr)) {
            return expandExpr.invocation.target
        }
        if (let Some(expandParam) <- (this as MacroExpandParam)) {
            return expandParam.invocation.target
        }
        return None
    }

    public func SetTarget(target: Option<Decl>): Unit {
        if (let Some(refType) <- (this as RefType)) {
            refType.ref.target = target
        } else if (let Some(refExpr) <- (this as RefExpr)) {
            refExpr.ref.target = target
        } else if (let Some(qualified) <- (this as QualifiedType)) {
            qualified.target = target
        } else if (let Some(member) <- (this as MemberAccess)) {
            member.target = target
        } else if (let Some(expandDecl) <- (this as MacroExpandDecl)) {
            expandDecl.invocation.target = target
        } else if (let Some(expandExpr) <- (this as MacroExpandExpr)) {
            expandExpr.invocation.target = target
        } else if (let Some(expandParam) <- (this as MacroExpandParam)) {
            expandParam.invocation.target = target
        }
    }

    public func GetInvocation(): Option<MacroInvocation> {
        if (let Some(expandExpr) <- (this as MacroExpandExpr)) {
            return expandExpr.invocation
        }
        if (let Some(expandDecl) <- (this as MacroExpandDecl)) {
            return expandDecl.invocation
        }
        if (let Some(expandParam) <- (this as MacroExpandParam)) {
            return expandParam.invocation
        }
        return None
    }

    public func GetConstInvocation(): Option<MacroInvocation> {
        return GetInvocation()
    }

    public func GetMacroCallPos(originPos: Position, isLowerBound!: Bool = false): Position {
        if (let Some(macroCall) <- curMacroCall) {
            if (originPos.line != macroCall.begin.line) {
                return originPos
            }
            if (let Some(invocation) <- macroCall.GetConstInvocation()) {
                if (IsPureAnnotation(invocation)) {
                    return originPos
                }
                return invocation.macroCallDiagInfo.MapPos(originPos, isLowerBound: isLowerBound)
            }
        }
        if (let Some(invocation) <- GetConstInvocation()) {
            if (begin.fileID != originPos.fileID) {
                return originPos
            }
            return invocation.macroCallDiagInfo.MapPos(originPos, isLowerBound: isLowerBound)
        }
        return originPos
    }

    public func GetBegin(): Position {
        return GetMacroCallPos(begin)
    }

    public func GetEnd(): Position {
        let beginPos = GetMacroCallPos(begin)
        var endPos = GetMacroCallPos(end, isLowerBound: true)
        if (beginPos.fileID != endPos.fileID) {
            endPos = beginPos + 1
        }
        return endPos
    }

    public func GetMacroCallNewPos(originPos: Position): Position {
        var invocation: Option<MacroInvocation> = None
        if (isInMacroCall) {
            if (let Some(macroCall) <- curMacroCall) {
                invocation = GetOutermostMacroInvocation(macroCall)
            }
        }
        if (IsMacroCallNode()) {
            invocation = GetOutermostMacroInvocation(this)
        }
        if (let Some(value) <- invocation) {
            if (value.macroCallDiagInfo.originPosMap.size() == 0 || value.origin2newPosMap.isEmpty()) {
                return INVALID_POSITION
            }
            let key = originPos.Hash32()
            if (let Some(entry) <- value.macroCallDiagInfo.originPosMap.lowerBound(key)) {
                let newKey = entry[1].Hash64()
                if (let Some(pos) <- FindPositionByUInt64Key(value.origin2newPosMap, newKey)) {
                    return pos
                }
            }
        }
        return INVALID_POSITION
    }

    @OverflowWrapping
    public func GetDebugPos(curPos: Position): Position {
        var invocation = GetConstInvocation()
        if (let None <- invocation) {
            if (curPos == INVALID_POSITION) {
                return curPos
            }
            if (let Some(macroCall) <- curMacroCall) {
                invocation = macroCall.GetConstInvocation()
            } else {
                return curPos
            }
            if (let Some(value) <- invocation) {
                if (value.macroDebugMap.isEmpty()) {
                    return curPos
                }
            } else {
                return curPos
            }
        }
        if (let Some(value) <- invocation) {
            let key = UInt64(UInt32(curPos.column))
            if (let Some(pos) <- FindPositionByUInt64Key(value.macroDebugMap, key)) {
                return pos
            }
        }
        return curPos
    }

    public func GetFullPackageName(): String {
        if (let Some(decl) <- (this as Decl)) {
            if (!decl.fullPackageName.isEmpty()) {
                return decl.fullPackageName
            }
        }
        if (let Some(file) <- curFile) {
            if (let Some(pkg) <- file.curPackage) {
                return pkg.fullPackageName
            }
        }
        return ""
    }
}

public class Modifier <: Node {
    public var modifier: TokenKind = TokenKind.ILLEGAL
    public var isExplicit: Bool = false

    public init() {
        super(ASTKind.MODIFIER)
    }

    public init(kind: TokenKind, pos: Position) {
        super(ASTKind.MODIFIER)
        modifier = kind
        begin = pos
        end = Position(pos.fileID, pos.line, pos.column + Len(kind))
        isExplicit = true
    }

    public override func ToString(): String {
        return if (isExplicit) { TokenKindText(modifier) } else { "" }
    }

    public operator func <(right: Modifier): Bool {
        return TokenKindIndex(modifier) < TokenKindIndex(right.modifier)
    }
}

public enum AnnotationKind {
    | JAVA
    | CALLING_CONV
    | C
    | JAVA_MIRROR
    | JAVA_IMPL
    | JAVA_HAS_DEFAULT
    | OBJ_C_MIRROR
    | OBJ_C_IMPL
    | OBJ_C_INIT
    | OBJ_C_OPTIONAL
    | FOREIGN_NAME
    | FOREIGN_GETTER_NAME
    | FOREIGN_SETTER_NAME
    | ATTRIBUTE
    | NUMERIC_OVERFLOW
    | INTRINSIC
    | WHEN
    | FASTNATIVE
    | ANNOTATION
    | CUSTOM
    | CONSTSAFE
    | DEPRECATED
    | FROZEN
    | ENSURE_PREPARED_TO_MOCK
    | NON_PRODUCT
    | UNKNOWN
    | NO_HEAP_ALLOC
    | NO_WRITE_BARRIER_REC
    | NO_STACK_GROW
}

public func AnnotationKindIndex(kind: AnnotationKind): Int64 {
    return match (kind) {
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
}

extend AnnotationKind <: Equatable<AnnotationKind> {
    public operator func ==(right: AnnotationKind): Bool {
        return AnnotationKindIndex(this) == AnnotationKindIndex(right)
    }

    public operator func !=(right: AnnotationKind): Bool {
        return !(this == right)
    }
}

public enum AnnotationTarget {
    | TYPE
    | PARAMETER
    | INIT
    | MEMBER_PROPERTY
    | MEMBER_FUNCTION
    | MEMBER_VARIABLE
    | ENUM_CONSTRUCTOR
    | GLOBAL_FUNCTION
    | GLOBAL_VARIABLE
    | EXTEND
}

private func AnnotationTargetIndex(target: AnnotationTarget): Int64 {
    return match (target) {
        case AnnotationTarget.TYPE => 0
        case AnnotationTarget.PARAMETER => 1
        case AnnotationTarget.INIT => 2
        case AnnotationTarget.MEMBER_PROPERTY => 3
        case AnnotationTarget.MEMBER_FUNCTION => 4
        case AnnotationTarget.MEMBER_VARIABLE => 5
        case AnnotationTarget.ENUM_CONSTRUCTOR => 6
        case AnnotationTarget.GLOBAL_FUNCTION => 7
        case AnnotationTarget.GLOBAL_VARIABLE => 8
        case AnnotationTarget.EXTEND => 9
    }
}

private func AnnotationTargetMask(target: AnnotationTarget): UInt16 {
    var mask: UInt16 = 1u16
    for (_ in 0..AnnotationTargetIndex(target)) {
        mask = mask << 1
    }
    return mask
}

public class Annotation <: Node {
    public var isCompileTimeVisible: Bool = false
    public var kind: AnnotationKind = AnnotationKind.UNKNOWN
    public var identifier: Identifier = Identifier()
    public var lsquarePos: Position = INVALID_POSITION
    public let args: ArrayList<FuncArg> = ArrayList<FuncArg>()
    public var rsquarePos: Position = INVALID_POSITION
    public var overflowStrategy: OverflowStrategy = OverflowStrategy.NA
    public let attrs: ArrayList<Token> = ArrayList<Token>()
    public let attrCommas: ArrayList<Position> = ArrayList<Position>()
    public var definedPackage: String = ""
    public var condExpr: Option<Expr> = None
    public var target: UInt16 = 0u16
    public var runtimeVisible: Bool = false
    public var baseExpr: Option<Expr> = None

    public init() {
        super(ASTKind.ANNOTATION)
    }

    public init(name: String, annoKind: AnnotationKind, pos: Position) {
        super(ASTKind.ANNOTATION)
        kind = annoKind
        identifier = Identifier(name, INVALID_POSITION, INVALID_POSITION)
        begin = pos
    }

    public func TestTarget(target: AnnotationTarget): Bool {
        return (this.target & AnnotationTargetMask(target)) != 0u16
    }

    public func EnableTarget(target: AnnotationTarget): Unit {
        this.target = this.target | AnnotationTargetMask(target)
    }

    public func EnableAllTargets(): Unit {
        this.target = 0xffffu16
    }

    public operator func <(right: Annotation): Bool {
        return AnnotationKindIndex(kind) < AnnotationKindIndex(right.kind)
    }
}

public class Reference {
    public var identifier: SrcIdentifier = SrcIdentifier()
    public var target: Option<Decl> = None
    public let targets: ArrayList<Decl> = ArrayList<Decl>()

    public init() {}

    public init(id: SrcIdentifier) {
        identifier = id
    }

    public init(name: String) {
        identifier = SrcIdentifier(name, INVALID_POSITION, INVALID_POSITION, false)
    }
}
