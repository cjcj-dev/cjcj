package cjcj::codegen

import std.collection.*
import std.sort.*
import cjcj::chir.AnnoInfo
import cjcj::chir.Attribute
import cjcj::chir.AttributeInfo
import cjcj::chir.ClassDef
import cjcj::chir.ClassType
import cjcj::chir.CustomTypeDef
import cjcj::chir.EnumDef
import cjcj::chir.EnumType
import cjcj::chir.FuncType
import cjcj::chir.Function
import cjcj::chir.GenericType
import cjcj::chir.GlobalVar
import cjcj::chir.MemberVarInfo
import cjcj::chir.Parameter
import cjcj::chir.StructDef
import cjcj::chir.Type
import cjcj::chir.GetTypeQualifiedName
import cjcj::utils.{BOX_DECL_PREFIX, CORE_PACKAGE_NAME, SplitQualifiedName, StaticCast}

private let PRIMITIVE_TIS: Array<String> = [
    "Nothing.ti", "Unit.ti", "Bool.ti", "Rune.ti", "UInt8.ti", "UInt16.ti",
    "UInt32.ti", "UInt64.ti", "UIntNative.ti", "Int8.ti", "Int16.ti", "Int32.ti", "Int64.ti", "IntNative.ti",
    "Float16.ti", "Float32.ti", "Float64.ti", "CString.ti"]
private let PRIMITIVE_TTS: Array<String> = [
    "Tuple.tt", "VArray.tt", "RawArray.tt", "CPointer.tt", "CFunc.tt", "Closure.tt"]

private enum MetadataKind {
    | PKG_METADATA | STRUCT_METADATA | CLASS_METADATA | ENUM_METADATA | GV_METADATA | GF_METADATA | COUNT
}

private enum GenReflectMode {
    | NO_REFLECT | FULL_REFLECT
}

private func GenReflectModeIndex(mode: GenReflectMode): Int64 {
    return match (mode) {
        case GenReflectMode.NO_REFLECT => 0
        case GenReflectMode.FULL_REFLECT => 1
    }
}

extend GenReflectMode <: Equatable<GenReflectMode> {
    public operator func ==(right: GenReflectMode): Bool {
        return GenReflectModeIndex(this) == GenReflectModeIndex(right)
    }

    public operator func !=(right: GenReflectMode): Bool {
        return !(this == right)
    }
}

private enum ExtraAttribute {
    | MUTABLE_FIELD | IMMUTABLE_FIELD | INTERFACE | CLASS | STRUCT | ENUM | METHOD | BOX_CLASS | METHOD_FROM_INTERFACE
}

private enum SRetMode {
    | SRET_NON_GENERIC | SRET_GENERIC | SRET_KNOWN_GENERIC_CUSTOM | SRET_UNKNOWN_GENERIC_CUSTOM | NO_SRET
}

private func SRetModeIndex(mode: SRetMode): UInt8 {
    return match (mode) {
        case SRetMode.SRET_NON_GENERIC => 0u8
        case SRetMode.SRET_GENERIC => 1u8
        case SRetMode.SRET_KNOWN_GENERIC_CUSTOM => 2u8
        case SRetMode.SRET_UNKNOWN_GENERIC_CUSTOM => 3u8
        case SRetMode.NO_SRET => 4u8
    }
}

extend SRetMode <: Equatable<SRetMode> {
    public operator func ==(right: SRetMode): Bool {
        return SRetModeIndex(this) == SRetModeIndex(right)
    }

    public operator func !=(right: SRetMode): Bool {
        return !(this == right)
    }
}

private class MetadataVector {
    private let llvmCtx: LLVMContextHandle
    private let data: ArrayList<LLVMMetadataRef> = ArrayList<LLVMMetadataRef>()

    public init(llvmCtx: LLVMContextHandle) {
        this.llvmCtx = llvmCtx
    }

    public func Concat(md: LLVMMetadataRef): MetadataVector {
        data.add(md)
        return this
    }

    public func Concat(rawStr: String): MetadataVector {
        data.add(LLVMCreateMDString(llvmCtx, rawStr))
        return this
    }

    public func Concat(num: UInt32): MetadataVector {
        let i32Ty = unsafe { LLVMInt32TypeInContext(llvmCtx.raw) }
        data.add(LLVMValueToMetadata(unsafe { LLVMConstInt(i32Ty, UInt64(num), 0) }))
        return this
    }

    public func AddSubItem(mdVec: MetadataVector): MetadataVector {
        data.add(mdVec.CreateMDTuple())
        return this
    }

    public func CreateMDTuple(): LLVMMetadataRef {
        return LLVMCreateMDTuple(llvmCtx, data)
    }
}

private open class MetadataInfo {
    protected let module: CGModule
    protected let subCHIRPkg: SubCHIRPackage
    protected let reflectionMode: GenReflectMode

    public init(cgMod: CGModule, subCHIRPkg: SubCHIRPackage, reflectionMode: GenReflectMode) {
        module = cgMod
        this.subCHIRPkg = subCHIRPkg
        this.reflectionMode = reflectionMode
    }

    public open func Gen(): Unit {}

    protected func GenerateParametersMetadata(argsInfo: ArrayList<Parameter>, hasThis!: Bool = false): LLVMMetadataRef {
        let llvmCtx = module.GetLLVMContext()
        let res = MetadataVector(llvmCtx)
        var idx: Int64 = 0
        while (idx < argsInfo.size) {
            let arg = argsInfo[idx]
            if (idx == 0 && hasThis) {
                idx++
                continue
            }
            res.AddSubItem(MetadataVector(llvmCtx)
                .Concat(arg.GetSrcCodeIdentifier())
                .Concat(GetTiName(arg.GetType().getOrThrow()))
                .Concat(GenerateAttrsMetadata(AttributeInfo(), ExtraAttribute.METHOD, arg.GetAnnoInfo())))
            idx++
        }
        return res.CreateMDTuple()
    }

    protected func GenerateParametersMetadata(genericParamInfos: ArrayList<GenericType>): LLVMMetadataRef {
        let llvmCtx = module.GetLLVMContext()
        let res = MetadataVector(llvmCtx)
        for (arg in genericParamInfos) {
            res.Concat(GetTiName(arg))
        }
        return res.CreateMDTuple()
    }

