package cangjie_compiler::ast

import std.collection.*

public open class Type <: Node {
    public var commaPos: Position = INVALID_POSITION
    public var bitAndPos: Position = INVALID_POSITION
    public var colonPos: Position = INVALID_POSITION
    public var typePos: Position = INVALID_POSITION
    public var typeParameterName: String = ""
    public var typeParameterNameIsRawId: Bool = false
    public var aliasTy: Option<Ty> = Ty.GetInitialTy()

    public init() {
        super(ASTKind.TYPE)
    }

    public init(kind: ASTKind) {
        super(kind)
    }

    public open override func Clear(): Unit {
        super.Clear()
    }

    public open func GetTypeArgs(): ArrayList<Type> {
        return ArrayList<Type>()
    }

    public func GetTypeParameterNameRawText(): String {
        return if (typeParameterNameIsRawId) { "`" + typeParameterName + "`" } else { typeParameterName }
    }
}

public class InvalidType <: Type {
    public init(pos: Position) {
        super(ASTKind.INVALID_TYPE)
        EnableAttr(Attribute.IS_BROKEN)
        begin = pos
        end = pos
    }

    public override func ToString(): String {
        return "<invalid type>"
    }
}

public class RefType <: Type {
    public var ref: Reference = Reference()
    public var leftAnglePos: Position = INVALID_POSITION
    public let typeArguments: ArrayList<Type> = ArrayList<Type>()
    public var rightAnglePos: Position = INVALID_POSITION

    public init() {
        super(ASTKind.REF_TYPE)
    }

    public override func Clear(): Unit {
        super.Clear()
        ref.target = None
        ref.targets.clear()
    }

    public override func GetTypeArgs(): ArrayList<Type> {
        return typeArguments
    }

    public func IsGenericThisType(): Bool {
        if (ref.identifier != "This") {
            return false
        }
        if (let Some(_) <- ref.target) {
            return true
        }
        return false
    }

    public override func ToString(): String {
        if (typeArguments.isEmpty()) {
            return ref.identifier.Val()
        }
        let parts = ArrayList<String>()
        for (arg in typeArguments) {
            parts.add(arg.ToString())
        }
        return ref.identifier.Val() + "<" + JoinStrings(parts, ", ") + ">"
    }
}

public class ThisType <: Type {
    public init(pos: Position) {
        super(ASTKind.THIS_TYPE)
        begin = pos
        end = begin + Len(TokenKind.THISTYPE)
    }

    public override func ToString(): String {
        return "This"
    }
}

public class PrimitiveType <: Type {
    public var str: String = ""
    public var kind: TypeKind = TypeKind.TYPE_INVALID

    public init() {
        super(ASTKind.PRIMITIVE_TYPE)
    }

    public override func ToString(): String {
        return if (str.isEmpty()) { TypeKindName(kind) } else { str }
    }
}

public class ParenType <: Type {
    public var leftParenPos: Position = INVALID_POSITION
    public var innerType: Option<Type> = None
    public var rightParenPos: Position = INVALID_POSITION

    public init() {
        super(ASTKind.PAREN_TYPE)
    }

    public override func ToString(): String {
        return "(" + (if (let Some(value) <- innerType) { value.ToString() } else { "" }) + ")"
    }
}

public class QualifiedType <: Type {
    public var baseType: Option<Type> = None
    public var dotPos: Position = INVALID_POSITION
    public var field: SrcIdentifier = SrcIdentifier()
    public var leftAnglePos: Position = INVALID_POSITION
    public let typeArguments: ArrayList<Type> = ArrayList<Type>()
    public var rightAnglePos: Position = INVALID_POSITION
    public var target: Option<Decl> = None

    public init() {
        super(ASTKind.QUALIFIED_TYPE)
    }

    public override func Clear(): Unit {
        super.Clear()
        target = None
    }

    public override func GetTypeArgs(): ArrayList<Type> {
        return typeArguments
    }

    public func GetFieldPos(): Position {
        return GetMacroCallPos(field.Begin())
    }

    public override func ToString(): String {
        let base = if (let Some(value) <- baseType) { value.ToString() + "." } else { "" }
        return base + field.GetRawText()
    }
}

