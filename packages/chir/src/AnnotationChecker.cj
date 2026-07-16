package cjcj::chir

import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.DiagKindRefactor
import cjcj::utils.CJC_ASSERT
import cjcj::utils.StaticCast
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

public class AnnotationChecker {
    private let pkg: Package
    private let diag: BasicDiagnosticEngine
    private let annotationTargets: HashMap<String, HashSet<String>> = HashMap<String, HashSet<String>>()
    private let targetToErrMsg: HashMap<String, String> = HashMap<String, String>()

    public init(pkg: Package, diag: BasicDiagnosticEngine) {
        this.pkg = pkg
        this.diag = diag
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

    public func Run(): Bool {
        CollectAnnotationTargets()
        CheckAnnotationTargets()
        return diag.GetErrorCount() == 0
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
        let enumCtorIdx = StaticCast<IntLiteral>(constValue).GetUnsignedVal()
        return annotationKindDef.GetCtor(Int64(enumCtorIdx)).name
    }

    private func CheckAnnotationTargets(): Unit {
        for (def in pkg.GetCurPkgCustomTypeDef()) {
            if (def.IsExtend()) {
                CheckTargetsOnDef(def, EXTENSION_TARGET)
            } else {
                CheckTargetsOnDef(def, TYPE_TARGET)
            }
        }
        for (globalVar in pkg.GetGlobalVarsWithInit(includeSrcCodeImported: false)) {
            CheckTargetsOnGlobalVar(globalVar)
        }
        for (fn in pkg.GetGlobalFunctions(includePureAbstract: true)) {
            if (fn.TestAttr(Attribute.IMPORTED)) {
                continue
            }
            CheckTargetsOnGlobalFunc(fn)
        }
    }

    private func CheckTargetsOnGlobalVar(globalVar: GlobalVar): Unit {
        if (globalVar.GetParentCustomTypeDef().isSome()) {
            CheckTargets(globalVar.GetAnnoInfo(), MEMBER_VARIABLE_TARGET)
        } else {
            CheckTargets(globalVar.GetAnnoInfo(), GLOBAL_VARIABLE_TARGET)
        }
    }

    private func CheckTargetsOnGlobalFunc(fn: Function): Unit {
        if (fn.GetParentCustomTypeDef().isSome()) {
            if (fn.IsConstructor()) {
                CheckTargets(fn.GetAnnoInfo(), INIT_TARGET)
            } else if (fn.GetFuncKind() == FuncKind.GETTER || fn.GetFuncKind() == FuncKind.SETTER) {
                CheckTargets(fn.GetAnnoInfo(), MEMBER_PROPERTY_TARGET)
            } else {
                CheckTargets(fn.GetAnnoInfo(), MEMBER_FUNCTION_TARGET)
            }
        } else {
            CheckTargets(fn.GetAnnoInfo(), GLOBAL_FUNCTION_TARGET)
        }
        for (param in fn.GetParams()) {
            CheckTargets(param.GetAnnoInfo(), PARAMETER_TARGET)
        }
    }

    private func CheckTargets(annoInfo: AnnoInfo, target: String): Unit {
        for (annoPair in annoInfo.GetCustomAnnoInstances()) {
            let annoClassName = annoPair.GetAnnoClassName()
            let targets = annotationTargets.get(annoClassName).getOrThrow()
            if (targets.isEmpty()) {
                continue
            }
            if (targets.contains(target)) {
                continue
            }
            let loc = ToRangeIfNotZero(annoPair.GetDebugLocation())[1]
            diag.DiagnoseRefactor(DiagKindRefactor.chir_annotation_not_applicable, loc,
                annoClassName, targetToErrMsg.get(target).getOrThrow()).Emit()
        }
    }

    private func CheckTargetsOnDef(def: CustomTypeDef, defTarget: String): Unit {
        CheckTargets(def.GetAnnoInfo(), defTarget)
        for (memberVar in def.GetDirectInstanceVars()) {
            CheckTargets(memberVar.annoInfo, MEMBER_VARIABLE_TARGET)
        }
        if (let Some(enumDef) <- (def as EnumDef)) {
            for (ctor in enumDef.GetCtors()) {
                CheckTargets(ctor.annoInfo, ENUM_CONSTRUCTOR_TARGET)
            }
        }
    }
}