    protected func GenerateAttrsMetadata(attrs: AttributeInfo, extraAttr: ExtraAttribute, annoInfo: AnnoInfo,
        hasSRetMode!: SRetMode = SRetMode.NO_SRET, enumKind!: String = "", isUnknownSize!: Bool = false):
        LLVMMetadataRef {
        let attrsStr = HashSet<String>()
        match (extraAttr) {
            case ExtraAttribute.METHOD_FROM_INTERFACE => attrsStr.add("abstract")
            case ExtraAttribute.IMMUTABLE_FIELD => attrsStr.add(ATTR_IMMUTABLE)
            case ExtraAttribute.INTERFACE => attrsStr.add(METADATA_ATTR_OPEN)
            case ExtraAttribute.ENUM => attrsStr.add(enumKind)
            case ExtraAttribute.BOX_CLASS => attrsStr.add("box")
            case _ => ()
        }
        attrsStr.add("reflectVersion1")
        if (hasSRetMode != SRetMode.NO_SRET) {
            attrsStr.add("hasSRet" + SRetModeIndex(hasSRetMode).toString())
        }
        if (isUnknownSize) {
            attrsStr.add("unknownSize")
        }
        AddTestAttrs(attrsStr, attrs)
        let ops = MetadataVector(module.GetLLVMContext())
        let orderedAttrs = ArrayList<String>()
        for (attr in attrsStr) {
            orderedAttrs.add(attr)
        }
        sort(orderedAttrs, by: { left: String, right: String => CompareMetadataString(left, right) })
        for (attr in orderedAttrs) {
            ops.Concat(attr)
        }
        let annoFactoryFuncName = annoInfo.GetAnnoFactoryFuncMangledName()
        ops.Concat(annoFactoryFuncName)
        if (annoInfo.IsAvailable()) {
            if (let Some(chirFunc) <- module.GetCGContext().GetCGPkgContext().FindCHIRGlobalValue(annoFactoryFuncName)) {
                module.GetOrInsertCGFunction(chirFunc)
            }
        }
        return ops.CreateMDTuple()
    }

    protected func GetTiName(ty: Type): String {
        if (ty.IsRef()) {
            return GetTiName(ty.StripAllRefs())
        }
        let cgType = CGType.GetOrCreate(module, ty)
        if (ty.IsGenericRelated()) {
            let ti = cgType.GetOrCreateTypeInfo()
            return LLVMCStringToString(unsafe { LLVMGetValueName(ti) }) ?? ""
        }
        if (ty.IsAutoEnvBase() && ty.IsAutoEnvInstBase()) {
            if (let Some(classTy) <- (ty as ClassType)) {
                if (let Some(superClassTy) <- classTy.GetSuperClassTy(builder: Some(module.GetCGContext().GetCHIRBuilder()))) {
                    return GetTiName(superClassTy)
                }
            }
        }
        let tiName = CGType.GetNameOfTypeInfoGV(ty)
        if (let Some(moduleHandle) <- module.GetLLVMModule()) {
            try (nameCString = unsafe { LibC.mallocCString(tiName) }.asResource()) {
                if (unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameCString.value) }.isNull()) {
                    let ti = cgType.GetOrCreateTypeInfo()
                    let realName = LLVMCStringToString(unsafe { LLVMGetValueName(ti) }) ?? ""
                    if (cgType.IsStaticGI()) {
                        module.GetCGContext().RegisterReflectGeneratedStaticGIName(realName)
                    }
                    return realName
                }
            }
        }
        return tiName
    }

    protected func GenerateInstanceFieldMetadata(field: MemberVarInfo, idx: Int64): LLVMMetadataRef {
        let llvmCtx = module.GetLLVMContext()
        return MetadataVector(llvmCtx)
            .Concat(UInt32(idx))
            .Concat(field.name)
            .Concat(GenerateAttrsMetadata(field.attributeInfo,
                if (field.TestAttr(Attribute.READONLY)) { ExtraAttribute.IMMUTABLE_FIELD } else { ExtraAttribute.MUTABLE_FIELD },
                field.annoInfo))
            .CreateMDTuple()
    }

    protected func GenerateStaticFieldMetadata(staticField: GlobalVar): LLVMMetadataRef {
        let llvmCtx = module.GetLLVMContext()
        return MetadataVector(llvmCtx)
            .Concat(staticField.GetSrcCodeIdentifier())
            .Concat(GetTiName(staticField.GetType().getOrThrow()))
            .Concat(staticField.GetIdentifierWithoutPrefix())
            .Concat(GenerateAttrsMetadata(staticField.GetAttributeInfo(),
                if (staticField.TestAttr(Attribute.READONLY)) {
                    ExtraAttribute.IMMUTABLE_FIELD
                } else {
                    ExtraAttribute.MUTABLE_FIELD
                },
                staticField.GetAnnoInfo()))
            .CreateMDTuple()
    }

    protected func GenerateMethodMetadata(method: Function, isFromInterface!: Bool = false): LLVMMetadataRef {
        let llvmCtx = module.GetLLVMContext()
        let funcType = StaticCast<FuncType>(method.GetType().getOrThrow())
        let retTypeInfo = GetTiName(funcType.GetReturnType())
        let methodMD = MetadataVector(llvmCtx)
        methodMD.Concat(method.GetSrcCodeIdentifier())
            .Concat(retTypeInfo)
            .Concat(method.GetIdentifierWithoutPrefix())
        let extraAttr = if (isFromInterface) { ExtraAttribute.METHOD_FROM_INTERFACE } else { ExtraAttribute.METHOD }
        let hasSRetMode = GetSRetMode(funcType.GetReturnType(), module.GetOrInsertCGFunction(method))
        methodMD
            .Concat(if (method.TestAttr(Attribute.STATIC)) {
                GenerateParametersMetadata(method.GetParams())
            } else {
                GenerateParametersMetadata(method.GetParams(), hasThis: true)
            })
            .Concat(GenerateParametersMetadata(method.GetGenericTypeParams()))
            .Concat(GenerateAttrsMetadata(method.GetAttributeInfo(), extraAttr, method.GetAnnoInfo(),
                hasSRetMode: hasSRetMode))
        module.GetOrInsertCGFunction(method)
        return methodMD.CreateMDTuple()
    }
}

