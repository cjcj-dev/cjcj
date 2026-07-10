package cjcj::mangle

import std.collection.*
import std.sort.*
import cjcj::ast.*

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

private func MangleRefTypeAnnotation(typeAnnotation: MangleTypeAnnotation): String {
    var mangledName = MangleName(typeAnnotation.name)
    if (!typeAnnotation.typeArguments.isEmpty()) {
        mangledName += MANGLE_LT_PREFIX
        for (arg in typeAnnotation.typeArguments) {
            mangledName += MangleAstType(arg)
        }
        mangledName += MANGLE_GT_PREFIX
    }
    return mangledName
}

private func MangleParenTypeAnnotation(typeAnnotation: MangleTypeAnnotation): String {
    var mangledName = MANGLE_PAREN_PREFIX + MANGLE_WILDCARD_PREFIX
    if (let Some(inner) <- typeAnnotation.innerType) {
        mangledName += MangleAstType(inner)
    } else {
        throw IllegalArgumentException("Parenthesized type annotation has no inner type.")
    }
    return mangledName
}

private func MangleOptionTypeAnnotation(typeAnnotation: MangleTypeAnnotation): String {
    var mangledName = MANGLE_OPTION_PREFIX + "${typeAnnotation.questNum}" + MANGLE_WILDCARD_PREFIX
    if (let Some(component) <- typeAnnotation.componentType) {
        mangledName += MangleAstType(component)
    } else {
        throw IllegalArgumentException("Option type annotation has no component type.")
    }
    return mangledName
}

