package cjcj::mangle

import std.collection.*
import std.sort.*
import cjcj::ast.*
import cjcj::lex.TokenKind

public let MANGLE_PAREN_PREFIX: String = "P"
public let MANGLE_OPTION_PREFIX: String = "O"
public let MANGLE_AST_CFUNC_PREFIX: String = "CF"
public let MANGLE_AST_FUNC_PREFIX: String = "F"
public let MANGLE_QUALIFIED_PREFIX: String = "Q"
public let MANGLE_INITIAL_PREFIX: String = "INITIAL"
public let MANGLE_EXIG_PREFIX: String = "Extend!"
public let MANGLE_THIS_PREFIX: String = "H"
public let MANGLE_PUBLIC_PREFIX: String = "P"
public let MANGLE_PROTECTED_PREFIX: String = "R"
public let MANGLE_PRIVATE_PREFIX: String = "I"
public let MANGLE_DIDOLLAR_PREFIX: String = "$$"
public let MANGLE_VARIABLE_PREFIX: String = "V"
public let MANGLE_LET_PREFIX: String = "L"
public let MANGLE_INOUT_PREFIX: String = "$IO"
public let MANGLE_GEXTEND_PREFIX: String = "W"

private func MangleBuiltinTypeImpl(typeName: String): Option<String> {
    return match (typeName) {
        case "Nothing" => "n"
        case "Unit" => "u"
        case "Rune" => "c"
        case "Bool" => "b"
        case "Float16" => "Dh"
        case "Float32" => "f"
        case "Float64" => "d"
        case "Int8" => "a"
        case "Int16" => "s"
        case "Int32" => "i"
        case "Int64" => "l"
        case "IntNative" => "q"
        case "UInt8" => "h"
        case "UInt16" => "t"
        case "UInt32" => "j"
        case "UInt64" => "m"
        case "UIntNative" => "r"
        case "CString" => "CString"
        case "CFunc" => "CFunc"
        case "CPointer" => "CPointer"
        case _ => None
    }
}

private func MangleRefTypeAnnotation(typeNode: Type): String {
    let typeAnnotation = (typeNode as RefType).getOrThrow()
    var mangledName = MangleName(typeAnnotation.ref.identifier.Val())
    if (!typeAnnotation.typeArguments.isEmpty()) {
        mangledName += MANGLE_LT_PREFIX
        for (arg in typeAnnotation.typeArguments) {
            mangledName += MangleAstType(arg)
        }
        mangledName += MANGLE_GT_PREFIX
    }
    return mangledName
}

private func MangleParenTypeAnnotation(typeNode: Type): String {
    let typeAnnotation = (typeNode as ParenType).getOrThrow()
    var mangledName = MANGLE_PAREN_PREFIX + MANGLE_WILDCARD_PREFIX
    if (let Some(inner) <- typeAnnotation.innerType) {
        mangledName += MangleAstType(inner)
    } else {
        throw IllegalArgumentException("Parenthesized type annotation has no inner type.")
    }
    return mangledName
}

private func MangleOptionTypeAnnotation(typeNode: Type): String {
    let typeAnnotation = (typeNode as OptionType).getOrThrow()
    var mangledName = MANGLE_OPTION_PREFIX + "${typeAnnotation.questNum}" + MANGLE_WILDCARD_PREFIX
    if (let Some(component) <- typeAnnotation.componentType) {
        mangledName += MangleAstType(component)
    } else {
        throw IllegalArgumentException("Option type annotation has no component type.")
    }
    return mangledName
}

private func MangleFuncTypeAnnotation(typeNode: Type): String {
    let typeAnnotation = (typeNode as FuncType).getOrThrow()
    var mangledName = if (typeAnnotation.isC) { MANGLE_AST_CFUNC_PREFIX } else { MANGLE_AST_FUNC_PREFIX }
    if (let Some(ret) <- typeAnnotation.retType) {
        mangledName += MangleAstType(ret)
    } else {
        throw IllegalArgumentException("Function type annotation has no return type.")
    }
    for (param in typeAnnotation.paramTypes) {
        mangledName += MangleAstType(param)
    }
    return mangledName
}

private func MangleConstantTypeAnnotation(typeNode: Type): String {
    let typeAnnotation = (typeNode as ConstantType).getOrThrow()
    return MANGLE_DOLLAR_PREFIX + (typeAnnotation.constantExpr.getOrThrow() as LitConstExpr).getOrThrow().stringValue
}

private func MangleVArrayTypeAnnotation(typeNode: Type): String {
    let typeAnnotation = (typeNode as VArrayType).getOrThrow()
    var mangledName = MANGLE_VARRAY_PREFIX + MANGLE_WILDCARD_PREFIX
    if (let Some(typeArg) <- typeAnnotation.typeArgument) {
        mangledName += MangleAstType(typeArg)
    } else {
        throw IllegalArgumentException("VArray type annotation has no element type.")
    }
    if (let Some(constantType) <- typeAnnotation.constantType) {
        mangledName += MangleAstType(constantType)
    } else {
        throw IllegalArgumentException("VArray type annotation has no constant size type.")
    }
    return mangledName
}