private class StructMetadataInfo <: MetadataInfo {
    public init(cgMod: CGModule, subCHIRPkg: SubCHIRPackage, reflectionMode: GenReflectMode) {
        super(cgMod, subCHIRPkg, reflectionMode)
    }

    public override func Gen(): Unit {
        GenerateAllStructsMetadata()
    }

    private func GenerateAllStructsMetadata(): Unit {
        let doneSet = HashSet<String>()
        for (typeDef in subCHIRPkg.chirCustomDefs) {
            if (typeDef.TestAttr(Attribute.GENERIC_INSTANTIATED) || typeDef.TestAttr(Attribute.IMPORTED) ||
                typeDef.TestAttr(Attribute.NON_RECOMPILE) || typeDef.TestAttr(Attribute.NO_REFLECT_INFO) ||
                !typeDef.IsStruct()) {
                continue
            }
            GenerateStructMetadata(StaticCast<StructDef>(typeDef), doneSet)
        }
        for (typeName in doneSet) {
            module.GetCGContext().AddGeneratedStructType(typeName)
        }
    }

    private func GenerateStructMetadata(sd: StructDef, doneSet: HashSet<String>): Unit {
        let typeName = sd.GetIdentifierWithoutPrefix()
        let structTypeName = STRUCT_TYPE_PREFIX + typeName
        if (doneSet.contains(structTypeName)) {
            return
        }

        let moduleHandle = module.GetLLVMModule() ?? return
        let llvmCtx = module.GetLLVMContext()
        let typesMD = if (sd.TestAttr(Attribute.GENERIC)) { METADATA_TYPETEMPLATES } else { METADATA_TYPES }
        LLVMGetOrInsertNamedMetadata(moduleHandle, typesMD)
        let structTy = sd.GetType().getOrThrow()
        let tiOrTTName = if (sd.TestAttr(Attribute.GENERIC)) {
            CGType.GetNameOfTypeTemplateGV(structTy)
        } else {
            CGType.GetNameOfTypeInfoGV(structTy)
        }
        var reflectTIOrTT = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(tiOrTTName) }.asResource()) {
            reflectTIOrTT = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameCString.value) }
        }
        if (reflectTIOrTT.isNull()) {
            return
        }

        if (reflectionMode != GenReflectMode.FULL_REFLECT) {
            let mdTuple = MetadataVector(llvmCtx)
                .Concat(tiOrTTName)
                .Concat(GenerateStructFieldMetadata(sd))
                .CreateMDTuple()
            LLVMAddNamedMetadataOperand(moduleHandle, typesMD, mdTuple)
            LLVMSetGlobalMetadata(llvmCtx, reflectTIOrTT, "Reflection", mdTuple)
            doneSet.add(structTypeName)
            return
        }
        let declaredGenericTi = if (sd.TestAttr(Attribute.GENERIC)) { GetTiName(structTy) } else { "" }

        let methodsVec = ArrayList<LLVMMetadataRef>()
        let staticMethodsVec = ArrayList<LLVMMetadataRef>()
        GenerateStructMethodMetadata(sd, methodsVec, staticMethodsVec)
        let cgType = CGType.GetOrCreate(module, structTy)
        let isUnknownSize = cgType.GetSize().isNone()
        let mdTuple = MetadataVector(llvmCtx)
            .Concat(tiOrTTName)
            .Concat(declaredGenericTi)
            .Concat(GenerateStructFieldMetadata(sd))
            .Concat(GenerateStructStaticFieldMetadata(sd))
            .Concat(LLVMCreateMDTuple(llvmCtx, methodsVec))
            .Concat(LLVMCreateMDTuple(llvmCtx, staticMethodsVec))
            .Concat(GenerateAttrsMetadata(sd.GetAttributeInfo(), ExtraAttribute.STRUCT, sd.GetAnnoInfo(),
                hasSRetMode: SRetMode.NO_SRET, enumKind: "", isUnknownSize: isUnknownSize))
            .CreateMDTuple()

        LLVMAddNamedMetadataOperand(moduleHandle, typesMD, mdTuple)
        LLVMSetGlobalMetadata(llvmCtx, reflectTIOrTT, "Reflection", mdTuple)
        doneSet.add(structTypeName)
    }

    private func GenerateStructFieldMetadata(sd: StructDef): LLVMMetadataRef {
        let llvmCtx = module.GetLLVMContext()
        let fieldsVec = MetadataVector(llvmCtx)
        var idx: Int64 = 0
        for (field in sd.GetAllInstanceVars()) {
            fieldsVec.Concat(GenerateInstanceFieldMetadata(field, idx))
            idx++
        }
        return fieldsVec.CreateMDTuple()
    }

    private func GenerateStructStaticFieldMetadata(sd: StructDef): LLVMMetadataRef {
        let llvmCtx = module.GetLLVMContext()
        let staticFieldsVec = MetadataVector(llvmCtx)
        for (staticField in sd.GetStaticMemberVars()) {
            staticFieldsVec.Concat(GenerateStaticFieldMetadata(staticField))
            module.GetOrInsertGlobalVariable(staticField)
        }
        return staticFieldsVec.CreateMDTuple()
    }

    private func GenerateStructMethodMetadata(sd: StructDef, methodsVec: ArrayList<LLVMMetadataRef>,
        staticMethodsVec: ArrayList<LLVMMetadataRef>): Unit {
        for (method in sd.GetMethods()) {
            if (method.TestAttr(Attribute.NO_REFLECT_INFO) || method.TestAttr(Attribute.IMPORTED)) {
                continue
            }
            let methodMD = GenerateMethodMetadata(method)
            module.GetOrInsertCGFunction(method)
            if (method.TestAttr(Attribute.STATIC)) {
                staticMethodsVec.add(methodMD)
            } else {
                methodsVec.add(methodMD)
            }
        }
    }
}