public class OptionType <: Type {
    public var componentType: Option<Type> = None
    public var questNum: UInt64 = 0
    public let questVector: ArrayList<Position> = ArrayList<Position>()
    public var desugarType: Option<RefType> = None

    public init() {
        super(ASTKind.OPTION_TYPE)
    }

    public override func ToString(): String {
        let component = if (let Some(value) <- componentType) { value.ToString() } else { "" }
        return "?" + component
    }
}

public class ConstantType <: Type {
    public var constantExpr: Option<Expr> = None
    public var dollarPos: Position = INVALID_POSITION

    public init() {
        super(ASTKind.CONSTANT_TYPE)
    }

    public override func ToString(): String {
        return "$" + (if (let Some(value) <- constantExpr) { value.ToString() } else { "" })
    }
}

public class VArrayType <: Type {
    public var varrayPos: Position = INVALID_POSITION
    public var leftAnglePos: Position = INVALID_POSITION
    public var typeArgument: Option<Type> = None
    public var constantType: Option<Type> = None
    public var rightAnglePos: Position = INVALID_POSITION

    public init() {
        super(ASTKind.VARRAY_TYPE)
    }

    public override func ToString(): String {
        let elem = if (let Some(value) <- typeArgument) { value.ToString() } else { "" }
        let size = if (let Some(value) <- constantType) { value.ToString() } else { "" }
        return "VArray<${elem}, ${size}>"
    }
}

public class FuncType <: Type {
    public var leftParenPos: Position = INVALID_POSITION
    public let paramTypes: ArrayList<Type> = ArrayList<Type>()
    public var rightParenPos: Position = INVALID_POSITION
    public var arrowPos: Position = INVALID_POSITION
    public var retType: Option<Type> = None
    public var isC: Bool = false

    public init() {
        super(ASTKind.FUNC_TYPE)
    }

    public override func ToString(): String {
        let parts = ArrayList<String>()
        for (param in paramTypes) {
            parts.add(param.ToString())
        }
        let ret = if (let Some(value) <- retType) { value.ToString() } else { "Unit" }
        return "(" + JoinStrings(parts, ", ") + ") -> " + ret
    }
}

public class TupleType <: Type {
    public var leftParenPos: Position = INVALID_POSITION
    public var rightParenPos: Position = INVALID_POSITION
    public let fieldTypes: ArrayList<Type> = ArrayList<Type>()
    public let commaPosVector: ArrayList<Position> = ArrayList<Position>()

    public init() {
        super(ASTKind.TUPLE_TYPE)
    }

    public override func ToString(): String {
        let parts = ArrayList<String>()
        for (field in fieldTypes) {
            parts.add(field.ToString())
        }
        return "(" + JoinStrings(parts, ", ") + ")"
    }
}

public enum InheritanceVisitStatus {
    | UNVISITED
    | VISITING
    | VISITED
}

public class GenericConstraint <: Node {
    public var wherePos: Position = INVALID_POSITION
    public var refType: Option<RefType> = None
    public var operatorPos: Position = INVALID_POSITION
    public let bitAndPos: ArrayList<Position> = ArrayList<Position>()
    public let upperBounds: ArrayList<Type> = ArrayList<Type>()
    public var commaPos: Position = INVALID_POSITION
    public var isImplicitlyIntroduced: Bool = false

    public init() {
        super(ASTKind.GENERIC_CONSTRAINT)
    }

    public override func ToString(): String {
        let bounds = ArrayList<String>()
        for (bound in upperBounds) {
            bounds.add(bound.ToString())
        }
        let lhs = if (let Some(value) <- refType) { value.ToString() } else { "" }
        return lhs + " <: " + JoinStrings(bounds, " & ")
    }
}

public class Generic <: Node {
    public var leftAnglePos: Position = INVALID_POSITION
    public let typeParameters: ArrayList<GenericParamDecl> = ArrayList<GenericParamDecl>()
    public var rightAnglePos: Position = INVALID_POSITION
    public let genericConstraints: ArrayList<GenericConstraint> = ArrayList<GenericConstraint>()

    public init() {
        super(ASTKind.GENERIC)
    }

    public override func ToString(): String {
        let params = ArrayList<String>()
        for (param in typeParameters) {
            params.add(param.identifier.Val())
        }
        return "<" + JoinStrings(params, ", ") + ">"
    }
}
