package cangjie_compiler::parse

import std.collection.*
import cangjie_compiler::ast.AnnotationKind as AstAnnotationKind
public import cangjie_compiler::ast.{ASTKind, ASTKindIndex, Attribute, AttributeIndex, AttributePack}
public import cangjie_compiler::ast.{
    ConstantType, FuncType, Generic, GenericConstraint, GenericParamDecl, Identifier, InvalidType, Node, OptionType,
    ParenType, PrimitiveType, QualifiedType, RefType, SrcIdentifier, ThisType, TupleType, Type, VArrayType
}
public import cangjie_compiler::utils.OverflowStrategy

public type AnnotationKind = AstAnnotationKind

public enum ModifierKind {
    | PUBLIC | PROTECTED | INTERNAL | PRIVATE | STATIC | ABSTRACT | OPEN | SEALED | OVERRIDE
    | REDEF | FOREIGN | INOUT | MUT | UNSAFE | OPERATOR | CONST | COMMON | SPECIFIC
}

private func ModifierKindIndex(kind: ModifierKind): Int64 {
    return match (kind) {
        case ModifierKind.PUBLIC => 0
        case ModifierKind.PROTECTED => 1
        case ModifierKind.INTERNAL => 2
        case ModifierKind.PRIVATE => 3
        case ModifierKind.STATIC => 4
        case ModifierKind.ABSTRACT => 5
        case ModifierKind.OPEN => 6
        case ModifierKind.SEALED => 7
        case ModifierKind.OVERRIDE => 8
        case ModifierKind.REDEF => 9
        case ModifierKind.FOREIGN => 10
        case ModifierKind.INOUT => 11
        case ModifierKind.MUT => 12
        case ModifierKind.UNSAFE => 13
        case ModifierKind.OPERATOR => 14
        case ModifierKind.CONST => 15
        case ModifierKind.COMMON => 16
        case ModifierKind.SPECIFIC => 17
    }
}

extend ModifierKind <: Equatable<ModifierKind> {
    public operator func ==(right: ModifierKind): Bool { return ModifierKindIndex(this) == ModifierKindIndex(right) }
    public operator func !=(right: ModifierKind): Bool { return !(this == right) }
}

public class Modifier <: Node {
    public var kind: ModifierKind
    public var tokenKind: TokenKind

    public init(kind: ModifierKind, tokenKind: TokenKind, begin: Position, end: Position) {
        super(ASTKind.MODIFIER)
        this.kind = kind
        this.tokenKind = tokenKind
        this.begin = begin
        this.end = end
    }
}

public class Annotation <: Node {
    public var isCompileTimeVisible: Bool = false
    public var kind: AnnotationKind = AnnotationKind.CUSTOM
    public var identifier: SrcIdentifier = SrcIdentifier()
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
    public var atPos: Position = INVALID_POSITION

    public init() {
        super(ASTKind.ANNOTATION)
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (arg in args) { out.add(arg) }
        if (let Some(cond) <- condExpr) { out.add(cond) }
        if (let Some(base) <- baseExpr) { out.add(base) }
        return out
    }
}
