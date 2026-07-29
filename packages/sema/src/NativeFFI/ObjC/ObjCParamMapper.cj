package cjcj::sema.NativeFFI.ObjC

import std.collection.*
import cjcj::ast.*

// C++ src/Sema/NativeFFI/ObjC/ObjCCodeTranspiler/ObjCParamMapper.h:27.
public type ArgsList = ArrayList<(String, String)>

// C++ src/Sema/NativeFFI/ObjC/ObjCCodeTranspiler/ObjCParamMapper.h:34-90 and
// ObjCParamMapper.cpp:32,98-257.
public class ObjCParamMapper {
    public static let ID_TYPE: String = "id"
    private static let CAST_TO_VOID_PTR: String = "(__bridge void*)"
    private static let CAST_TO_VOID_PTR_RETAINED: String = "(__bridge_retained void*)"
    private static let CAST_TO_VOID_PTR_UNSAFE: String = "(void*)"
    private static let REGISTRY_ID: String = "$registryId"
    private static let SELF_NAME: String = "self"
    private static let UNSUPPORTED_TYPE: String = "UNSUPPORTED_TYPE"
    private static let INT64_T: String = "int64_t"
    private static let SETTER_PARAM_NAME: String = "value"
    private static let VOID_TYPE: String = "void"
    private static let VOID_POINTER_TYPE: String = VOID_TYPE + "*"

    public init() {}

    public static func ConvertParamsListToArgsList(typedefs: HashSet<String>,
        paramLists: ArrayList<FuncParamList>, withRegistryId: Bool): ArgsList {
        let result = ArgsList()
        if (withRegistryId) {
            result.add((INT64_T, SELF_NAME + "." + REGISTRY_ID))
        }
        if (!paramLists.isEmpty()) {
            for (cur in paramLists[0].params) {
                var name = cur.identifier.Val()
                name = GenerateArgumentCast(cur.GetTy().getOrThrow(), name)
                result.add((MapCJTypeToObjCType(typedefs, Some(cur)), name))
            }
        }
        return result
    }

    public static func ConvertParamsListToArgsListToString(paramLists: ArrayList<FuncParamList>,
        withRegistryId: Bool): String {
        let result = StringBuilder()
        if (withRegistryId) {
            result.append(SELF_NAME + "." + REGISTRY_ID)
        }
        if (!paramLists.isEmpty()) {
            if (withRegistryId && !paramLists[0].params.isEmpty()) {
                result.append(", ")
            }
            for (idx in 0..paramLists[0].params.size) {
                let cur = paramLists[0].params[idx]
                result.append(GenerateArgumentCast(cur.GetTy().getOrThrow(), cur.identifier.Val()))
                if (idx + 1 < paramLists[0].params.size) {
                    result.append(", ")
                }
            }
        }
        return result.toString()
    }

    public static func ConvertParamsListToCallableParamsString(paramLists: ArrayList<FuncParamList>,
        withSelf: Bool): ArrayList<String> {
        let result = ArrayList<String>()
        if (withSelf) {
            result.add(CAST_TO_VOID_PTR + SELF_NAME)
        }
        if (!paramLists.isEmpty()) {
            for (cur in paramLists[0].params) {
                result.add(GenerateArgumentCast(cur.GetTy().getOrThrow(), cur.identifier.Val()))
            }
        }
        return result
    }

    public static func MapCJTypeToObjCType(typedefs: HashSet<String>, ty: Ty): String {
        let objctype = TypeMapper.Cj2ObjCForObjC(ty)
        if (!objctype.decl.isEmpty()) {
            typedefs.add(objctype.decl)
        }
        return objctype.usage
    }

    public static func MapCJTypeToObjCType(typedefs: HashSet<String>, `type`: Option<Type>): String {
        if (let None <- `type`) {
            return UNSUPPORTED_TYPE
        }
        return MapCJTypeToObjCType(typedefs, `type`.getOrThrow().GetTy().getOrThrow())
    }

    public static func MapCJTypeToObjCType(typedefs: HashSet<String>, param: Option<FuncParam>): String {
        if (let None <- param) {
            return UNSUPPORTED_TYPE
        }
        return MapCJTypeToObjCType(typedefs,
            param.getOrThrow().typeNode.getOrThrow().GetTy().getOrThrow())
    }

    public static func GenerateArgumentCast(retTy: Ty, value: String): String {
        if (TypeMapper.IsObjCCJMapping(retTy)) {
            return value + "." + REGISTRY_ID
        }
        let actualTy = if (retTy.IsCoreOptionType()) { retTy.typeArgs[0] } else { retTy }
        if (TypeMapper.IsObjCImpl(actualTy)) {
            return CAST_TO_VOID_PTR + value
        }
        if (TypeMapper.IsObjCMirror(actualTy) || TypeMapper.IsObjCBlock(actualTy) ||
            TypeMapper.IsObjCCJMappingInterface(actualTy)) {
            return CAST_TO_VOID_PTR_RETAINED + value
        }
        if (TypeMapper.IsObjCPointer(actualTy)) {
            return CAST_TO_VOID_PTR_UNSAFE + value
        }
        return value
    }

    public static func GetGetterForProp(`prop`: EmittableObjCPropMetainfo, getterName: String,
        getterWrapperName: String, bridge: Bool): EmittableObjCFuncMetainfo {
        var getter = EmittableObjCFuncMetainfo()
        getter.isStatic = `prop`.isStatic
        getter.selectorComponents = ArrayList<String>()
        getter.identifier = getterName
        getter.mangledIdentifier = getterWrapperName
        getter.retType = `prop`.`type`
        getter.paramsDecl = ""
        getter.paramStaticRef = if (`prop`.isStatic) { "" } else { INT64_T }
        getter.callingParams = if (`prop`.isStatic) { "" } else { SELF_NAME + "." + REGISTRY_ID }
        getter.convertedParams = if (`prop`.isStatic) { "" } else { SELF_NAME + "." + REGISTRY_ID }
        getter.bridge = bridge
        return getter
    }

    public static func GetSetterForProp(`prop`: EmittableObjCPropMetainfo, ty: Ty, getterName: String,
        getterWrapperName: String): EmittableObjCFuncMetainfo {
        var setter = EmittableObjCFuncMetainfo()
        setter.isStatic = `prop`.isStatic
        setter.selectorComponents = ArrayList<String>()
        setter.identifier = getterName
        setter.mangledIdentifier = getterWrapperName
        setter.retType = VOID_TYPE
        setter.bridge = false
        setter.paramsDecl = "(" + `prop`.`type` + ")" + SETTER_PARAM_NAME
        setter.paramStaticRef = (if (!`prop`.isStatic) { "(" + INT64_T + "," } else { "(" }) +
            `prop`.`type` + ")"
        setter.callingParams = if (!`prop`.isStatic) {
            SELF_NAME + "." + REGISTRY_ID + ", " + SETTER_PARAM_NAME
        } else {
            SETTER_PARAM_NAME
        }
        setter.convertedParams = (if (!`prop`.isStatic) { SELF_NAME + "." + REGISTRY_ID + ", " } else { "" }) +
            GenerateArgumentCast(ty, SETTER_PARAM_NAME)
        return setter
    }
}