private func MangleTupleTypeAnnotation(typeNode: Type): String {
    let typeAnnotation = (typeNode as TupleType).getOrThrow()
    var mangledName = MANGLE_TUPLE_PREFIX + "${typeAnnotation.fieldTypes.size}" + MANGLE_WILDCARD_PREFIX
    for (field in typeAnnotation.fieldTypes) {
        mangledName += MangleAstType(field)
    }
    return mangledName
}

private func MangleQualifiedTypeAnnotation(typeNode: Type): String {
    let typeAnnotation = (typeNode as QualifiedType).getOrThrow()
    var mangledName = MANGLE_QUALIFIED_PREFIX
    if (let Some(baseType) <- typeAnnotation.baseType) {
        mangledName += MangleAstType(baseType)
    } else {
        throw IllegalArgumentException("Qualified type annotation has no base type.")
    }
    mangledName += MANGLE_DOT_PREFIX + MangleName(typeAnnotation.field.Val())
    if (!typeAnnotation.typeArguments.isEmpty()) {
        mangledName += MANGLE_LT_PREFIX
        for (arg in typeAnnotation.typeArguments) {
            mangledName += MangleAstType(arg)
        }
        mangledName += MANGLE_GT_PREFIX
    }
    return mangledName
}

public func MangleAstType(typeAnnotation: Type): String {
    return match (typeAnnotation.astKind) {
        case ASTKind.PRIMITIVE_TYPE => ASTMangler.ManglePrimitiveType(typeAnnotation)
        case ASTKind.REF_TYPE => MangleRefTypeAnnotation(typeAnnotation)
        case ASTKind.PAREN_TYPE => MangleParenTypeAnnotation(typeAnnotation)
        case ASTKind.OPTION_TYPE => MangleOptionTypeAnnotation(typeAnnotation)
        case ASTKind.CONSTANT_TYPE => MangleConstantTypeAnnotation(typeAnnotation)
        case ASTKind.VARRAY_TYPE => MangleVArrayTypeAnnotation(typeAnnotation)
        case ASTKind.FUNC_TYPE => MangleFuncTypeAnnotation(typeAnnotation)
        case ASTKind.TUPLE_TYPE => MangleTupleTypeAnnotation(typeAnnotation)
        case ASTKind.QUALIFIED_TYPE => MangleQualifiedTypeAnnotation(typeAnnotation)
        case ASTKind.THIS_TYPE => MANGLE_THIS_PREFIX
        case _ => throw IllegalArgumentException("Unexpected type annotation for AST mangling: " +
            ASTKindName(typeAnnotation.astKind))
    }
}

private func MangleAccessibility(decl: Decl): String {
    var res = ""
    for (mod in decl.modifiers) {
        match (mod.modifier) {
            case TokenKind.PUBLIC => res += MANGLE_PUBLIC_PREFIX
            case TokenKind.PROTECTED => res += MANGLE_PROTECTED_PREFIX
            case TokenKind.PRIVATE => res += MANGLE_PRIVATE_PREFIX
            case _ => ()
        }
    }
    return res
}

private func MangleDeclAstKind(kind: ASTKind): String {
    return match (kind) {
        case ASTKind.FUNC_DECL => "F"
        case ASTKind.MACRO_DECL => "M"
        case ASTKind.CLASS_DECL => "C"
        case ASTKind.INTERFACE_DECL => "I"
        case ASTKind.EXTEND_DECL => "X"
        case ASTKind.ENUM_DECL => "U"
        case ASTKind.STRUCT_DECL => "S"
        case ASTKind.TYPE_ALIAS_DECL => "T"
        case ASTKind.PRIMARY_CTOR_DECL => "Y"
        case ASTKind.VAR_DECL => "V"
        case ASTKind.PROP_DECL => "P"
        case _ => ""
    }
}

private func sortedStrings(values: ArrayList<String>): ArrayList<String> {
    let out = ArrayList<String>()
    for (value in values) {
        out.add(value)
    }
    sort(out, by: { left: String, right: String =>
        if (left < right) {
            Ordering.LT
        } else if (left > right) {
            Ordering.GT
        } else {
            Ordering.EQ
        }
    }, stable: true)
    return out
}

// Direct AST implementation: upstream src/Mangle/ASTMangler.cpp:245-552.
private class ASTManglerImpl {
    private let fullPackageName: String
    private var mangled: String = ""
    private let wildcardMap: HashMap<String, Int64> = HashMap<String, Int64>()

