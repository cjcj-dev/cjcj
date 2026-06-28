package cangjie_compiler::chir

import cangjie_compiler::utils.CJC_ASSERT
import cangjie_compiler::utils.StaticCast
import std.collection.*

private let TYPE_TARGET = "Type"
private let PARAMETER_TARGET = "Parameter"
private let INIT_TARGET = "Init"
private let MEMBER_PROPERTY_TARGET = "MemberProperty"
private let MEMBER_FUNCTION_TARGET = "MemberFunction"
private let MEMBER_VARIABLE_TARGET = "MemberVariable"
private let ENUM_CONSTRUCTOR_TARGET = "EnumConstructor"
private let GLOBAL_FUNCTION_TARGET = "GlobalFunction"
private let GLOBAL_VARIABLE_TARGET = "GlobalVariable"
private let EXTENSION_TARGET = "Extension"

private let CUSTOM_ANNO_METADATA_KEYS: Array<String> = [
    "customAnnotations",
    "annotations",
    "annos"
]

public class AnnotationChecker {
    private let pkg: Package
    private let annotationTargets: HashMap<String, HashSet<String>> = HashMap<String, HashSet<String>>()
    private let targetToErrMsg: HashMap<String, String> = HashMap<String, String>()

    public init(pkg: Package) {
        this.pkg = pkg
        targetToErrMsg[TYPE_TARGET] = "type"
        targetToErrMsg[PARAMETER_TARGET] = "parameter"
        targetToErrMsg[INIT_TARGET] = "init"
        targetToErrMsg[MEMBER_PROPERTY_TARGET] = "member property"
        targetToErrMsg[MEMBER_FUNCTION_TARGET] = "member function"
        targetToErrMsg[MEMBER_VARIABLE_TARGET] = "member variable"
        targetToErrMsg[ENUM_CONSTRUCTOR_TARGET] = "enum constructor"
        targetToErrMsg[GLOBAL_FUNCTION_TARGET] = "global function"
        targetToErrMsg[GLOBAL_VARIABLE_TARGET] = "global variable"
        targetToErrMsg[EXTENSION_TARGET] = "extend"
    }

    public func Run(): CHIRCheckResult {
        let result = CHIRCheckResult()
        Run(result)
        return result
    }

    public func Run(result: CHIRCheckResult): Unit {
        CollectAnnotationTargets()
        CheckAnnotationTargets(result)
    }

    private func CollectAnnotationTargets(): Unit {
        for (def in pkg.GetAllClassDef()) {
            if (!def.IsAnnotation()) {
                continue
            }
            let targets = def.GetAnnotationTargets()
            if (targets.isEmpty()) {
                annotationTargets[def.GetSrcCodeIdentifier()] = HashSet<String>()
                continue
            }
            let result = HashSet<String>()
            for (target in targets) {
                result.add(CalculateTarget(target))
            }
            annotationTargets[def.GetSrcCodeIdentifier()] = result
        }
    }

    private func CalculateTarget(globalVar: GlobalVar): String {
        let users = globalVar.GetUsers()
        CJC_ASSERT(users.size == 1)
        let store = StaticCast<Store>(users[0])
        let storeValue = store.GetValue()
        let annotationKindDef = StaticCast<EnumType>(storeValue.GetType().getOrThrow()).GetEnumDef()
        CJC_ASSERT(annotationKindDef.GetSrcCodeIdentifier() == "AnnotationKind")
        CJC_ASSERT(annotationKindDef.GetPackageName() == "std.core")
        let typecast = StaticCast<TypeCast>(StaticCast<LocalVar>(storeValue).GetExpr().getOrThrow())
        let constExpr = StaticCast<Constant>(StaticCast<LocalVar>(typecast.GetSourceValue()).GetExpr().getOrThrow())
        let constValue = constExpr.GetValue()
        CJC_ASSERT(RequiredResultType(constExpr).GetTypeKind() == TypeKind.TYPE_UINT32)
        let enumCtorIdx = StaticCast<IntLiteral>(constValue).value
        return annotationKindDef.GetCtor(enumCtorIdx).name
    }

    private func CheckAnnotationTargets(result: CHIRCheckResult): Unit {
        for (def in pkg.GetCurPkgCustomTypeDef()) {
            if ((def as ExtendDef).isSome()) {
                CheckTargetsOnDef(def, EXTENSION_TARGET, result)
            } else {
                CheckTargetsOnDef(def, TYPE_TARGET, result)
            }
        }
        for (globalVar in pkg.GetGlobalVarsWithInit(includeSrcCodeImported: false)) {
            CheckTargetsOnGlobalVar(globalVar, result)
        }
        for (fn in pkg.GetGlobalFunctions(includePureAbstract: true)) {
            if (!fn.TestAttr(Attribute.IMPORTED)) {
                CheckTargetsOnGlobalFunc(fn, result)
            }
        }
    }

    private func CheckTargetsOnDef(def: CustomTypeDef, defTarget: String, result: CHIRCheckResult): Unit {
        CheckTargets(GetDefCustomAnnotations(def), defTarget, result)
        for (memberVar in def.GetDirectInstanceVars()) {
            CheckTargets(memberVar.annoInfo.GetAnnotations(), MEMBER_VARIABLE_TARGET, result)
        }
    }

