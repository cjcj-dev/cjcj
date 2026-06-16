package cangjie_compiler::mangle

import std.collection.*
import std.sort.*
import cangjie_compiler::ast.*

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
    }
    return mangledName
}

private func MangleOptionTypeAnnotation(typeAnnotation: MangleTypeAnnotation): String {
    var mangledName = MANGLE_OPTION_PREFIX + "${typeAnnotation.questNum}" + MANGLE_WILDCARD_PREFIX
    if (let Some(component) <- typeAnnotation.componentType) {
        mangledName += MangleAstType(component)
    }
    return mangledName
}

private func MangleFuncTypeAnnotation(typeAnnotation: MangleTypeAnnotation): String {
    var mangledName = if (typeAnnotation.isC) { MANGLE_AST_CFUNC_PREFIX } else { MANGLE_AST_FUNC_PREFIX }
    if (let Some(ret) <- typeAnnotation.retType) {
        mangledName += MangleAstType(ret)
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
    }
    if (let Some(constantType) <- typeAnnotation.constantType) {
        mangledName += MangleAstType(constantType)
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
        case MangleAstKind.PRIMITIVE_TYPE => ASTMangler.ManglePrimitiveType(typeAnnotation)
        case MangleAstKind.REF_TYPE => MangleRefTypeAnnotation(typeAnnotation)
        case MangleAstKind.PAREN_TYPE => MangleParenTypeAnnotation(typeAnnotation)
        case MangleAstKind.OPTION_TYPE => MangleOptionTypeAnnotation(typeAnnotation)
        case MangleAstKind.CONSTANT_TYPE => MangleConstantTypeAnnotation(typeAnnotation)
        case MangleAstKind.VARRAY_TYPE => MangleVArrayTypeAnnotation(typeAnnotation)
        case MangleAstKind.FUNC_TYPE => MangleFuncTypeAnnotation(typeAnnotation)
        case MangleAstKind.TUPLE_TYPE => MangleTupleTypeAnnotation(typeAnnotation)
        case MangleAstKind.QUALIFIED_TYPE => MangleQualifiedTypeAnnotation(typeAnnotation)
        case MangleAstKind.THIS_TYPE => MANGLE_THIS_PREFIX
        case _ => ""
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
    if (param.TestAttr(MangleAttribute.PUBLIC)) {
        res += MANGLE_PUBLIC_PREFIX
    }
    if (param.TestAttr(MangleAttribute.PROTECTED)) {
        res += MANGLE_PROTECTED_PREFIX
    }
    if (param.TestAttr(MangleAttribute.PRIVATE)) {
        res += MANGLE_PRIVATE_PREFIX
    }
    return res
}

private func MangleDeclAstKind(kind: MangleAstKind): String {
    return match (kind) {
        case MangleAstKind.FUNC_DECL => "F"
        case MangleAstKind.MACRO_DECL => "M"
        case MangleAstKind.CLASS_DECL => "C"
        case MangleAstKind.INTERFACE_DECL => "I"
        case MangleAstKind.EXTEND_DECL => "X"
        case MangleAstKind.ENUM_DECL => "U"
        case MangleAstKind.STRUCT_DECL => "S"
        case MangleAstKind.TYPE_ALIAS_DECL => "T"
        case MangleAstKind.PRIMARY_CTOR_DECL => "Y"
        case MangleAstKind.VAR_DECL => "V"
        case MangleAstKind.PROP_DECL => "P"
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
    if (pattern.astKind == MangleAstKind.VAR_PATTERN || pattern.astKind == MangleAstKind.WILDCARD_PATTERN) {
        out.add(pattern)
        return
    }
    if (pattern.astKind == MangleAstKind.TUPLE_PATTERN || pattern.astKind == MangleAstKind.ENUM_PATTERN) {
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
        if (decl.astKind == MangleAstKind.VAR_WITH_PATTERN_DECL) {
            return MangleVarWithPatternDecl(decl)
        }
        if (decl.astKind == MangleAstKind.EXTEND_DECL) {
            var mangled = ""
            MangleExtendDecl(decl, mangledRef: StringRef(mangled))
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
            if (ty.kind == MangleTypeKind.TYPE_INITIAL) {
                return MANGLE_INITIAL_PREFIX
            }
        }
        return MANGLE_INITIAL_PREFIX
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
        if (decl.TestAttr(MangleAttribute.GLOBAL) && decl.TestAttr(MangleAttribute.PRIVATE)) {
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
        let useInternalIdent = decl.TestAnyAttr(MangleAttribute.CONSTRUCTOR, MangleAttribute.MAIN_ENTRY) &&
            decl.astKind != MangleAstKind.PRIMARY_CTOR_DECL
        if (useInternalIdent) {
            mangled += MangleName(MANGLE_LT_PREFIX + decl.identifier + MANGLE_GT_PREFIX)
        } else {
            mangled += MangleName(decl.identifier)
        }
        mangled += MangleGenericArguments(decl)
        mangled += MangleDeclAstKind(decl.astKind)
        if (decl.astKind == MangleAstKind.FUNC_DECL && decl.TestAttr(MangleAttribute.CONSTRUCTOR) &&
            decl.TestAttr(MangleAttribute.STATIC)) {
            let initSuffix = MangleName(MANGLE_LT_PREFIX + decl.identifier + MANGLE_GT_PREFIX) +
                MangleDeclAstKind(MangleAstKind.FUNC_DECL)
            if (EndsWith(mangled, initSuffix)) {
                mangled = mangled[0..mangled.size - initSuffix.size] + MangleName(STATIC_INIT_FUNC)
            }
        }
        mangled += MangleOthers(decl)
        return mangled
    }

    private func MangleOthers(decl: MangleDecl): String {
        var mangled = ""
        if (decl.astKind == MangleAstKind.VAR_DECL ||
            (decl.astKind == MangleAstKind.FUNC_PARAM && decl.isMemberParam)) {
            mangled += MANGLE_DIDOLLAR_PREFIX
            if (let Some(typeAnnotation) <- decl.typeAnnotation) {
                mangled += MangleAstType(typeAnnotation)
            }
        }
        if (decl.astKind == MangleAstKind.MAIN_DECL || decl.astKind == MangleAstKind.FUNC_DECL ||
            decl.astKind == MangleAstKind.MACRO_DECL || decl.astKind == MangleAstKind.PRIMARY_CTOR_DECL) {
            if (let Some(body) <- decl.funcBody) {
                mangled += MangleFuncParameters(body.params)
                if (decl.astKind == MangleAstKind.FUNC_DECL) {
                    mangled += MANGLE_DIDOLLAR_PREFIX
                    if (let Some(retType) <- body.retType) {
                        mangled += MangleAstType(retType)
                    } else if (let Some(outer) <- decl.outerDecl) {
                        if (outer.astKind == MangleAstKind.PROP_DECL) {
                            if (let Some(typeAnnotation) <- outer.typeAnnotation) {
                                mangled += MangleAstType(typeAnnotation)
                            }
                        }
                    }
                } else if (decl.astKind == MangleAstKind.MAIN_DECL) {
                    if (let Some(retType) <- body.retType) {
                        mangled += MangleAstType(retType)
                    }
                }
            }
        }
        return mangled
    }

    private func MangleExtendLiteralIfInExtend(decl: MangleDecl): String {
        if (let Some(outer) <- decl.outerDecl) {
            if (outer.astKind == MangleAstKind.EXTEND_DECL) {
                return MangleName(MANGLE_EXIG_PREFIX)
            }
        }
        return ""
    }

    private func MangleGenericArguments(decl: MangleDecl): String {
        let args = ArrayList<String>()
        if (decl.astKind == MangleAstKind.FUNC_DECL) {
            if (let Some(body) <- decl.funcBody) {
                if (let Some(generic) <- body.generic) {
                    for (arg in generic.typeParameters) {
                        args.add(arg.identifier)
                    }
                }
            }
        } else if (let Some(generic) <- decl.generic) {
            if (decl.astKind == MangleAstKind.EXTEND_DECL) {
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
            if (outer.TestAttr(MangleAttribute.GLOBAL) && outer.TestAttr(MangleAttribute.PRIVATE)) {
                mangled += MangleFilePrivate(outer)
            }
            if (outer.astKind == MangleAstKind.EXTEND_DECL) {
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
        if (let Some(extendedType) <- decl.extendedType) {
            mangled += MangleAstType(extendedType)
        }
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
        mangled += MangleDeclAstKind(MangleAstKind.EXTEND_DECL)
        return mangled
    }

    private func MangleExtendDecl(decl: MangleDecl, mangledRef!: StringRef): Unit {
        mangledRef.value += MangleExtendDeclString(decl)
    }

    private func MangleGenericConstraints(generic: MangleGeneric): String {
        let constraints = ArrayList<GenericConstraintMangle>()
        for (constraint in generic.genericConstraints) {
            var constrainedType = ""
            var item = MANGLE_GEXTEND_PREFIX
            if (let Some(typeAnnotation) <- constraint.typeAnnotation) {
                constrainedType = MangleAstType(typeAnnotation)
                item += constrainedType
            }
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
        if (let Some(pattern) <- decl.irrefutablePattern) {
            let patterns = ArrayList<ManglePattern>()
            flattenVarWithPattern(pattern, patterns)
            for (item in patterns) {
                if (item.astKind == MangleAstKind.VAR_PATTERN) {
                    if (let Some(varDecl) <- item.varDecl) {
                        ret += MangleName(varDecl.identifier)
                    }
                }
            }
        }
        if (ret.isEmpty()) {
            let filename = if (let Some(file) <- decl.curFile) { file.fileName } else { "" }
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
