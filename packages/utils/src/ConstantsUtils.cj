package cjcj::utils

public enum OverflowStrategy {
    | NA
    | CHECKED
    | WRAPPING
    | THROWING
    | SATURATING
    | OVERFLOW_STRATEGY_END
}

public func OverflowStrategyIndex(strategy: OverflowStrategy): Int64 {
    return match (strategy) {
        case OverflowStrategy.NA => 0
        case OverflowStrategy.CHECKED => 1
        case OverflowStrategy.WRAPPING => 2
        case OverflowStrategy.THROWING => 3
        case OverflowStrategy.SATURATING => 4
        case OverflowStrategy.OVERFLOW_STRATEGY_END => 5
    }
}

extend OverflowStrategy <: Equatable<OverflowStrategy> {
    public operator func ==(right: OverflowStrategy): Bool {
        return OverflowStrategyIndex(this) == OverflowStrategyIndex(right)
    }

    public operator func !=(right: OverflowStrategy): Bool {
        return !(this == right)
    }
}

public let MAIN_INVOKE: String = "$mainInvoke"
public let TEST_ENTRY_NAME: String = "$test.entry"
public let BOX_DECL_PREFIX: String = "$BOX_"
public let STATIC_INIT_VAR: String = "$init"
public let STATIC_INIT_FUNC: String = "static.init"
public let TO_ANY: String = "$toAny"

public let ITER_COMPILER: String = "iter-compiler"
public let V_COMPILER: String = "v-compiler"
public let INVALID_IDENTIFIER: String = "<invalid identifier>"
public let RESOURCE_NAME: String = "v-freshExc"
public let CANGJIE_HOME: String = "CANGJIE_HOME"

public let SERIALIZED_FILE_EXTENSION: String = ".cjo"
public let SERIALIZED_FILE_FLAG_EXTENSION: String = ".cjo.flag"
public let CJ_D_FILE_EXTENSION: String = ".cj.d"
public let FULL_BCHIR_SERIALIZED_FILE_EXTENSION: String = ".full.bchir"
public let BCHIR_SERIALIZED_FILE_EXTENSION: String = ".bchir"
public let CACHED_AST_EXTENSION: String = ".cachedast"
public let CACHED_LOG_EXTENSION: String = ".log"
public let CHIR_SERIALIZATION_FILE_EXTENSION: String = ".chir"
public let CHIR_READABLE_FILE_EXTENSION: String = ".chirtxt"

public let CLASS_EXCEPTION: String = "Exception"
public let CLASS_ERROR: String = "Error"
public let CLASS_COMMAND: String = "Command"
public let CLASS_HANDLER_FRAME: String = "HandlerFrame"
public let CLASS_IMMEDIATE_FRAME: String = "ImmediateFrame"
public let CLASS_FRAME_EXCEPTION_WRAPPER: String = "ImmediateFrameExceptionWrapper"
public let CLASS_FRAME_ERROR_WRAPPER: String = "ImmediateFrameErrorWrapper"
public let CLASS_EARLY_RETURN: String = "ImmediateEarlyReturn"
public let OPTION_NAME: String = "Option"
public let OPTION_VALUE_CTOR: String = "Some"
public let OPTION_NONE_CTOR: String = "None"
public let ANY_NAME: String = "Any"
public let OBJECT_NAME: String = "Object"
public let OCOBJECT_NAME: String = "NSObject"
public let CTYPE_NAME: String = "CType"
public let RAW_ARRAY_NAME: String = "RawArray"
public let CPOINTER_NAME: String = "CPointer"
public let CSTRING_NAME: String = "CString"
public let CFUNC_NAME: String = "CFunc"
public let VARRAY_NAME: String = "VArray"
public let TOSTRING_NAME: String = "ToString"

public let MACRO_DEF_NUM: Int64 = 2
public let MC_EXCEPTION: String = "MacroContextException"
public let MACRO_COMMON_ARGS: Int64 = 1
public let MACRO_ATTR_ARGS: Int64 = 2
public let MACRO_OBJECT_NAME: String = "MACRO_OBJECT"
public let IF_AVAILABLE: String = "IfAvailable"