private class ClassMetadataInfo <: MetadataInfo {
    public init(cgMod: CGModule, subCHIRPkg: SubCHIRPackage, reflectionMode: GenReflectMode) {
        super(cgMod, subCHIRPkg, reflectionMode)
    }

    public override func Gen(): Unit {
        GenerateAllClassesMetadata()
    }

    private func GenerateAllClassesMetadata(): Unit {
        for (typeDef in subCHIRPkg.chirCustomDefs) {
            if (typeDef.TestAttr(Attribute.GENERIC_INSTANTIATED) || typeDef.TestAttr(Attribute.NON_RECOMPILE) ||
                typeDef.TestAttr(Attribute.IMPORTED) || !typeDef.IsClassLike()) {
                continue
            }
            GenerateClassLikeMetadata(StaticCast<ClassDef>(typeDef))
        }
    }

    private func GenerateClassLikeMetadata(cd: ClassDef): Unit {
        if (cd.TestAttr(Attribute.NO_REFLECT_INFO) && !IsClassForBoxType(cd.GetSrcCodeIdentifier())) {
            return
        }

        let moduleHandle = module.GetLLVMModule() ?? return
        let llvmCtx = module.GetLLVMContext()
        let typesMD = if (cd.TestAttr(Attribute.GENERIC)) { METADATA_TYPETEMPLATES } else { METADATA_TYPES }
        LLVMGetOrInsertNamedMetadata(moduleHandle, typesMD)
        let classTy = cd.GetType().getOrThrow()
        let tiOrTTName = if (cd.TestAttr(Attribute.GENERIC)) {
            CGType.GetNameOfTypeTemplateGV(classTy)
        } else {
            CGType.GetNameOfTypeInfoGV(classTy)
        }
        var reflectTIOrTT = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(tiOrTTName) }.asResource()) {
            reflectTIOrTT = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameCString.value) }
        }
        if (reflectTIOrTT.isNull()) {
            return
        }
        if (reflectionMode != GenReflectMode.FULL_REFLECT) {
            let mdTuple = MetadataVector(llvmCtx)
                .Concat(tiOrTTName)
                .Concat(GenerateClassLikeFieldMetadata(cd))
                .CreateMDTuple()
            LLVMAddNamedMetadataOperand(moduleHandle, typesMD, mdTuple)
            LLVMSetGlobalMetadata(llvmCtx, reflectTIOrTT, "Reflection", mdTuple)
            return
        }
        let declaredGenericTi = if (cd.TestAttr(Attribute.GENERIC)) { GetTiName(classTy) } else { "" }

        let methodsVec = ArrayList<LLVMMetadataRef>()
        let staticMethodsVec = ArrayList<LLVMMetadataRef>()
        GenerateClassLikeMethodMetadata(cd, methodsVec, staticMethodsVec)

        let mdTuple = MetadataVector(llvmCtx)
            .Concat(tiOrTTName)
            .Concat(declaredGenericTi)
            .Concat(GenerateClassLikeFieldMetadata(cd))
            .Concat(GenerateClassLikeStaticFieldMetadata(cd))
            .Concat(LLVMCreateMDTuple(llvmCtx, methodsVec))
            .Concat(LLVMCreateMDTuple(llvmCtx, staticMethodsVec))
            .Concat(GenerateClassLikeTypeAttrsMetadata(cd))
            .CreateMDTuple()
        LLVMAddNamedMetadataOperand(moduleHandle, typesMD, mdTuple)
        LLVMSetGlobalMetadata(llvmCtx, reflectTIOrTT, "Reflection", mdTuple)
    }

    private func GenerateClassLikeMethodMetadata(cd: ClassDef, methodsVec: ArrayList<LLVMMetadataRef>,
        staticMethodsVec: ArrayList<LLVMMetadataRef>): Unit {
        if (IsClassForBoxType(cd.GetSrcCodeIdentifier())) {
            return
        }
        for (method in cd.GetMethods()) {
            if (method.TestAttr(Attribute.NO_REFLECT_INFO)) {
                continue
            }
            let methodMD = if (method.IsPureAbstract()) {
                GenerateClassAbsMethodMetadata(method)
            } else {
                GenerateMethodMetadata(method, isFromInterface: cd.IsInterface())
            }
            if (method.TestAttr(Attribute.STATIC)) {
                staticMethodsVec.add(methodMD)
            } else {
                methodsVec.add(methodMD)
            }
        }
    }

    private func GenerateClassAbsMethodMetadata(absMethod: Function): LLVMMetadataRef {
        let llvmCtx = module.GetLLVMContext()
        let funcTy = absMethod.GetFuncType().getOrThrow()
        let attr = AttributeInfo()
        attr.CopyFrom(absMethod.GetAttributeInfo())
        if (!absMethod.TestAttr(Attribute.STATIC)) {
            attr.Enable(Attribute.VIRTUAL)
        }
        let retTypeInfo = GetTiName(funcTy.GetReturnType())
        return MetadataVector(llvmCtx)
            .Concat(absMethod.GetSrcCodeIdentifier())
            .Concat(retTypeInfo)
            .Concat("")
            .Concat(GenerateParametersMetadata(absMethod.GetParams(), hasThis: !absMethod.TestAttr(Attribute.STATIC)))
            .Concat(GenerateParametersMetadata(absMethod.GetGenericTypeParams()))
            .Concat(GenerateAttrsMetadata(attr, ExtraAttribute.METHOD, absMethod.GetAnnoInfo()))
            .CreateMDTuple()
    }

    private func GenerateClassLikeStaticFieldMetadata(cd: ClassDef): LLVMMetadataRef {
        let llvmCtx = module.GetCGContext().GetLLVMContext()
        if (cd.IsInterface()) {
            return LLVMCreateMDTuple(llvmCtx, ArrayList<LLVMMetadataRef>())
        }
        let fieldsVec = MetadataVector(llvmCtx)
        for (value in cd.GetStaticMemberVars()) {
            fieldsVec.Concat(GenerateStaticFieldMetadata(value))
            module.GetOrInsertGlobalVariable(value)
        }
        return fieldsVec.CreateMDTuple()
    }

    private func GenerateClassLikeFieldMetadata(cd: ClassDef): LLVMMetadataRef {
        let llvmCtx = module.GetCGContext().GetLLVMContext()
        if (cd.IsInterface()) {
            return LLVMCreateMDTuple(llvmCtx, ArrayList<LLVMMetadataRef>())
        }
        let fieldsVec = MetadataVector(llvmCtx)
        var idx = cd.GetAllInstanceVarNum() - cd.GetDirectInstanceVarNum()
        for (field in cd.GetDirectInstanceVars()) {
            fieldsVec.Concat(GenerateInstanceFieldMetadata(field, idx))
            idx++
        }
        return fieldsVec.CreateMDTuple()
    }

    private func GenerateClassLikeTypeAttrsMetadata(cd: ClassDef): LLVMMetadataRef {
        var metadataType = ExtraAttribute.CLASS
        if (cd.IsInterface()) {
            metadataType = ExtraAttribute.INTERFACE
        }
        if (IsClassForBoxType(cd.GetSrcCodeIdentifier())) {
            metadataType = ExtraAttribute.BOX_CLASS
        }
        return GenerateAttrsMetadata(cd.GetAttributeInfo(), metadataType, cd.GetAnnoInfo())
    }
}

