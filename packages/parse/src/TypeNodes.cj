package cangjie_compiler::parse

import std.collection.*

public open class Type <: Node {
    public init() { super(ASTKind.TYPE) }
    public init(kind: ASTKind) { super(kind) }
}

public class InvalidType <: Type {
    public init(pos: Position) {
        super(ASTKind.INVALID_TYPE)
        begin = pos
        end = pos
        isBroken = true
    }
}

public class PrimitiveType <: Type {
    public var name: String = ""
    public var tokenKind: TokenKind = TokenKind.ILLEGAL

    public init(name: String, tokenKind: TokenKind, begin: Position, end: Position) {
        super(ASTKind.PRIMITIVE_TYPE)
        this.name = name
        this.tokenKind = tokenKind
        this.begin = begin
        this.end = end
    }

    public override func ToString(): String { return name }
}

public class RefType <: Type {
    public var identifier: SrcIdentifier = SrcIdentifier()
    public let typeArguments: ArrayList<Type> = ArrayList<Type>()
    public var leftAnglePos: Position = INVALID_POSITION
    public var rightAnglePos: Position = INVALID_POSITION

    public init() { super(ASTKind.REF_TYPE) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (ty in typeArguments) { out.add(ty) }
        return out
    }

    public override func ToString(): String {
        if (typeArguments.isEmpty()) {
            return identifier.GetRawText()
        }
        let parts = ArrayList<String>()
        for (ty in typeArguments) { parts.add(ty.ToString()) }
        return identifier.GetRawText() + "<" + JoinStrings(parts, ", ") + ">"
    }
}

public class QualifiedType <: Type {
    public var baseType: Option<Type> = None
    public var dotPos: Position = INVALID_POSITION
    public var field: SrcIdentifier = SrcIdentifier()
    public let typeArguments: ArrayList<Type> = ArrayList<Type>()

    public init() { super(ASTKind.QUALIFIED_TYPE) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(base) <- baseType) { out.add(base) }
        for (ty in typeArguments) { out.add(ty) }
        return out
    }

    public override func ToString(): String {
        let prefix = if (let Some(base) <- baseType) { base.ToString() + "." } else { "" }
        return prefix + field.GetRawText()
    }
}

public class OptionType <: Type {
    public var componentType: Option<Type> = None
    public let questVector: ArrayList<Position> = ArrayList<Position>()

    public init() { super(ASTKind.OPTION_TYPE) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(child) <- componentType) { out.add(child) }
        return out
    }
}

public class ConstantType <: Type {
    public var dollarPos: Position = INVALID_POSITION
    public var constantExpr: Option<Expr> = None

    public init() { super(ASTKind.CONSTANT_TYPE) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(expr) <- constantExpr) { out.add(expr) }
        return out
    }
}

public class VArrayType <: Type {
    public var varrayPos: Position = INVALID_POSITION
    public var leftAnglePos: Position = INVALID_POSITION
    public var typeArgument: Option<Type> = None
    public var constantType: Option<Type> = None
    public var rightAnglePos: Position = INVALID_POSITION

    public init() { super(ASTKind.VARRAY_TYPE) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(arg) <- typeArgument) { out.add(arg) }
        if (let Some(size) <- constantType) { out.add(size) }
        return out
    }
}

public class ParenType <: Type {
    public var innerType: Option<Type> = None
    public var leftParenPos: Position = INVALID_POSITION
    public var rightParenPos: Position = INVALID_POSITION

    public init() { super(ASTKind.PAREN_TYPE) }
}

public class TupleType <: Type {
    public let fieldTypes: ArrayList<Type> = ArrayList<Type>()
    public let commaPosVector: ArrayList<Position> = ArrayList<Position>()
    public var leftParenPos: Position = INVALID_POSITION
    public var rightParenPos: Position = INVALID_POSITION

    public init() { super(ASTKind.TUPLE_TYPE) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (ty in fieldTypes) { out.add(ty) }
        return out
    }
}

public class FuncType <: Type {
    public let paramTypes: ArrayList<Type> = ArrayList<Type>()
    public var retType: Option<Type> = None
    public var arrowPos: Position = INVALID_POSITION
    public var leftParenPos: Position = INVALID_POSITION
    public var rightParenPos: Position = INVALID_POSITION
    public var isC: Bool = false

    public init() { super(ASTKind.FUNC_TYPE) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (ty in paramTypes) { out.add(ty) }
        if (let Some(ret) <- retType) { out.add(ret) }
        return out
    }
}

public class ThisType <: Type {
    public init(pos: Position) {
        super(ASTKind.THIS_TYPE)
        begin = pos
        end = pos + 4
    }
}

public class Generic <: Node {
    public let typeParameters: ArrayList<GenericParamDecl> = ArrayList<GenericParamDecl>()
    public var leftAnglePos: Position = INVALID_POSITION
    public var rightAnglePos: Position = INVALID_POSITION

    public init() { super(ASTKind.GENERIC) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (param in typeParameters) { out.add(param) }
        return out
    }
}

public class GenericConstraint <: Node {
    public var wherePos: Position = INVALID_POSITION
    public var refType: Option<RefType> = None
    public let upperBounds: ArrayList<Type> = ArrayList<Type>()

    public init() { super(ASTKind.GENERIC_CONSTRAINT) }
}