    public init(fullPackageName: String) {
        this.fullPackageName = fullPackageName
    }

    public func Mangle(decl: Decl): String {
        if (let Some(vp) <- (decl as VarWithPatternDecl)) {
            MangleVarWithPatternDecl(vp)
        } else if (let Some(ed) <- (decl as ExtendDecl)) {
            MangleExtendDecl(ed)
        } else {
            MangleDeclCommon(decl)
        }
        // C++ moves the result out of Impl; String is a value in Cangjie.
        let result = mangled
        mangled = ""
        return result
    }

    private func MangleFullPackageName(decl: Decl): String {
        let ret = MangleName(fullPackageName)
        if (decl.TestAttr(Attribute.GLOBAL) && decl.TestAttr(Attribute.PRIVATE)) {
            return ret + MangleFilePrivate(decl)
        }
        return ret
    }

    private func MangleFuncParameters(params: ArrayList<FuncParam>): Unit {
        for (param in params) {
            if (let Some(ty) <- param.typeNode) { mangled += MangleAstType(ty) }
            if (param.isMemberParam || param.isNamedParam) { mangled += "!" }
            if (param.isMemberParam && param.hasLetOrVar) {
                mangled += MangleAccessibility(param)
                mangled += if (param.isVar) { MANGLE_VARIABLE_PREFIX } else { MANGLE_LET_PREFIX }
            }
            if (param.isMemberParam || param.isNamedParam) {
                mangled += MangleName(param.identifier.Val())
                if (param.assignment.isSome()) { mangled += "=" }
            }
        }
    }

    private func MangleDeclCommon(decl: Decl): Unit {
        mangled += MangleFullPackageName(decl)
        MangleExtendLiteralIfInExtend(decl)
        MangleNestedDecl(decl)
        let useInternalIdent = decl.TestAnyAttr(Attribute.CONSTRUCTOR, Attribute.MAIN_ENTRY) &&
            decl.astKind != ASTKind.PRIMARY_CTOR_DECL
        mangled += MangleName(if (useInternalIdent) {
            MANGLE_LT_PREFIX + decl.identifier.Val() + MANGLE_GT_PREFIX
        } else { decl.identifier.Val() })
        MangleGenericArguments(decl)
        mangled += MangleDeclAstKind(decl.astKind)
        MangleOthers(decl)
    }

    private func MangleOthers(decl: Decl): Unit {
        if (decl.astKind == ASTKind.VAR_DECL || IsMemberParam(decl)) {
            mangled += MANGLE_DIDOLLAR_PREFIX
            if (let Some(ty) <- (decl as VarDecl).getOrThrow().typeNode) {
                mangled += MangleAstType(ty)
            }
        }
        if (let Some(md) <- (decl as MainDecl)) {
            let body = md.funcBody.getOrThrow()
            MangleFuncParameters(body.paramLists[0].params)
            if (let Some(ty) <- body.retType) { mangled += MangleAstType(ty) }
        }
        if (let Some(fd) <- (decl as FuncDecl)) {
            let body = fd.funcBody.getOrThrow()
            MangleFuncParameters(body.paramLists[0].params)
            if (fd.TestAttr(Attribute.CONSTRUCTOR) && fd.TestAttr(Attribute.STATIC)) {
                let initNameAndEnd: Int64 = 8
                mangled = mangled[0..mangled.size - initNameAndEnd] + MangleName("<clinit>")
            }
            mangled += MANGLE_DIDOLLAR_PREFIX
            if (let Some(ty) <- body.retType) {
                mangled += MangleAstType(ty)
            } else if (let Some(outer) <- fd.outerDecl) {
                if (let Some(property) <- (outer as PropDecl)) {
                    mangled += MangleAstType(property.typeNode.getOrThrow())
                }
            }
        }
        if (let Some(ctor) <- (decl as PrimaryCtorDecl)) {
            MangleFuncParameters(ctor.funcBody.getOrThrow().paramLists[0].params)
        }
        if (let Some(macroDecl) <- (decl as MacroDecl)) {
            MangleFuncParameters(macroDecl.funcBody.getOrThrow().paramLists[0].params)
        }
    }

    private func MangleExtendLiteralIfInExtend(decl: Decl): Unit {
        if (let Some(outer) <- decl.outerDecl) {
            if (outer.astKind == ASTKind.EXTEND_DECL) { mangled += MangleName(MANGLE_EXIG_PREFIX) }
        }
    }