private class PkgMetadataInfo <: MetadataInfo {
    public init(cgMod: CGModule, subCHIRPkg: SubCHIRPackage, reflectionMode: GenReflectMode) {
        super(cgMod, subCHIRPkg, reflectionMode)
    }

    public override func Gen(): Unit {
        GeneratePkgMetadata()
    }

    private func GeneratePkgMetadata(): Unit {
        let moduleHandle = module.GetLLVMModule() ?? return
        let llvmCtx = module.GetLLVMContext()
        let pkgInfo = LLVMGetOrInsertNamedMetadata(moduleHandle, METADATA_PKG)
        if (pkgInfo.isNull()) {
            return
        }
        let names = SplitQualifiedName(module.GetCGContext().GetCurrentPkgName())
        let moduleName = if (names.size > 0) { ReplaceDelimiterAfterOrgName(names[0]) } else { "" }
        let pkgName = ReplaceDelimiterAfterOrgName(module.GetCGContext().GetCurrentPkgName())
        let currentIdx = subCHIRPkg.subCHIRPackageIdx
        let version = ""
        let currentPkgName = if (subCHIRPkg.splitNum == 1) {
            moduleName + "_" + pkgName
        } else {
            moduleName + "_" + pkgName + "_" + currentIdx.toString()
        }
        let nextPkgName = if (currentIdx < subCHIRPkg.splitNum - 1) {
            moduleName + "_" + pkgName + "_" + (currentIdx + 1).toString()
        } else {
            ""
        }
        let flag: UInt32 = if (reflectionMode == GenReflectMode.FULL_REFLECT) { 1u32 } else { 0u32 }
        LLVMAddNamedMetadataOperand(moduleHandle, METADATA_PKG,
            MetadataVector(llvmCtx)
                .Concat(flag)
                .Concat(version)
                .Concat(moduleName)
                .Concat(pkgName)
                .Concat(currentPkgName)
                .Concat(nextPkgName)
                .CreateMDTuple())
        if (pkgName == CORE_PACKAGE_NAME && currentIdx == 0) {
            AddPrimitiveTypeInfoToCorePkgInfo()
        }
    }

    private func AddPrimitiveTypeInfoToCorePkgInfo(): Unit {
        let moduleHandle = module.GetLLVMModule() ?? return
        let llvmCtx = module.GetLLVMContext()
        LLVMGetOrInsertNamedMetadata(moduleHandle, METADATA_PRIMITIVE_TYPES)
        LLVMGetOrInsertNamedMetadata(moduleHandle, METADATA_PRIMITIVE_TYPETEMPLATES)
        let typeTemplateType = CGType.GetOrCreateTypeTemplateType(llvmCtx)
        let typeInfoType = CGType.GetOrCreateTypeInfoType(llvmCtx)
        for (tiName in PRIMITIVE_TIS) {
            let ti = GetOrInsertCodeGenGlobal(module, tiName, typeInfoType)
            addAttribute(ti, GC_KLASS_ATTR)
            LLVMAddNamedMetadataOperand(moduleHandle, METADATA_PRIMITIVE_TYPES,
                MetadataVector(llvmCtx).Concat(tiName).CreateMDTuple())
        }
        for (ttName in PRIMITIVE_TTS) {
            GetOrInsertCodeGenGlobal(module, ttName, typeTemplateType)
            LLVMAddNamedMetadataOperand(moduleHandle, METADATA_PRIMITIVE_TYPETEMPLATES,
                MetadataVector(llvmCtx).Concat(ttName).CreateMDTuple())
        }
    }
}

private class EnumMetadataInfo <: MetadataInfo {
    public init(cgMod: CGModule, subCHIRPkg: SubCHIRPackage, reflectionMode: GenReflectMode) {
        super(cgMod, subCHIRPkg, reflectionMode)
    }

    public override func Gen(): Unit {
        GenerateAllEnumsMetadata()
    }

    private func GenerateAllEnumsMetadata(): Unit {
        for (typeDef in subCHIRPkg.chirCustomDefs) {
            if (typeDef.TestAttr(Attribute.GENERIC_INSTANTIATED) || typeDef.TestAttr(Attribute.NO_REFLECT_INFO) ||
                typeDef.TestAttr(Attribute.NON_RECOMPILE) || typeDef.TestAttr(Attribute.IMPORTED) ||
                !typeDef.IsEnum()) {
                continue
            }
            GenerateEnumMetadata(StaticCast<EnumDef>(typeDef))
        }
    }

