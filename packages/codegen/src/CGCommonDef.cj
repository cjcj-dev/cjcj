package cjcj::codegen

import std.collection.*
import cjcj::basic.Linkage
import cjcj::chir.GenericType
import cjcj::chir.TypeKind

public let INTEGER_CONVERT_MAP = HashMap<TypeKind, TypeKind>([
    (TypeKind.TYPE_UINT8, TypeKind.TYPE_INT8),
    (TypeKind.TYPE_UINT16, TypeKind.TYPE_INT16),
    (TypeKind.TYPE_UINT32, TypeKind.TYPE_INT32),
    (TypeKind.TYPE_UINT64, TypeKind.TYPE_INT64),
    (TypeKind.TYPE_UINT_NATIVE, TypeKind.TYPE_INT_NATIVE)
])

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
        case Linkage.EXTERNAL_WEAK => LLVMLinkage.External
    }
}

public func AddLinkageTypeMetadata(globalObject: LLVMValueRef, linkageType: LLVMLinkage, markByMD: Bool): Unit {
    if (!markByMD) {
        unsafe { LLVMSetLinkage(globalObject, LLVMLinkageValue(linkageType)) }
        return
    }
    let linkageTypeStr = match (linkageType) {
        case LLVMLinkage.External => "ExternalLinkage"
        case LLVMLinkage.AvailableExternally => "AvailableExternallyLinkage"
        case LLVMLinkage.LinkOnceAny => "LinkOnceAnyLinkage"
        case LLVMLinkage.LinkOnceODR => "LinkOnceODRLinkage"
        case LLVMLinkage.WeakAny => "WeakAnyLinkage"
        case LLVMLinkage.WeakODR => "WeakODRLinkage"
        case LLVMLinkage.Appending => "AppendingLinkage"
        case LLVMLinkage.Internal => "InternalLinkage"
        case LLVMLinkage.Private => "PrivateLinkage"
        case LLVMLinkage.ExternalWeak => "ExternalWeakLinkage"
        case LLVMLinkage.Common => "CommonLinkage"
    }
    let context = LLVMContextHandle(unsafe { LLVMGetTypeContext(LLVMTypeOf(globalObject)) }, owned: false)
    LLVMSetGlobalStringMetadata(context, globalObject, "LinkageType", linkageTypeStr)
}

public func GetLinkageTypeOfGlobalObject(globalObject: LLVMValueRef): LLVMLinkage {
    let context = LLVMContextHandle(unsafe { LLVMGetTypeContext(LLVMTypeOf(globalObject)) }, owned: false)
    let kindID = LLVMGetMDKindID(context, "LinkageType")
    if (kindID != 0u32) {
        try (countPtr = LibC.malloc<UIntNative>().asResource()) {
            unsafe { countPtr.value.write(UIntNative(0)) }
            let entries = unsafe { LLVMGlobalCopyAllMetadata(globalObject, countPtr.value) }
            let count = unsafe { countPtr.value.read() }
            if (!entries.isNull()) {
                var idx: UInt32 = 0u32
                while (idx < UInt32(count)) {
                    if (unsafe { LLVMValueMetadataEntriesGetKind(entries, idx) } == kindID) {
                        let metadata = unsafe { LLVMValueMetadataEntriesGetMetadata(entries, idx) }
                        let operands = LLVMGetMDNodeOperands(LLVMMetadataToValue(context, metadata))
                        unsafe { LLVMDisposeValueMetadataEntries(entries) }
                        if (!operands.isEmpty()) {
                            if (let Some(linkageTypeStr) <- LLVMGetMDStringValue(operands[0])) {
                                return match (linkageTypeStr) {
                                    case "ExternalLinkage" => LLVMLinkage.External
                                    case "AvailableExternallyLinkage" => LLVMLinkage.AvailableExternally
                                    case "LinkOnceAnyLinkage" => LLVMLinkage.LinkOnceAny
                                    case "LinkOnceODRLinkage" => LLVMLinkage.LinkOnceODR
                                    case "WeakAnyLinkage" => LLVMLinkage.WeakAny
                                    case "WeakODRLinkage" => LLVMLinkage.WeakODR
                                    case "AppendingLinkage" => LLVMLinkage.Appending
                                    case "InternalLinkage" => LLVMLinkage.Internal
                                    case "PrivateLinkage" => LLVMLinkage.Private
                                    case "ExternalWeakLinkage" => LLVMLinkage.ExternalWeak
                                    case "CommonLinkage" => LLVMLinkage.Common
                                    case _ => throw IllegalArgumentException("unexpected LinkageType metadata: " +
                                        linkageTypeStr)
                                }
                            }
                        }
                        throw IllegalArgumentException("unexpected LinkageType metadata")
                    }
                    idx++
                }
                unsafe { LLVMDisposeValueMetadataEntries(entries) }
            }
        }
    }
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
