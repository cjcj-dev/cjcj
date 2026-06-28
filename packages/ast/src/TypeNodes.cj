package cangjie_compiler::ast

import cangjie_compiler::utils.CJC_ASSERT
import cangjie_compiler::utils.CJC_NULLPTR_CHECK
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
        return "<invalid>"
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

    public init(id: SrcIdentifier) {
        super(ASTKind.REF_TYPE)
        ref = Reference(id)
        begin = id.Begin()
        end = id.End()
    }

    public init(name: String) {
        super(ASTKind.REF_TYPE)
        ref = Reference(name)
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
        if (let Some(target) <- ref.target) {
            if (let Some(classDecl) <- (target as ClassDecl)) {
                if (let Some(generic) <- classDecl.generic) {
                    if (!generic.typeParameters.isEmpty() && ref.identifier == "This") {
                        return true
                    }
                }
            }
        }
        return false
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (ty in typeArguments) { out.add(ty) }
        return out
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

    public init(name: String) {
        super(ASTKind.PRIMITIVE_TYPE)
        str = name
        kind = TypeKindFromName(name)
    }

    public init(kind: TypeKind) {
        super(ASTKind.PRIMITIVE_TYPE)
        this.kind = kind
        str = TypeKindName(kind)
    }

    public init(name: String, begin: Position, end: Position) {
        super(ASTKind.PRIMITIVE_TYPE)
        str = name
        kind = TypeKindFromName(name)
        this.begin = begin
        this.end = end
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

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(child) <- innerType) { out.add(child) }
        return out
    }

    public override func ToString(): String {
        CJC_ASSERT(innerType.isSome())
        return "(" + innerType.getOrThrow().ToString() + ")"
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

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(base) <- baseType) { out.add(base) }
        for (ty in typeArguments) { out.add(ty) }
        return out
    }

    public func GetFieldPos(): Position {
        return GetMacroCallPos(field.Begin())
    }

    public override func ToString(): String {
        CJC_ASSERT(baseType.isSome())
        var out = baseType.getOrThrow().ToString()
        out += "."
        out += field.GetRawText()
        if (!typeArguments.isEmpty()) {
            let parts = ArrayList<String>()
            for (arg in typeArguments) {
                parts.add(arg.ToString())
            }
            out += "<" + JoinStrings(parts, ", ") + ">"
        }
        return out
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

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(child) <- componentType) { out.add(child) }
        return out
    }

    public override func ToString(): String {
        var out = ""
        let count = if (questNum > 0u64) { questNum } else { UInt64(questVector.size) }
        var idx: UInt64 = 0u64
        while (idx < count) {
            out += "?"
            idx++
        }
        CJC_ASSERT(componentType.isSome())
        return out + componentType.getOrThrow().ToString()
    }
}

public class ConstantType <: Type {
    public var constantExpr: Option<Expr> = None
    public var dollarPos: Position = INVALID_POSITION

    public init() {
        super(ASTKind.CONSTANT_TYPE)
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(expr) <- constantExpr) { out.add(expr) }
        return out
    }

    public override func ToString(): String {
        CJC_ASSERT(constantExpr.isSome())
        return "$" + constantExpr.getOrThrow().ToString()
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

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(arg) <- typeArgument) { out.add(arg) }
        if (let Some(size) <- constantType) { out.add(size) }
        return out
    }

    public override func ToString(): String {
        CJC_ASSERT(typeArgument.isSome())
        var out = "VArray<" + typeArgument.getOrThrow().ToString()
        if (let Some(value) <- constantType) {
            out += ", " + value.ToString()
        }
        out += ">"
        return out
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

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (ty in paramTypes) { out.add(ty) }
        if (let Some(ret) <- retType) { out.add(ret) }
        return out
    }

    public override func ToString(): String {
        let parts = ArrayList<String>()
        for (param in paramTypes) {
            parts.add(param.ToString())
        }
        var out = "(" + JoinStrings(parts, ", ") + ")"
        if (let Some(value) <- retType) {
            out += " -> " + value.ToString()
        }
        return out
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

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (ty in fieldTypes) { out.add(ty) }
        return out
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

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(refTy) <- refType) { out.add(refTy) }
        for (bound in upperBounds) { out.add(bound) }
        return out
    }

    public override func ToString(): String {
        let bounds = ArrayList<String>()
        for (bound in upperBounds) {
            bounds.add(bound.ToString())
        }
        CJC_NULLPTR_CHECK(refType)
        let lhs = refType.getOrThrow().ToString()
        if (bounds.isEmpty()) {
            return lhs
        }
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

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (param in typeParameters) { out.add(param) }
        for (constraint in genericConstraints) { out.add(constraint) }
        return out
    }

    public override func ToString(): String {
        if (typeParameters.isEmpty()) {
            return ""
        }
        let params = ArrayList<String>()
        for (param in typeParameters) {
            params.add(param.identifier.Val())
        }
        return "<" + JoinStrings(params, ", ") + ">"
    }
}