    private func GenerateEnumMetadata(ed: EnumDef): Unit {
        let moduleHandle = module.GetLLVMModule() ?? return
        let llvmCtx = module.GetLLVMContext()
        let typesMD = if (ed.TestAttr(Attribute.GENERIC)) { METADATA_TYPETEMPLATES } else { METADATA_TYPES }
        LLVMGetOrInsertNamedMetadata(moduleHandle, typesMD)
        let enumTy = StaticCast<EnumType>(ed.GetType().getOrThrow())
        let tiOrTTName = if (ed.TestAttr(Attribute.GENERIC)) {
            CGType.GetNameOfTypeTemplateGV(enumTy)
        } else {
            CGType.GetNameOfTypeInfoGV(enumTy)
        }
        var reflectTIOrTT = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(tiOrTTName) }.asResource()) {
            reflectTIOrTT = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameCString.value) }
        }
        if (reflectTIOrTT.isNull()) {
            return
        }
        if (reflectionMode != GenReflectMode.FULL_REFLECT) {
            let mdTuple = MetadataVector(llvmCtx)
                .Concat(tiOrTTName)
                .Concat(GenerateEnumConstructorMetadata(ed))
                .Concat(GenerateAttrsMetadata(ed.GetAttributeInfo(), ExtraAttribute.ENUM, ed.GetAnnoInfo(),
                    hasSRetMode: SRetMode.NO_SRET, enumKind: GetEnumKindName(module, ed)))
                .CreateMDTuple()
            LLVMAddNamedMetadataOperand(moduleHandle, typesMD, mdTuple)
            LLVMSetGlobalMetadata(llvmCtx, reflectTIOrTT, "Reflection", mdTuple)
            return
        }
        let declaredGenericTi = if (ed.TestAttr(Attribute.GENERIC)) { GetTiName(enumTy) } else { "" }
        let methodsVec = ArrayList<LLVMMetadataRef>()
        let staticMethodsVec = ArrayList<LLVMMetadataRef>()
        GenerateEnumMethodMetadata(ed, methodsVec, staticMethodsVec)
        let mdTuple = MetadataVector(llvmCtx)
            .Concat(tiOrTTName)
            .Concat(GenerateEnumConstructorMetadata(ed))
            .Concat(declaredGenericTi)
            .Concat(LLVMCreateMDTuple(llvmCtx, methodsVec))
            .Concat(LLVMCreateMDTuple(llvmCtx, staticMethodsVec))
            .Concat(GenerateAttrsMetadata(ed.GetAttributeInfo(), ExtraAttribute.ENUM, ed.GetAnnoInfo(),
                hasSRetMode: SRetMode.NO_SRET, enumKind: GetEnumKindName(module, ed)))
            .CreateMDTuple()
        LLVMAddNamedMetadataOperand(moduleHandle, typesMD, mdTuple)
        LLVMSetGlobalMetadata(llvmCtx, reflectTIOrTT, "Reflection", mdTuple)
    }

    private func GenerateEnumConstructorMetadata(ed: EnumDef): LLVMMetadataRef {
        let llvmCtx = module.GetLLVMContext()
        let fieldsVec = MetadataVector(llvmCtx)
        var index: Int64 = 0
        for (ctor in ed.GetCtors()) {
            var ctorName = ctor.name
            let currentCgType = StaticCast<CGEnumType>(CGType.GetOrCreate(module, ed.GetType().getOrThrow()))
            if (currentCgType.IsOptionLike()) {
                let nonArgIndex = if (currentCgType.IsAntiOptionLike()) { 0 } else { 1 }
                if (nonArgIndex == index && !(StaticCast<EnumType>(ed.GetType().getOrThrow()).IsOption())) {
                    ctorName = "N$_" + ctor.name
                }
            }
            let ti = GenerateCtorFn(ed, index, GetTypeQualifiedName(ed.GetType().getOrThrow()))
            fieldsVec.AddSubItem(MetadataVector(llvmCtx).Concat(ctorName).Concat(ti))
            index++
        }
        return fieldsVec.CreateMDTuple()
    }

    private func GenerateCtorFn(enumDef: EnumDef, index: Int64, qualifiedName: String): String {
        let funcName = qualifiedName + ".Ctor_" + index.toString() + ".Fn"
        let moduleHandle = module.GetLLVMModule() ?? return funcName
        var getTiFn = LLVMNullValue()
        try (funcNameCString = unsafe { LibC.mallocCString(funcName) }.asResource()) {
            getTiFn = unsafe { LLVMGetNamedFunction(moduleHandle.raw, funcNameCString.value) }
            if (getTiFn.isNull()) {
                let llvmCtx = module.GetLLVMContext()
                let i8Type = unsafe { LLVMInt8TypeInContext(llvmCtx.raw) }
                let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
                let typeInfoType = CGType.GetOrCreateTypeInfoType(llvmCtx)
                let argTypes = ArrayList<LLVMTypeRef>()
                argTypes.add(unsafe { LLVMInt32TypeInContext(llvmCtx.raw) })
                let typeInfoPtrType = unsafe { LLVMPointerType(typeInfoType, 0u32) }
                argTypes.add(unsafe { LLVMPointerType(typeInfoPtrType, 0u32) })
                var ctorFnType = LLVMNullType()
                try (argTypePtr = LibC.malloc<LLVMTypeRef>(count: argTypes.size).asResource()) {
                    var idx: Int64 = 0
                    while (idx < argTypes.size) {
                        unsafe { (argTypePtr.value + idx).write(argTypes[idx]) }
                        idx++
                    }
                    ctorFnType = unsafe { LLVMFunctionType(i8PtrType, argTypePtr.value, UInt32(argTypes.size), 0) }
                }
                getTiFn = unsafe { LLVMAddFunction(moduleHandle.raw, funcNameCString.value, ctorFnType) }
                AddFnAttr(getTiFn, "native-interface-fn")
                unsafe {
                    LLVMSetLinkage(getTiFn, LLVMLinkageValue(LLVMLinkage.Private))
                    LLVMSetUnnamedAddress(getTiFn, LLVMUnnamedAddrValue(LLVMUnnamedAddr.GlobalUnnamedAddr))
                }
                try (irBuilder = IRBuilder2(module)) {
                    let entryBB = irBuilder.CreateEntryBasicBlock(getTiFn, "entry")
                    irBuilder.SetInsertPoint(entryBB)
                    let chirEnumType = StaticCast<EnumType>(enumDef.GetType().getOrThrow())
                    let ti = if (CGType.GetOrCreate(module, chirEnumType).IsDynamicGI()) {
                        let args = ArrayList<LLVMValueRef>()
                        args.add(module.GetOrCreateEnumCtorTIOrTT(chirEnumType, index))
                        args.add(unsafe { LLVMGetParam(getTiFn, 0u32) })
                        args.add(unsafe { LLVMGetParam(getTiFn, 1u32) })
                        irBuilder.CallIntrinsicGetTypeInfo(args)
                    } else {
                        module.GetOrCreateEnumCtorTIOrTT(chirEnumType, index)
                    }
                    irBuilder.CreateRet(irBuilder.CreateBitCast(ti, i8PtrType))
                }
            }
        }
        return funcName
    }

    private func GenerateEnumMethodMetadata(ed: EnumDef, methodsVec: ArrayList<LLVMMetadataRef>,
        staticMethodsVec: ArrayList<LLVMMetadataRef>): Unit {
        for (method in ed.GetMethods()) {
            if (method.TestAttr(Attribute.NO_REFLECT_INFO) || method.TestAttr(Attribute.IMPORTED)) {
                continue
            }
            let methodMD = GenerateMethodMetadata(method)
            if (method.TestAttr(Attribute.STATIC)) {
                staticMethodsVec.add(methodMD)
            } else {
                methodsVec.add(methodMD)
            }
        }
    }
}