private func MangleFuncTypeAnnotation(typeAnnotation: MangleTypeAnnotation): String {
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

private func MangleConstantTypeAnnotation(typeAnnotation: MangleTypeAnnotation): String {
    return MANGLE_DOLLAR_PREFIX + typeAnnotation.constantValue
}

private func MangleVArrayTypeAnnotation(typeAnnotation: MangleTypeAnnotation): String {
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

private func MangleTupleTypeAnnotation(typeAnnotation: MangleTypeAnnotation): String {
    var mangledName = MANGLE_TUPLE_PREFIX + "${typeAnnotation.fieldTypes.size}" + MANGLE_WILDCARD_PREFIX
    for (field in typeAnnotation.fieldTypes) {
        mangledName += MangleAstType(field)
    }
    return mangledName
}

private func MangleQualifiedTypeAnnotation(typeAnnotation: MangleTypeAnnotation): String {
    var mangledName = MANGLE_QUALIFIED_PREFIX
    if (let Some(baseType) <- typeAnnotation.baseType) {
        mangledName += MangleAstType(baseType)
    } else {
        throw IllegalArgumentException("Qualified type annotation has no base type.")
    }
    mangledName += MANGLE_DOT_PREFIX + MangleName(typeAnnotation.field)
    if (!typeAnnotation.typeArguments.isEmpty()) {
        mangledName += MANGLE_LT_PREFIX
        for (arg in typeAnnotation.typeArguments) {
            mangledName += MangleAstType(arg)
        }
        mangledName += MANGLE_GT_PREFIX
    }
    return mangledName
}

public func MangleAstType(typeAnnotation: MangleTypeAnnotation): String {
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

public func MangleAstType(typeNode: Type): String {
    let adapter = MangleAstAdapter()
    return MangleAstType(adapter.ConvertTypeAnnotation(typeNode))
}

private func MangleAccessibility(param: MangleFuncParam): String {
    if (param.hasAccessibilityModifiers) {
        return param.accessibilityModifiers
    }
    var res = ""
    if (param.TestAttr(Attribute.PUBLIC)) {
        res += MANGLE_PUBLIC_PREFIX
    }
    if (param.TestAttr(Attribute.PROTECTED)) {
        res += MANGLE_PROTECTED_PREFIX
    }
    if (param.TestAttr(Attribute.PRIVATE)) {
        res += MANGLE_PRIVATE_PREFIX
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

private class GenericConstraintMangle {
    public var key: String
    public var rendered: String

    public init(key: String, rendered: String) {
        this.key = key
        this.rendered = rendered
    }
}

private func sortedGenericConstraints(values: ArrayList<GenericConstraintMangle>): ArrayList<GenericConstraintMangle> {
    let out = ArrayList<GenericConstraintMangle>()
    for (value in values) {
        out.add(value)
    }
    sort(out, by: { left: GenericConstraintMangle, right: GenericConstraintMangle =>
        if (left.key < right.key) {
            Ordering.LT
        } else if (left.key > right.key) {
            Ordering.GT
        } else {
            Ordering.EQ
        }
    }, stable: true)
    return out
}

private func flattenVarWithPattern(pattern: ManglePattern, out: ArrayList<ManglePattern>): Unit {
    if (pattern.astKind == ASTKind.VAR_PATTERN || pattern.astKind == ASTKind.WILDCARD_PATTERN) {
        out.add(pattern)
        return
    }
    if (pattern.astKind == ASTKind.TUPLE_PATTERN || pattern.astKind == ASTKind.ENUM_PATTERN) {
        for (child in pattern.patterns) {
            flattenVarWithPattern(child, out)
        }
    }
}

public class ASTMangler {
    private var fullPackageName: String
    private let wildcardMap: HashMap<String, Int64> = HashMap<String, Int64>()

    public init(fullPackageName: String) {
        this.fullPackageName = fullPackageName
    }

    public func Mangle(decl: MangleDecl): String {
        if (decl.astKind == ASTKind.VAR_WITH_PATTERN_DECL) {
            return MangleVarWithPatternDecl(decl)
        }
        if (decl.astKind == ASTKind.EXTEND_DECL) {
            return MangleExtendDeclString(decl)
        }
        return MangleDeclCommon(decl)
    }

    public func Mangle(decl: Decl): String {
        let adapter = MangleAstAdapter()
        return Mangle(adapter.ConvertDecl(decl))
    }

    public static func ManglePrimitiveType(typeAnnotation: MangleTypeAnnotation): String {
        if (let Some(value) <- MangleBuiltinTypeImpl(typeAnnotation.name)) {
            return value
        }
        if (let Some(ty) <- typeAnnotation.ty) {
            if (ty.kind == TypeKind.TYPE_INITIAL) {
                return MANGLE_INITIAL_PREFIX
            }
        }
        throw IllegalArgumentException("Unexpected primitive type annotation: " + typeAnnotation.name)
    }

    public static func ManglePrimitiveType(typeNode: Type): String {
        let adapter = MangleAstAdapter()
        return ASTMangler.ManglePrimitiveType(adapter.ConvertTypeAnnotation(typeNode))
    }

    public static func MangleBuiltinType(typeName: String): String {
        if (let Some(value) <- MangleBuiltinTypeImpl(typeName)) {
            return value
        }
        return typeName
    }

    public static func TruncateExtendMangledName(name: String): Option<String> {
        if (let Some(_) <- name.indexOf(MangleName(MANGLE_EXIG_PREFIX))) {
            return None
        }
        if (let Some(pos) <- name.indexOf(MANGLE_LT_COLON_PREFIX)) {
            return name[0..pos]
        }
        return None
    }

    private func MangleFullPackageName(decl: MangleDecl): String {
        let ret = MangleName(fullPackageName)
        if (decl.TestAttr(Attribute.GLOBAL) && decl.TestAttr(Attribute.PRIVATE)) {
            return ret + MangleFilePrivate(decl)
        }
        return ret
    }

    private func MangleFuncParameters(params: ArrayList<MangleFuncParam>): String {
        var mangled = ""
        for (param in params) {
            if (let Some(typeAnnotation) <- param.typeAnnotation) {
                mangled += MangleAstType(typeAnnotation)
            }
            if (param.isMemberParam || param.isNamedParam) {
                mangled += "!"
            }
            if (param.isMemberParam && param.hasLetOrVar) {
                mangled += MangleAccessibility(param)
                mangled += if (param.isVar) { MANGLE_VARIABLE_PREFIX } else { MANGLE_LET_PREFIX }
            }
            if (param.isMemberParam || param.isNamedParam) {
                mangled += MangleName(param.identifier)
                if (param.assignment) {
                    mangled += "="
                }
            }
        }
        return mangled
    }

    private func MangleDeclCommon(decl: MangleDecl): String {
        var mangled = MangleFullPackageName(decl)
        mangled += MangleExtendLiteralIfInExtend(decl)
        mangled += MangleNestedDecl(decl)
        let useInternalIdent = decl.TestAnyAttr(Attribute.CONSTRUCTOR, Attribute.MAIN_ENTRY) &&
            decl.astKind != ASTKind.PRIMARY_CTOR_DECL
        if (useInternalIdent) {
            mangled += MangleName(MANGLE_LT_PREFIX + decl.identifier + MANGLE_GT_PREFIX)
        } else {
            mangled += MangleName(decl.identifier)
        }
        mangled += MangleGenericArguments(decl)
        mangled += MangleDeclAstKind(decl.astKind)
        let mangledRef = StringRef(mangled)
        MangleOthers(decl, mangledRef: mangledRef)
        return mangledRef.value
    }

    private func MangleOthers(decl: MangleDecl, mangledRef!: StringRef): Unit {
        if (decl.astKind == ASTKind.VAR_DECL ||
            (decl.astKind == ASTKind.FUNC_PARAM && decl.isMemberParam)) {
            mangledRef.value += MANGLE_DIDOLLAR_PREFIX
            if (let Some(typeAnnotation) <- decl.typeAnnotation) {
                mangledRef.value += MangleAstType(typeAnnotation)
            }
        }
        if (decl.astKind == ASTKind.MAIN_DECL || decl.astKind == ASTKind.FUNC_DECL ||
            decl.astKind == ASTKind.MACRO_DECL || decl.astKind == ASTKind.PRIMARY_CTOR_DECL) {
            let body = if (let Some(value) <- decl.funcBody) {
                value
            } else {
                throw IllegalArgumentException("Function-like declaration has no function body: " + decl.identifier)
            }
            mangledRef.value += MangleFuncParameters(body.params)
            if (decl.astKind == ASTKind.FUNC_DECL) {
                if (decl.TestAttr(Attribute.CONSTRUCTOR) && decl.TestAttr(Attribute.STATIC)) {
                    let initNameAndEnd: Int64 = 8
                    mangledRef.value = mangledRef.value[0..mangledRef.value.size - initNameAndEnd] +
                        MangleName(STATIC_INIT_FUNC)
                }
                mangledRef.value += MANGLE_DIDOLLAR_PREFIX
                if (let Some(retType) <- body.retType) {
                    mangledRef.value += MangleAstType(retType)
                } else if (let Some(outer) <- decl.outerDecl) {
                    if (outer.astKind == ASTKind.PROP_DECL) {
                        if (let Some(typeAnnotation) <- outer.typeAnnotation) {
                            mangledRef.value += MangleAstType(typeAnnotation)
                        } else {
                            throw IllegalArgumentException("Property accessor has no property type: " + decl.identifier)
                        }
                    }
                }
            } else if (decl.astKind == ASTKind.MAIN_DECL) {
                if (let Some(retType) <- body.retType) {
                    mangledRef.value += MangleAstType(retType)
                }
            }
        }
    }

    private func MangleExtendLiteralIfInExtend(decl: MangleDecl): String {
        if (let Some(outer) <- decl.outerDecl) {
            if (outer.astKind == ASTKind.EXTEND_DECL) {
                return MangleName(MANGLE_EXIG_PREFIX)
            }
        }
        return ""
    }

    private func MangleGenericArguments(decl: MangleDecl): String {
        let args = ArrayList<String>()
        if (decl.astKind == ASTKind.FUNC_DECL) {
            if (let Some(body) <- decl.funcBody) {
                if (let Some(generic) <- body.generic) {
                    for (arg in generic.typeParameters) {
                        args.add(arg.identifier)
                    }
                }
            }
        } else if (let Some(generic) <- decl.generic) {
            if (decl.astKind == ASTKind.EXTEND_DECL) {
                for (arg in generic.typeParameters) {
                    args.add(arg.identifier)
                }
            } else {
                return MANGLE_LT_PREFIX + "${generic.typeParameters.size}" + MANGLE_GT_PREFIX
            }
        }
        if (args.isEmpty()) {
            return ""
        }
        var mangled = MANGLE_LT_PREFIX
        for (arg in args) {
            mangled += MangleName(arg)
        }
        mangled += MANGLE_GT_PREFIX
        return mangled
    }

    private func MangleNestedDecl(decl: MangleDecl): String {
        var mangled = ""
        var outerDecl = decl.outerDecl
        while (let Some(outer) <- outerDecl) {
            if (outer.TestAttr(Attribute.GLOBAL) && outer.TestAttr(Attribute.PRIVATE)) {
                mangled += MangleFilePrivate(outer)
            }
            if (outer.astKind == ASTKind.EXTEND_DECL) {
                mangled += MangleExtendDeclString(outer)
            } else {
                mangled += MangleName(outer.identifier)
                mangled += MangleGenericArguments(outer)
                mangled += MangleDeclAstKind(outer.astKind)
            }
            outerDecl = outer.outerDecl
        }
        return mangled
    }

    private func MangleExtendDeclString(decl: MangleDecl): String {
        var mangled = ""
        let extendedType = if (let Some(value) <- decl.extendedType) {
            value
        } else {
            throw IllegalArgumentException("Extend declaration has no extended type.")
        }
        mangled += MangleAstType(extendedType)
        mangled += MANGLE_LT_COLON_PREFIX
        let inherits = ArrayList<String>()
        for (inheritedType in decl.inheritedTypes) {
            inherits.add(MangleAstType(inheritedType))
        }
        let sortedInherits = sortedStrings(inherits)
        var first = true
        for (item in sortedInherits) {
            if (!first) {
                mangled += "&"
            }
            first = false
            mangled += item
        }
        if (let Some(generic) <- decl.generic) {
            mangled += MangleGenericConstraints(generic)
        }
        mangled += MangleDeclAstKind(ASTKind.EXTEND_DECL)
        return mangled
    }

    private func MangleGenericConstraints(generic: MangleGeneric): String {
        let constraints = ArrayList<GenericConstraintMangle>()
        for (constraint in generic.genericConstraints) {
            var item = MANGLE_GEXTEND_PREFIX
            let constrainedType = if (let Some(typeAnnotation) <- constraint.typeAnnotation) {
                MangleAstType(typeAnnotation)
            } else {
                throw IllegalArgumentException("Generic constraint has no constrained type.")
            }
            item += constrainedType
            let uppers = ArrayList<String>()
            for (upper in constraint.upperBounds) {
                uppers.add(MangleAstType(upper))
            }
            for (upper in sortedStrings(uppers)) {
                item += ":" + upper
            }
            constraints.add(GenericConstraintMangle(constrainedType, item))
        }
        var out = ""
        for (item in sortedGenericConstraints(constraints)) {
            out += item.rendered
        }
        return out
    }

    private func MangleVarWithPatternDecl(decl: MangleDecl): String {
        var ret = ""
        let pattern = if (let Some(value) <- decl.irrefutablePattern) {
            value
        } else {
            throw IllegalArgumentException("VarWithPattern declaration has no irrefutable pattern.")
        }
        let patterns = ArrayList<ManglePattern>()
        flattenVarWithPattern(pattern, patterns)
        for (item in patterns) {
            if (item.astKind == ASTKind.VAR_PATTERN) {
                if (let Some(varDecl) <- item.varDecl) {
                    ret += MangleName(varDecl.identifier)
                } else {
                    throw IllegalArgumentException("VarPattern has no variable declaration.")
                }
            }
        }
        if (ret.isEmpty()) {
            let filename = if (let Some(file) <- decl.curFile) {
                file.fileName
            } else {
                throw IllegalArgumentException("Wildcard VarWithPattern declaration has no current file.")
            }
            ret += MANGLE_WILDCARD_PREFIX + MangleName(filename) + "${NextWildcard(filename)}"
        }
        if (let Some(typeAnnotation) <- decl.typeAnnotation) {
            ret += MangleAstType(typeAnnotation)
        }
        return ret
    }

    private func NextWildcard(filename: String): Int64 {
        let current = wildcardMap.get(filename) ?? 0
        wildcardMap[filename] = current + 1
        return current
    }
}