    private func MangleGenericArguments(decl: Decl): Unit {
        let args = ArrayList<String>()
        if (decl.astKind == ASTKind.FUNC_DECL) {
            if (let Some(generic) <- (decl as FuncDecl).getOrThrow().funcBody.getOrThrow().generic) {
                for (arg in generic.typeParameters) { args.add(arg.identifier.Val()) }
            }
        } else if (let Some(generic) <- decl.generic) {
            if (decl.astKind == ASTKind.EXTEND_DECL) {
                for (arg in generic.typeParameters) { args.add(arg.identifier.Val()) }
            } else {
                mangled += MANGLE_LT_PREFIX + "${generic.typeParameters.size}" + MANGLE_GT_PREFIX
                return
            }
        }
        if (args.isEmpty()) { return }
        mangled += MANGLE_LT_PREFIX
        for (arg in args) { mangled += MangleName(arg) }
        mangled += MANGLE_GT_PREFIX
    }

    private func MangleNestedDecl(decl: Decl): Unit {
        var outerDecl = decl.outerDecl
        while (let Some(outer) <- outerDecl) {
            if (outer.TestAttr(Attribute.GLOBAL) && outer.TestAttr(Attribute.PRIVATE)) {
                mangled += MangleFilePrivate(outer)
            }
            if (let Some(ed) <- (outer as ExtendDecl)) {
                MangleExtendDecl(ed)
            } else {
                mangled += MangleName(outer.identifier.Val())
                MangleGenericArguments(outer)
                mangled += MangleDeclAstKind(outer.astKind)
            }
            outerDecl = outer.outerDecl
        }
    }

    private func MangleExtendDecl(decl: ExtendDecl): Unit {
        mangled += MangleAstType(decl.extendedType.getOrThrow())
        mangled += MANGLE_LT_COLON_PREFIX
        let inherits = ArrayList<String>()
        for (ty in decl.inheritedTypes) { inherits.add(MangleAstType(ty)) }
        var first = true
        for (item in sortedStrings(inherits)) {
            if (!first) { mangled += "&" }
            first = false
            mangled += item
        }
        if (let Some(generic) <- decl.generic) { MangleGenericConstraints(generic) }
        mangled += MangleDeclAstKind(ASTKind.EXTEND_DECL)
    }

    private func MangleGenericConstraints(generic: Generic): Unit {
        let constraints = ArrayList<(GenericConstraint, String)>()
        for (gc in generic.genericConstraints) {
            constraints.add((gc, MangleAstType(gc.refType.getOrThrow())))
        }
        sort(constraints, by: { left: (GenericConstraint, String), right: (GenericConstraint, String) =>
            if (left[1] < right[1]) { Ordering.LT }
            else if (left[1] > right[1]) { Ordering.GT } else { Ordering.EQ }
        }, stable: true)
        for ((gc, key) in constraints) {
            mangled += MANGLE_GEXTEND_PREFIX + key
            let uppers = ArrayList<String>()
            for (upper in gc.upperBounds) { uppers.add(MangleAstType(upper)) }
            for (upper in sortedStrings(uppers)) { mangled += ":" + upper }
        }
    }

    private func MangleVarWithPatternDecl(decl: VarWithPatternDecl): Unit {
        var ret = ""
        for (pattern in FlattenVarWithPatternDecl(decl)) {
            if (let Some(vp) <- (pattern as VarPattern)) {
                ret += MangleName(vp.varDecl.getOrThrow().identifier.Val())
            }
        }
        if (ret.isEmpty()) {
            let filename = decl.curFile.getOrThrow().fileName
            ret += MANGLE_WILDCARD_PREFIX + MangleName(filename) + "${NextWildcard(filename)}"
        }
        mangled += ret
        if (let Some(ty) <- decl.typeNode) { mangled += MangleAstType(ty) }
    }

    private func NextWildcard(filename: String): Int64 {
        let current = wildcardMap.get(filename) ?? 0
        wildcardMap[filename] = current + 1
        return current
    }
}

public class ASTMangler {
    private let impl: ASTManglerImpl

    public init(fullPackageName: String) { impl = ASTManglerImpl(fullPackageName) }

    public func Mangle(decl: Decl): String { return impl.Mangle(decl) }

    public static func ManglePrimitiveType(typeNode: Type): String {
        let primitive = (typeNode as PrimitiveType).getOrThrow()
        if (let Some(value) <- MangleBuiltinTypeImpl(primitive.str)) { return value }
        if (typeNode.GetTy().getOrThrow().kind == TypeKind.TYPE_INITIAL) { return MANGLE_INITIAL_PREFIX }
        throw IllegalArgumentException("Unexpected primitive type annotation: " + primitive.str)
    }

    public static func MangleBuiltinType(typeName: String): String {
        return MangleBuiltinTypeImpl(typeName) ?? typeName
    }

    public static func TruncateExtendMangledName(name: String): Option<String> {
        if (name.indexOf(MangleName(MANGLE_EXIG_PREFIX)).isSome()) { return None }
        if (let Some(pos) <- name.indexOf(MANGLE_LT_COLON_PREFIX)) { return name[0..pos] }
        return None
    }
}