private class GFMetadataInfo <: MetadataInfo {
    public init(cgMod: CGModule, subCHIRPkg: SubCHIRPackage, reflectionMode: GenReflectMode) {
        super(cgMod, subCHIRPkg, reflectionMode)
    }

    public override func Gen(): Unit {
        GenerateAllFunctionsMetadata()
    }

    private func GenerateAllFunctionsMetadata(): Unit {
        if (reflectionMode != GenReflectMode.FULL_REFLECT) {
            return
        }
        let moduleHandle = module.GetLLVMModule() ?? return
        let llvmCtx = module.GetLLVMContext()
        LLVMGetOrInsertNamedMetadata(moduleHandle, METADATA_FUNCTIONS)
        for (gf in subCHIRPkg.chirFuncs) {
            if (gf.GetParentCustomTypeDef().isSome()) {
                continue
            }
            if (gf.TestAttr(Attribute.NO_REFLECT_INFO) || gf.TestAttr(Attribute.IMPORTED) ||
                gf.GetSrcCodeIdentifier().isEmpty() || gf.GetFuncType().getOrThrow().IsCFunc() ||
                gf.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
                continue
            }
            let retTypeInfo = GetTiName(gf.GetReturnType().getOrThrow())
            let hasSRetMode = GetSRetMode(gf.GetReturnType().getOrThrow(), module.GetOrInsertCGFunction(gf))
            var rawFunction = LLVMNullValue()
            try (nameCString = unsafe { LibC.mallocCString(gf.GetIdentifierWithoutPrefix()) }.asResource()) {
                rawFunction = unsafe { LLVMGetNamedFunction(moduleHandle.raw, nameCString.value) }
            }
            if (!rawFunction.isNull()) {
                let funcMD = MetadataVector(llvmCtx)
                    .Concat(gf.GetSrcCodeIdentifier())
                    .Concat(retTypeInfo)
                    .Concat(gf.GetIdentifierWithoutPrefix())
                    .Concat(GenerateParametersMetadata(gf.GetParams()))
                    .Concat(GenerateParametersMetadata(gf.GetGenericTypeParams()))
                    .Concat(GenerateAttrsMetadata(gf.GetAttributeInfo(), ExtraAttribute.METHOD,
                        gf.GetAnnoInfo(), hasSRetMode: hasSRetMode))
                    .CreateMDTuple()
                LLVMAddNamedMetadataOperand(moduleHandle, METADATA_FUNCTIONS, funcMD)
                LLVMSetGlobalMetadata(llvmCtx, rawFunction, "ReflectionFunc", funcMD)
            }
        }
    }
}

private class GVMetadataInfo <: MetadataInfo {
    public init(cgMod: CGModule, subCHIRPkg: SubCHIRPackage, reflectionMode: GenReflectMode) {
        super(cgMod, subCHIRPkg, reflectionMode)
    }

    public override func Gen(): Unit {
        GenerateGlobalVariablesMetadata()
    }

    private func GenerateGlobalVariablesMetadata(): Unit {
        if (reflectionMode != GenReflectMode.FULL_REFLECT) {
            return
        }
        let moduleHandle = module.GetLLVMModule() ?? return
        let llvmCtx = module.GetLLVMContext()
        LLVMGetOrInsertNamedMetadata(moduleHandle, METADATA_GLOBAL_VAR)
        for (variable in subCHIRPkg.chirGVs) {
            if (variable.TestAttr(Attribute.STATIC) || variable.TestAttr(Attribute.NO_REFLECT_INFO) ||
                variable.TestAttr(Attribute.IMPORTED)) {
                continue
            }
            if (let Some(variableMetadata) <- GenerateVariableMetadata(variable)) {
                LLVMAddNamedMetadataOperand(moduleHandle, METADATA_GLOBAL_VAR, variableMetadata)
                var globalVariable = LLVMNullValue()
                try (nameCString = unsafe { LibC.mallocCString(variable.GetIdentifierWithoutPrefix()) }.asResource()) {
                    globalVariable = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameCString.value) }
                }
                LLVMSetGlobalMetadata(llvmCtx, globalVariable, "ReflectionGV", variableMetadata)
            }
        }
    }

    private func GenerateVariableMetadata(variable: GlobalVar): Option<LLVMMetadataRef> {
        let moduleHandle = module.GetLLVMModule() ?? return None
        let variableMangleName = variable.GetIdentifierWithoutPrefix()
        var globalVariable = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(variableMangleName) }.asResource()) {
            globalVariable = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameCString.value) }
        }
        var isStringGV = false
        if (let Some(initializer) <- variable.GetInitializer()) {
            if (let Some(initializerTy) <- initializer.GetType()) {
                isStringGV = initializerTy.IsString()
            }
        }
        if (globalVariable.isNull()) {
            return None
        }
        if (unsafe { LLVMGetInitializer(globalVariable) }.isNull() && !isStringGV) {
            return None
        }
        let llvmCtx = module.GetLLVMContext()
        return MetadataVector(llvmCtx)
            .Concat(variable.GetSrcCodeIdentifier())
            .Concat(GetTiName(variable.GetType().getOrThrow()))
            .Concat(variableMangleName)
            .Concat(GenerateAttrsMetadata(variable.GetAttributeInfo(),
                if (variable.TestAttr(Attribute.READONLY)) {
                    ExtraAttribute.IMMUTABLE_FIELD
                } else {
                    ExtraAttribute.MUTABLE_FIELD
                },
                variable.GetAnnoInfo()))
            .CreateMDTuple()
    }
}

