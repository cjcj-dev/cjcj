package cangjie_compiler::parse

import std.collection.*
import cangjie_compiler::ast.AnnotationKind as AstAnnotationKind
public import cangjie_compiler::ast.{ASTKind, ASTKindIndex, Attribute, AttributeIndex}

public type AnnotationKind = AstAnnotationKind

public open class Node {
    public var begin: Position = INVALID_POSITION
    public var end: Position = INVALID_POSITION
    public var curMacroCall: Option<Node> = None
    public var curFile: Option<File> = None
    public let astKind: ASTKind
    public var isBroken: Bool = false

    public init() {
        astKind = ASTKind.NODE
    }

    public init(kind: ASTKind) {
        astKind = kind
    }

    public open func Children(): ArrayList<Node> {
        return ArrayList<Node>()
    }

    public open func ToString(): String {
        return ""
    }
}

public class SrcIdentifier {
    public var value: String = ""
    public var rawValue: String = ""
    public var begin: Position = INVALID_POSITION
    public var end: Position = INVALID_POSITION
    public var isRaw: Bool = false

    public init() {}

    public init(value: String, rawValue: String, begin: Position, end: Position, isRaw: Bool) {
        this.value = value
        this.rawValue = rawValue
        this.begin = begin
        this.end = end
        this.isRaw = isRaw
    }

    public func Empty(): Bool {
        return value.isEmpty()
    }

    public func Begin(): Position {
        return begin
    }

    public func End(): Position {
        return end
    }

    public func Val(): String {
        return value
    }

    public func GetRawText(): String {
        return if (rawValue.isEmpty()) { value } else { rawValue }
    }
}

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
    public var kind: AnnotationKind = AnnotationKind.CUSTOM
    public var identifier: SrcIdentifier = SrcIdentifier()
    public let args: ArrayList<FuncArg> = ArrayList<FuncArg>()
    public var atPos: Position = INVALID_POSITION
    public var leftParenPos: Position = INVALID_POSITION
    public var rightParenPos: Position = INVALID_POSITION

    public init() {
        super(ASTKind.ANNOTATION)
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (arg in args) { out.add(arg) }
        return out
    }
}
