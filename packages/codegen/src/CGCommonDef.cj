package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::basic.Linkage
import cangjie_compiler::chir.GenericType

public enum TypeInfoFields {
    | TYPEINFO_NAME
    | TYPEINFO_TYPE_KIND
    | TYPEINFO_FLAG
    | TYPEINFO_FIELDS_NUM
    | TYPEINFO_SIZE
    | TYPEINFO_GC_TIB
    | TYPEINFO_UUID
    | TYPEINFO_ALIGN
    | TYPEINFO_TYPE_ARGS_NUM
    | TYPEINFO_INHERITED_CLASS_NUM
    | TYPEINFO_OFFSETS
    | TYPEINFO_SOURCE_GENERIC
    | TYPEINFO_TYPE_ARGS
    | TYPEINFO_FIELDS
    | TYPEINFO_SUPER
    | TYPEINFO_EXTENSIONDEF_PTR
    | TYPEINFO_MTABLE
    | TYPEINFO_REFLECTION
    | TYPE_INFO_FIELDS_NUM
}

public enum GenericTypeInfoFields {
    | GENERIC_TYPEINFO_NAME
    | GENERIC_TYPEINFO_TYPE_KIND
    | GENERIC_TYPEINFO_UPPERBOUNDS_NUM
    | GENERIC_TYPEINFO_UPPERBOUNDS
    | GENERIC_TYPE_INFO_FIELDS_NUM
}

public enum GenericCustomTypeInfoFields {
    | GENERIC_CUSTOM_TYPEINFO_NAME
    | GENERIC_CUSTOM_TYPEINFO_TYPE_KIND
    | GENERIC_CUSTOM_TYPEINFO_TYPE_ARGS_NUM
    | GENERIC_CUSTOM_TYPEINFO_TYPE_ARGS
    | GENERIC_CUSTOM_TYPEINFO_SOURCE_GENERIC
    | GENERIC_CUSTOM_TYPE_INFO_FIELDS_NUM
}

public enum TypeTemplateFields {
    | TYPETEMPLATE_NAME
    | TYPETEMPLATE_TYPE_KIND
    | TYPETEMPLATE_FLAG
    | TYPETEMPLATE_FIELDS_NUM
    | TYPETEMPLATE_TYPE_ARGS_NUM
    | TYPETEMPLATE_FIELDS_FNS
    | TYPETEMPLATE_SUPER_FN
    | TYPETEMPLATE_FINALIZER
    | TYPETEMPLATE_REFLECTION
    | TYPETEMPLATE_EXTENSIONDEF_PTR
    | TYPETEMPLATE_INHERITED_CLASS_NUM
    | TYPE_TEMPLATE_FIELDS_NUM
}

public enum ExtensionDefFields {
    | TYPE_PARAM_COUNT
    | IS_INTERFACE_TI
    | FLAG
    | FUNC_TABLE_SIZE
    | TARGET_TYPE
    | INTERFACE_FN_OR_INTERFACE_TI
    | WHERE_CONDITION_FN
    | FUNC_TABLE
    | EXTENSION_DEF_FIELDS_NUM
}

public enum ArrayBaseFields {
    | ARRAY_BASE_ARRAY_LEN
    | ARRAY_BASE_FIELDS_NUM
}

public enum BitMapFields {
    | BITMAP_NUMS
    | BITMAP_BITMAP
    | BITMAP_FIELDS_NUM
}

public class IntrinsicFuncInfo {
    public let funcName: String
    public let attributes: ArrayList<String> = ArrayList<String>()

    public init(funcName: String, attributes: Array<String>) {
        this.funcName = funcName
        for (attr in attributes) {
            this.attributes.add(attr)
        }
    }
}

public class GenericTypeAndPath {
    public let genericType: GenericType
    public let path: ArrayList<Int64> = ArrayList<Int64>()

    public init(genericType: GenericType, path: ArrayList<Int64>) {
        this.genericType = genericType
        for (value in path) {
            this.path.add(value)
        }
    }

    public func GetPath(): ArrayList<Int64> {
        return path.clone()
    }
}

public func IsCHIRWrapper(chirFuncName: String): Bool {
    return chirFuncName.endsWith("$withoutTI") || chirFuncName.contains("wrapper")
}

public func CHIRLinkage2LLVMLinkage(chirLinkage: Linkage): LLVMLinkage {
    return match (chirLinkage) {
        case Linkage.WEAK_ODR => LLVMLinkage.WeakODR
        case Linkage.EXTERNAL => LLVMLinkage.External
        case Linkage.INTERNAL => LLVMLinkage.Internal
        case Linkage.LINKONCE_ODR => LLVMLinkage.LinkOnceODR
        case Linkage.EXTERNAL_WEAK => LLVMLinkage.ExternalWeak
    }
}

public func AddLinkageTypeMetadata(globalObject: LLVMValueRef, linkageType: LLVMLinkage, markByMD: Bool): Unit {
    if (!markByMD) {
        unsafe { LLVMSetLinkage(globalObject, LLVMLinkageValue(linkageType)) }
    }
}

public func GetLinkageTypeOfGlobalObject(globalObject: LLVMValueRef): LLVMLinkage {
    let linkage = unsafe { LLVMGetLinkage(globalObject) }
    return match (linkage) {
        case 0 => LLVMLinkage.External
        case 1 => LLVMLinkage.AvailableExternally
        case 2 => LLVMLinkage.LinkOnceAny
        case 3 => LLVMLinkage.LinkOnceODR
        case 5 => LLVMLinkage.WeakAny
        case 6 => LLVMLinkage.WeakODR
        case 7 => LLVMLinkage.Appending
        case 8 => LLVMLinkage.Internal
        case 9 => LLVMLinkage.Private
        case 12 => LLVMLinkage.ExternalWeak
        case 14 => LLVMLinkage.Common
        case _ => LLVMLinkage.External
    }
}