public func GenerateReflectionMetadata(module: CGModule, subCHIRPkg: SubCHIRPackage): Unit {
    let globalOptions = module.GetCGContext().GetCGPkgContext().GetGlobalOptions()
    let reflectionMode = if (globalOptions.disableReflection) {
        GenReflectMode.NO_REFLECT
    } else {
        GenReflectMode.FULL_REFLECT
    }
    let allKinds: Array<MetadataKind> = [
        MetadataKind.PKG_METADATA,
        MetadataKind.CLASS_METADATA,
        MetadataKind.STRUCT_METADATA,
        MetadataKind.ENUM_METADATA,
        MetadataKind.GF_METADATA,
        MetadataKind.GV_METADATA]
    for (kind in allKinds) {
        match (kind) {
            case MetadataKind.PKG_METADATA => PkgMetadataInfo(module, subCHIRPkg, reflectionMode).Gen()
            case MetadataKind.CLASS_METADATA => ClassMetadataInfo(module, subCHIRPkg, reflectionMode).Gen()
            case MetadataKind.STRUCT_METADATA => StructMetadataInfo(module, subCHIRPkg, reflectionMode).Gen()
            case MetadataKind.ENUM_METADATA => EnumMetadataInfo(module, subCHIRPkg, reflectionMode).Gen()
            case MetadataKind.GF_METADATA => GFMetadataInfo(module, subCHIRPkg, reflectionMode).Gen()
            case MetadataKind.GV_METADATA => GVMetadataInfo(module, subCHIRPkg, reflectionMode).Gen()
            case MetadataKind.COUNT => ()
        }
    }
}

private func AddTestAttrs(attrsStr: HashSet<String>, attrs: AttributeInfo): Unit {
    if (attrs.Test(Attribute.PUBLIC)) { attrsStr.add("public") }
    if (attrs.Test(Attribute.PROTECTED)) { attrsStr.add("protected") }
    if (attrs.Test(Attribute.PRIVATE)) { attrsStr.add("private") }
    if (attrs.Test(Attribute.VIRTUAL)) { attrsStr.add("open") }
    if (attrs.Test(Attribute.OVERRIDE)) { attrsStr.add("override") }
    if (attrs.Test(Attribute.REDEF)) { attrsStr.add("redef") }
    if (attrs.Test(Attribute.MUT)) { attrsStr.add("mut") }
    if (attrs.Test(Attribute.STATIC)) { attrsStr.add("static") }
    if (attrs.Test(Attribute.ABSTRACT)) { attrsStr.add("abstract") }
    if (attrs.Test(Attribute.SEALED)) { attrsStr.add("sealed") }
}

private func GetSRetMode(retTy: Type, cgFunc: CGFunction): SRetMode {
    if (!cgFunc.IsSRet()) {
        return SRetMode.NO_SRET
    }
    if (!retTy.IsGenericRelated()) {
        return SRetMode.SRET_NON_GENERIC
    }
    if (retTy.IsGeneric()) {
        return SRetMode.SRET_GENERIC
    }
    let sretTy = unsafe { LLVMTypeOf(unsafe { LLVMGetParam(cgFunc.GetRawFunction(), 0u32) }) }
    if (!sretTy.isNull() && unsafe { LLVMGetTypeKind(sretTy) } == 12) {
        if (unsafe { LLVMGetPointerAddressSpace(sretTy) } == 0u32) {
            return SRetMode.SRET_KNOWN_GENERIC_CUSTOM
        }
        return SRetMode.SRET_UNKNOWN_GENERIC_CUSTOM
    }
    return SRetMode.SRET_NON_GENERIC
}

private func GetEnumKindName(cgMod: CGModule, ed: EnumDef): String {
    let cgType = StaticCast<CGEnumType>(CGType.GetOrCreate(cgMod, ed.GetType().getOrThrow()))
    return match (cgType.GetCGEnumTypeKind()) {
        case CGEnumTypeKind.NON_EXHAUSTIVE_UNASSOCIATED => "enumKind0"
        case CGEnumTypeKind.EXHAUSTIVE_ZERO_SIZE => "enumKind0"
        case CGEnumTypeKind.EXHAUSTIVE_UNASSOCIATED => "enumKind0"
        case CGEnumTypeKind.NON_EXHAUSTIVE_ASSOCIATED => "enumKind1"
        case CGEnumTypeKind.EXHAUSTIVE_OTHER => "enumKind1"
        case CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_REF => "enumKind2"
        case CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_NONREF => "enumKind2"
        case CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_T => "enumKind2"
        case CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_NONREF => "enumKind3"
        case _ => "UNKNOWN"
    }
}

private func IsClassForBoxType(className: String): Bool {
    return className.indexOf(BOX_DECL_PREFIX).isSome()
}

private func ReplaceDelimiterAfterOrgName(packageName: String): String {
    if (let Some(splitter) <- packageName.indexOf("::")) {
        return packageName[0..splitter] + "/" + packageName[splitter + 2..]
    }
    return packageName
}

private func CompareMetadataString(left: String, right: String): Ordering {
    let minSize = if (left.size < right.size) { left.size } else { right.size }
    var idx: Int64 = 0
    while (idx < minSize) {
        if (left[idx] < right[idx]) {
            return Ordering.LT
        }
        if (left[idx] > right[idx]) {
            return Ordering.GT
        }
        idx++
    }
    if (left.size < right.size) {
        return Ordering.LT
    }
    if (left.size > right.size) {
        return Ordering.GT
    }
    return Ordering.EQ
}