    private func CheckTargetsOnGlobalVar(globalVar: GlobalVar, result: CHIRCheckResult): Unit {
        if (globalVar.GetParentCustomTypeDef().isSome()) {
            CheckTargets(globalVar.GetAnnoInfo().GetAnnotations(), MEMBER_VARIABLE_TARGET, result)
        } else {
            CheckTargets(globalVar.GetAnnoInfo().GetAnnotations(), GLOBAL_VARIABLE_TARGET, result)
        }
    }

    private func CheckTargetsOnGlobalFunc(fn: Function, result: CHIRCheckResult): Unit {
        if (fn.GetParentCustomTypeDef().isSome()) {
            if (fn.IsConstructor()) {
                CheckTargets(fn.GetAnnoInfo().GetAnnotations(), INIT_TARGET, result)
            } else if (fn.GetFuncKind() == FuncKind.GETTER || fn.GetFuncKind() == FuncKind.SETTER) {
                CheckTargets(fn.GetAnnoInfo().GetAnnotations(), MEMBER_PROPERTY_TARGET, result)
            } else {
                CheckTargets(fn.GetAnnoInfo().GetAnnotations(), MEMBER_FUNCTION_TARGET, result)
            }
        } else {
            CheckTargets(fn.GetAnnoInfo().GetAnnotations(), GLOBAL_FUNCTION_TARGET, result)
        }
        for (param in fn.GetParams()) {
            CheckTargets(param.GetAnnoInfo().GetAnnotations(), PARAMETER_TARGET, result)
        }
    }

    private func CheckTargets(annotations: ArrayList<String>, target: String, result: CHIRCheckResult): Unit {
        for (annotation in annotations) {
            let annoName = NormalizeAnnotationName(annotation)
            if (annoName.isEmpty()) {
                continue
            }
            let maybeTargets = ResolveAnnotationTargets(annoName)
            if (maybeTargets.isNone()) {
                result.AddError("annotation `${annoName}` has no collected annotation target metadata.")
                continue
            }
            if (let Some(targets) <- maybeTargets) {
                if (targets.isEmpty() || targets.contains(target)) {
                    continue
                }
                let targetText = targetToErrMsg.get(target) ?? target
                result.AddError("annotation `${annoName}` is not applicable to ${targetText}.")
            }
        }
    }

    private func ResolveAnnotationTargets(name: String): Option<HashSet<String>> {
        if (let Some(targets) <- annotationTargets.get(name)) {
            return CopyStringSet(targets)
        }
        let shortName = ShortAnnotationName(name)
        if (let Some(targets) <- annotationTargets.get(shortName)) {
            return CopyStringSet(targets)
        }
        return None
    }
}

private func GetDefCustomAnnotations(def: CustomTypeDef): ArrayList<String> {
    let out = def.GetAnnoInfo().GetAnnotations()
    for (annotation in GetMetadataCustomAnnotations(def)) {
        AddAnnotationIfMissing(out, annotation)
    }
    return out
}

private func GetMetadataCustomAnnotations(def: CustomTypeDef): ArrayList<String> {
    for (key in CUSTOM_ANNO_METADATA_KEYS) {
        if (let Some(rawAnnotations) <- def.GetAnnotation(key)) {
            return ParseStringList(rawAnnotations)
        }
    }
    return ArrayList<String>()
}

private func AddAnnotationIfMissing(values: ArrayList<String>, annotation: String): Unit {
    for (value in values) {
        if (value == annotation) {
            return
        }
    }
    values.add(annotation)
}

private func ParseStringList(rawValue: String): ArrayList<String> {
    let out = ArrayList<String>()
    var current = ""
    var idx: Int64 = 0
    while (idx < rawValue.size) {
        let byte = rawValue[idx]
        if (IsAnnotationListDelimiter(byte)) {
            AddTrimmedIfNotEmpty(out, current)
            current = ""
        } else {
            current += rawValue[idx..idx + 1]
        }
        idx++
    }
    AddTrimmedIfNotEmpty(out, current)
    return out
}

private func AddTrimmedIfNotEmpty(values: ArrayList<String>, rawValue: String): Unit {
    let value = rawValue.trimAscii()
    if (!value.isEmpty()) {
        values.add(value)
    }
}

private func IsAnnotationListDelimiter(byte: UInt8): Bool {
    return byte == b',' || byte == b';' || byte == b'|' || byte == b' ' || byte == b'\t' ||
        byte == b'\n' || byte == b'\r'
}

private func NormalizeAnnotationName(annotation: String): String {
    var name = annotation.trimAscii()
    if (name.startsWith("@")) {
        name = name[1..]
    }
    let parenIndex = FindByte(name, b'(')
    if (parenIndex >= 0) {
        name = name[0..parenIndex]
    }
    return name.trimAscii()
}

private func ShortAnnotationName(name: String): String {
    let trimmed = name.trimAscii()
    var lastDot: Int64 = -1
    var idx: Int64 = 0
    while (idx < trimmed.size) {
        if (trimmed[idx] == b'.') {
            lastDot = idx
        }
        idx++
    }
    if (lastDot >= 0 && lastDot + 1 < trimmed.size) {
        return trimmed[lastDot + 1..]
    }
    return trimmed
}

private func FindByte(value: String, target: UInt8): Int64 {
    var idx: Int64 = 0
    while (idx < value.size) {
        if (value[idx] == target) {
            return idx
        }
        idx++
    }
    return -1
}

private func CopyStringSet(values: HashSet<String>): HashSet<String> {
    let out = HashSet<String>()
    for (value in values) {
        out.add(value)
    }
    return out
}
