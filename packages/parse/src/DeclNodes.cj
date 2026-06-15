package cangjie_compiler::parse

import std.collection.*

public open class Decl <: Node {
    public let modifiers: ArrayList<Modifier> = ArrayList<Modifier>()
    public let annotations: ArrayList<Annotation> = ArrayList<Annotation>()
    public var identifier: SrcIdentifier = SrcIdentifier()
    public var keywordPos: Position = INVALID_POSITION
    public var generic: Option<Generic> = None
    public let genericConstraints: ArrayList<GenericConstraint> = ArrayList<GenericConstraint>()

    public init() { super(ASTKind.DECL) }
    public init(kind: ASTKind) { super(kind) }

    public func AddCommon(mods: ArrayList<Modifier>, annos: ArrayList<Annotation>): Unit {
        for (modifier in mods) { modifiers.add(modifier) }
        for (anno in annos) { annotations.add(anno) }
    }
}

public class InvalidDecl <: Decl {
    public init(pos: Position) {
        super(ASTKind.INVALID_DECL)
        begin = pos
        end = pos
        isBroken = true
    }
}

public class GenericParamDecl <: Decl {
    public init() { super(ASTKind.GENERIC_PARAM_DECL) }
}

public class FuncParam <: Decl {
    public var typeNode: Option<Type> = None
    public var colonPos: Position = INVALID_POSITION
    public var assignment: Option<Expr> = None
    public var assignPos: Position = INVALID_POSITION
    public var isMemberParam: Bool = false
    public var isNamedParam: Bool = false
    public var isVariadic: Bool = false

    public init() { super(ASTKind.FUNC_PARAM) }
}

public class FuncParamList <: Node {
    public let params: ArrayList<FuncParam> = ArrayList<FuncParam>()
    public var leftParenPos: Position = INVALID_POSITION
    public var rightParenPos: Position = INVALID_POSITION

    public init() { super(ASTKind.FUNC_PARAM_LIST) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (param in params) { out.add(param) }
        return out
    }
}

public class FuncBody <: Node {
    public var paramLists: ArrayList<FuncParamList> = ArrayList<FuncParamList>()
    public var retType: Option<Type> = None
    public var colonPos: Position = INVALID_POSITION
    public var arrowPos: Position = INVALID_POSITION
    public var body: Option<Block> = None
    public var generic: Option<Generic> = None
    public let genericConstraints: ArrayList<GenericConstraint> = ArrayList<GenericConstraint>()

    public init() { super(ASTKind.FUNC_BODY) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (paramList in paramLists) { out.add(paramList) }
        if (let Some(ret) <- retType) { out.add(ret) }
        if (let Some(block) <- body) { out.add(block) }
        return out
    }
}

public open class FuncDecl <: Decl {
    public var funcBody: Option<FuncBody> = None
    public var isConst: Bool = false
    public var isOperator: Bool = false

    public init() { super(ASTKind.FUNC_DECL) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(body) <- funcBody) { out.add(body) }
        return out
    }
}

public class MainDecl <: FuncDecl {
    public init() {
        super()
    }
}

public class MacroDecl <: FuncDecl {
    public init() {
        super()
    }
}

public open class VarDeclAbstract <: Decl {
    public var typeNode: Option<Type> = None
    public var colonPos: Position = INVALID_POSITION
    public var initializer: Option<Expr> = None
    public var assignPos: Position = INVALID_POSITION
    public var isVar: Bool = false
    public var isConst: Bool = false

    public init(kind: ASTKind) { super(kind) }
}

public class VarDecl <: VarDeclAbstract {
    public init() { super(ASTKind.VAR_DECL) }
}

public class VarWithPatternDecl <: Decl {
    public var pattern: Option<Pattern> = None
    public var typeNode: Option<Type> = None
    public var initializer: Option<Expr> = None
    public var isVar: Bool = false
    public var isConst: Bool = false

    public init() { super(ASTKind.VAR_WITH_PATTERN_DECL) }
}

public open class InheritableDecl <: Decl {
    public let inheritedTypes: ArrayList<Type> = ArrayList<Type>()
    public var bodyDecls: ArrayList<Decl> = ArrayList<Decl>()

    public init(kind: ASTKind) { super(kind) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (ty in inheritedTypes) { out.add(ty) }
        for (decl in bodyDecls) { out.add(decl) }
        return out
    }
}

public class ClassDecl <: InheritableDecl {
    public init() { super(ASTKind.CLASS_DECL) }
}

public class InterfaceDecl <: InheritableDecl {
    public init() { super(ASTKind.INTERFACE_DECL) }
}

public class StructDecl <: InheritableDecl {
    public init() { super(ASTKind.STRUCT_DECL) }
}

public class EnumDecl <: InheritableDecl {
    public let constructors: ArrayList<Decl> = ArrayList<Decl>()
    public init() { super(ASTKind.ENUM_DECL) }
}

public class ExtendDecl <: InheritableDecl {
    public var extendedType: Option<Type> = None
    public init() { super(ASTKind.EXTEND_DECL) }
}

public class TypeAliasDecl <: Decl {
    public var typeNode: Option<Type> = None
    public var assignPos: Position = INVALID_POSITION
    public init() { super(ASTKind.TYPE_ALIAS_DECL) }
}

public class PropDecl <: Decl {
    public var typeNode: Option<Type> = None
    public var initializer: Option<Expr> = None
    public var getter: Option<FuncDecl> = None
    public var setter: Option<FuncDecl> = None
    public init() { super(ASTKind.PROP_DECL) }
}

public class PrimaryCtorDecl <: FuncDecl {
    public init() {
        super()
    }
}

public class MacroInvocation {
    public var identifier: SrcIdentifier = SrcIdentifier()
    public let attrs: ArrayList<Token> = ArrayList<Token>()
    public let tokens: ArrayList<Token> = ArrayList<Token>()
    public init() {}
}

public class MacroExpandDecl <: Decl {
    public var invocation: MacroInvocation = MacroInvocation()
    public init() { super(ASTKind.MACRO_EXPAND_DECL) }
}