public let DEFAULT_PACKAGE_NAME: String = "default"
public let CORE_PACKAGE_NAME: String = "std.core"
public let SYNC_PACKAGE_NAME: String = "std.sync"
public let MATH_PACKAGE_NAME: String = "std.math"
public let OVERFLOW_PACKAGE_NAME: String = "std.overflow"
public let RUNTIME_PACKAGE_NAME: String = "std.runtime"
public let UNITTEST_MOCK_INTERNAL_PACKAGE_NAME: String = "std.unittest.mock.internal"
public let AST_PACKAGE_NAME: String = "std.ast"
public let INTEROP_PACKAGE_NAME: String = "std.interop"
public let NET_PACKAGE_NAME: String = "std.net"
public let REFLECT_PACKAGE_NAME: String = "std.reflect"
public let REF_PACKAGE_NAME: String = "std.ref"
public let EFFECT_INTERNALS_PACKAGE_NAME: String = "stdx.effect"
public let EFFECT_PACKAGE_NAME: String = "stdx.effect"

public let STD_LIB_ARRAY: String = "Array"
public let STD_LIB_FUTURE: String = "Future"
public let STD_LIB_MONITOR: String = "Monitor"
public let STD_LIB_MUTEX: String = "Mutex"
public let STD_LIB_OPTION: String = "Option"
public let STD_LIB_STRING: String = "String"
public let STD_LIB_WAIT_QUEUE: String = "WaitQueue"
public let STD_LIB_WEAK_REF: String = "WeakRef"

public let ANNOTATION_VAR_POSTFIX: String = "@Annotation@"
public let CC_DEF_PREFIX: String = "$C"
public let GENERIC_VIRTUAL_FUNC: String = "$GenericVirtualFunc"
public let INST_VIRTUAL_FUNC: String = "$InstVirtualFunc"
public let CFFI_FUNC_SUFFIX: String = "$real"
public let HAS_INITED_IDENT: String = "$hasInited"

public let INTEROP_JOBJECT_NAME: String = "JObject"
public let INTEROP_JSTRING_NAME: String = "JString"
public let INTEROP_JARRAY_NAME: String = "JArray"
public let INTEROP_JAVA_LANG_PACKAGE: String = "java.lang"
public let JAVA_REF_FIELD_NAME: String = "$javaref"
public let JAVA_FWD_CLASS_SUFFIX: String = "_fwd"
public let JAVA_INTERFACE_FWD_CLASS_DEFAULT_METHOD_SUFFIX: String = "_default_impl"
public let JAVA_SELF_OBJECT: String = "selfobj"
public let JAVA_REF_GETTER_FUNC_NAME: String = "$getJavaRef"
public let INTEROPLIB_CFFI_JAVA_ENTITY: String = "Java_CFFI_JavaEntity"
public let JAVA_OBJECT_CONTROLLER: String = "JavaObjectController"
public let JAVA_OBJECT_CONTROLLER_NAME: String = "controller"
public let JAVA_OVERRIDE_MASK_NAME: String = "overrideMask"
public let ENV: String = "env"

public let OBJ_C_ID_IDENT: String = "ObjCId"
public let OBJ_C_POINTER_IDENT: String = "ObjCPointer"
public let OBJ_C_FUNC_IDENT: String = "ObjCFunc"
public let OBJ_C_BLOCK_IDENT: String = "ObjCBlock"
public let OBJ_C_LANG_PACKAGE_IDENT: String = "objc.lang"
public let NATIVE_HANDLE_IDENT: String = "$obj"
public let GET_OBJ_C_CLASS_IDENT: String = "$getObjCClass"
public let REGISTRY_ID_IDENT: String = "$registryId"
public let REGISTRY_ID_SETTER_SELECTOR: String = "set$registryId:"
public let SYNTHETIC_CLASS_SUFFIX: String = "$impl"
public let NATIVE_HANDLE_GETTER_IDENT: String = "$getObj"
public let OBJ_C_FWD_CLASS_SUFFIX: String = "_fwd"

public let GET_TYPE_FOR_TYPE_PARAMETER_FUNC_NAME: String = "getTypeForTypeParameter"
public let IS_SUBTYPE_TYPES_FUNC_NAME: String = "isSubtypeTypes"
public let ORG_NAME_SEPARATOR: String = "@"
