package cjcj::codegen

import std.collection.*
import cjcj::chir.Attribute
import cjcj::chir.CHIRBuilder
import cjcj::chir.ClassType
import cjcj::chir.CustomType
import cjcj::chir.DebugLocation
import cjcj::chir.Function
import cjcj::chir.GlobalVar
import cjcj::chir.Package
import cjcj::chir.Type
import cjcj::chir.Value
import cjcj::option.GlobalOptions
import cjcj::utils.{CJC_ASSERT, DynamicCast}

public class CallBaseToReplaceInfo {
    public let callWithoutTI: LLVMValueRef
    public let cgFuncCaller: CGFunction
    public let cgFuncCallee: CGFunction
    public let thisParamType: Type
    public let isCalleeMutOrCtor: Bool

    public init(callWithoutTI: LLVMValueRef, cgFuncCaller: CGFunction, cgFuncCallee: CGFunction, thisParamType: Type,
        isCalleeMutOrCtor: Bool) {
        this.callWithoutTI = callWithoutTI
        this.cgFuncCaller = cgFuncCaller
        this.cgFuncCallee = cgFuncCallee
        this.thisParamType = thisParamType
        this.isCalleeMutOrCtor = isCalleeMutOrCtor
    }
}

public class VirtualCallInfo4LICM {
    public let prepForVirtualCallBB: LLVMBasicBlockRef
    public var lookupVirtualInst: LLVMValueRef
    public var getOuterTypeInst: LLVMValueRef = LLVMNullValue()
    public let thisType: Type
    public let outerType: ClassType
    public let virtualMethodOffset: UInt64

    public init(prepForVirtualCallBB: LLVMBasicBlockRef, lookupVirtualInst: LLVMValueRef, thisType: Type,
        outerType: ClassType, virtualMethodOffset: UInt64) {
        this.prepForVirtualCallBB = prepForVirtualCallBB
        this.lookupVirtualInst = lookupVirtualInst
        this.thisType = thisType
        this.outerType = outerType
        this.virtualMethodOffset = virtualMethodOffset
    }

    public func SetLookupVirtualInst(inst: LLVMValueRef): Unit {
        lookupVirtualInst = inst
    }

    public func SetGetOuterTypeInst(inst: LLVMValueRef): Unit {
        getOuterTypeInst = inst
    }
}

public class PartialOrderPair {
    public let smaller: LLVMValueRef
    public let bigger: LLVMValueRef
    public init(smaller: LLVMValueRef, bigger: LLVMValueRef) {
        this.smaller = smaller
        this.bigger = bigger
    }
}

public class CGContext {
    private let subCHIRPackage: SubCHIRPackage
    private let cgPkgContext: CGPkgContext
    private let llvmContext: LLVMContextHandle
    private let impl: CGContextImpl = CGContextImpl()
    private let unwindBlockStack: ArrayList<LLVMBasicBlockRef> = ArrayList<LLVMBasicBlockRef>()
    private let generatedStructType: TreeSet<String> = TreeSet<String>()
    private let globalsOfCompileUnit: HashSet<String> = HashSet<String>()
    private let staticGINames: HashSet<String> = HashSet<String>()
    private let reflectGeneratedStaticGINames: ArrayList<String> = ArrayList<String>()
    private let genericTypeUpperBoundKeys: HashMap<String, ArrayList<String>> = HashMap<String, ArrayList<String>>()
    private let cjStrings: HashMap<String, String> = HashMap<String, String>()
    private let codegenAddedFuncsOrVars: HashMap<String, HashSet<String>> = HashMap<String, HashSet<String>>()
    private let llvmUsedGVs: HashSet<String> = HashSet<String>()
    private let callBasesToInline: ArrayList<(LLVMValueRef, LLVMValueRef)> = ArrayList<(LLVMValueRef, LLVMValueRef)>()
    private let callBasesToReplace: ArrayList<CallBaseToReplaceInfo> = ArrayList<CallBaseToReplaceInfo>()
    private let virtualCallInfo4LICMMap: ArrayList<(CGFunction, ArrayList<VirtualCallInfo4LICM>)> =
        ArrayList<(CGFunction, ArrayList<VirtualCallInfo4LICM>)>()
    private let dependentPartialOrderOfTypes: ArrayList<PartialOrderPair> = ArrayList<PartialOrderPair>()
    private let debugLocOfRetExpr: HashMap<UIntNative, ArrayList<DebugLocation>> =
        HashMap<UIntNative, ArrayList<DebugLocation>>()
    private let nonRefBox2RefMap: HashMap<UIntNative, LLVMValueRef> = HashMap<UIntNative, LLVMValueRef>()
    private var cjStringType: LLVMTypeRef = LLVMNullType()

    public var debugValue: LLVMValueRef = LLVMNullValue()
    public let genericParamsCacheMap: HashMap<UIntNative, HashMap<Int64, LLVMValueRef>> =
        HashMap<UIntNative, HashMap<Int64, LLVMValueRef>>()
    public let genericParamsSizeBlockLevelCacheMap: HashMap<UIntNative, HashMap<UIntNative, LLVMValueRef>> =
        HashMap<UIntNative, HashMap<UIntNative, LLVMValueRef>>()

    public init(subCHIRPackage: SubCHIRPackage, cgPkgContext: CGPkgContext) {
        this.subCHIRPackage = subCHIRPackage
        this.cgPkgContext = cgPkgContext
        llvmContext = LLVMContextHandle.Create()
    }

    public func Clear(): Unit {
        impl.Clear()
        unwindBlockStack.clear()
        generatedStructType.clear()
        globalsOfCompileUnit.clear()
        staticGINames.clear()
        reflectGeneratedStaticGINames.clear()
        genericTypeUpperBoundKeys.clear()
        cjStrings.clear()
        codegenAddedFuncsOrVars.clear()
        llvmUsedGVs.clear()
        callBasesToInline.clear()
        callBasesToReplace.clear()
        virtualCallInfo4LICMMap.clear()
        dependentPartialOrderOfTypes.clear()
        debugLocOfRetExpr.clear()
        nonRefBox2RefMap.clear()
        genericParamsCacheMap.clear()
        genericParamsSizeBlockLevelCacheMap.clear()
        subCHIRPackage.Clear()
    }

    public func GetSubCHIRPackage(): SubCHIRPackage { return subCHIRPackage }
    public func GetCGPkgContext(): CGPkgContext { return cgPkgContext }
    public func GetCHIRBuilder(): CHIRBuilder { return cgPkgContext.GetCHIRBuilder() }
    public func GetCHIRPackage(): Package { return cgPkgContext.GetCHIRPackage() }
    public func GetCurrentPkgName(): String { return cgPkgContext.GetCurrentPkgName() }
    public func GetCompileOptions(): GlobalOptions { return cgPkgContext.GetGlobalOptions() }
    public func GetLLVMContext(): LLVMContextHandle { return llvmContext }
    public func GetCachedMangleMap(): CachedMangleMap { return cgPkgContext.GetCachedMangleMap() }
    public func IsCGParallelEnabled(): Bool { return cgPkgContext.IsCGParallelEnabled() }
    public func IsLineInfoEnabled(): Bool { return cgPkgContext.IsLineInfoEnabled() }
    public func AddLocalizedSymbol(symName: String): Unit { cgPkgContext.AddLocalizedSymbol(symName) }

    public func IsCustomTypeOfOtherLLVMModule(chirType: Type): Bool {
        if (let Some(customType) <- (chirType as CustomType)) {
            let customDef = customType.GetCustomTypeDef()
            if (customDef.TestAttr(Attribute.IMPORTED)) {
                return true
            }
            return !subCHIRPackage.OwnsCustomDef(customDef)
        }
        return false
    }

    public func IsValueOfOtherLLVMModule(chirValue: Value): Bool {
        if (chirValue.TestAttr(Attribute.IMPORTED)) {
            return true
        }
        if (let Some(chirFunc) <- (chirValue as Function)) {
            if (chirFunc.IsFuncWithBody()) {
                return !subCHIRPackage.OwnsFunction(chirFunc)
            }
            return false
        } else if (let Some(chirGV) <- (chirValue as GlobalVar)) {
            if (chirGV.IsGlobalVarWithInitializer()) {
                return !subCHIRPackage.OwnsGlobalVar(chirGV)
            }
        }
        return false
    }

    public func AddCallBaseToInline(callBase: LLVMValueRef, retInst: LLVMValueRef): Unit {
        callBasesToInline.add((callBase, retInst))
    }

    public func GetCallBasesToInline(): ArrayList<(LLVMValueRef, LLVMValueRef)> {
        let out = ArrayList<(LLVMValueRef, LLVMValueRef)>()
        for (item in callBasesToInline) {
            out.add(item)
        }
        return out
    }

    public func AddCallBaseToReplace(callBaseToReplaceInfo: CallBaseToReplaceInfo): Unit {
        callBasesToReplace.add(callBaseToReplaceInfo)
    }

    public func GetCallBasesToReplace(): ArrayList<CallBaseToReplaceInfo> {
        let out = ArrayList<CallBaseToReplaceInfo>()
        for (item in callBasesToReplace) {
            out.add(item)
        }
        return out
    }

    public func AddVirtualCallInfo4LICM(cgfunc: CGFunction, info: VirtualCallInfo4LICM): Unit {
        for ((mappedCGFunc, vec) in virtualCallInfo4LICMMap) {
            if (!refEq(mappedCGFunc, cgfunc)) {
                continue
            }
            var idx = vec.size - 1
            while (idx >= 0) {
                if (vec[idx].prepForVirtualCallBB.toUIntNative() == info.prepForVirtualCallBB.toUIntNative()) {
                    return
                }
                idx--
            }
            vec.add(info)
            return
        }
        let vec = ArrayList<VirtualCallInfo4LICM>()
        vec.add(info)
        virtualCallInfo4LICMMap.add((cgfunc, vec))
    }

    public func SetGetOuterTypeInst(cgfunc: CGFunction, prepForVirtualCallBB: LLVMBasicBlockRef,
        getOuterTypeInst: LLVMValueRef): Unit {
        for ((mappedCGFunc, vec) in virtualCallInfo4LICMMap) {
            if (!refEq(mappedCGFunc, cgfunc)) {
                continue
            }
            var idx = vec.size - 1
            while (idx >= 0) {
                if (vec[idx].prepForVirtualCallBB.toUIntNative() == prepForVirtualCallBB.toUIntNative()) {
                    vec[idx].SetGetOuterTypeInst(getOuterTypeInst)
                    return
                }
                idx--
            }
            return
        }
    }

    public func GetVirtualCallInfo4LICM(cgfunc: CGFunction): ArrayList<VirtualCallInfo4LICM> {
        for ((mappedCGFunc, vec) in virtualCallInfo4LICMMap) {
            if (refEq(mappedCGFunc, cgfunc)) {
                return vec
            }
        }
        return ArrayList<VirtualCallInfo4LICM>()
    }

    public func AddDebugLocOfRetExpr(funcValue: LLVMValueRef, debugLoc: DebugLocation): Unit {
        let key = funcValue.toUIntNative()
        if (!debugLocOfRetExpr.contains(key)) {
            debugLocOfRetExpr[key] = ArrayList<DebugLocation>()
        }
        debugLocOfRetExpr[key].add(debugLoc)
    }

    public func GetDebugLocOfRetExpr(funcValue: LLVMValueRef): ArrayList<DebugLocation> {
        let key = funcValue.toUIntNative()
        if (!debugLocOfRetExpr.contains(key)) {
            debugLocOfRetExpr[key] = ArrayList<DebugLocation>()
        }
        return debugLocOfRetExpr[key]
    }

    public func SetBoxedValueMap(boxedRefVal: LLVMValueRef, originalNonRefVal: LLVMValueRef): Unit {
        if (!nonRefBox2RefMap.contains(boxedRefVal.toUIntNative())) {
            nonRefBox2RefMap[boxedRefVal.toUIntNative()] = originalNonRefVal
        }
    }

    public func GetOriginalNonRefValOfBoxedValue(boxedRefVal: LLVMValueRef): Option<LLVMValueRef> {
        return nonRefBox2RefMap.get(boxedRefVal.toUIntNative())
    }

    public func SetBasePtr(value: LLVMValueRef, basePtr: LLVMValueRef): Unit {
        impl.SetBasePtr(value, basePtr)
    }

    public func GetBasePtrOf(value: LLVMValueRef): Option<LLVMValueRef> {
        return impl.GetBasePtr(value)
    }

    public func GetImplicitUsedFunc(funcMangledName: String): Option<Function> {
        return cgPkgContext.GetImplicitUsedFunc(funcMangledName)
    }

    public func GetCjStringType(): LLVMTypeRef {
        if (!cjStringType.isNull()) {
            return cjStringType
        }
        let fields = ArrayList<LLVMTypeRef>()
        fields.add(unsafe { LLVMPointerType(LLVMInt8TypeInContext(llvmContext.raw), 1u32) })
        fields.add(unsafe { LLVMInt32TypeInContext(llvmContext.raw) })
        fields.add(unsafe { LLVMInt32TypeInContext(llvmContext.raw) })
        var result = LLVMNullType()
        try (nameCString = unsafe { LibC.mallocCString("record.std.core:String") }.asResource()) {
            result = unsafe { LLVMGetTypeByName2(llvmContext.raw, nameCString.value) }
            if (result.isNull()) {
                result = unsafe { LLVMStructCreateNamed(llvmContext.raw, nameCString.value) }
                SetStructTypeBody(result, fields)
            }
        }
        cjStringType = result
        return cjStringType
    }

    public func AddCJString(cjStringName: String, cjStringContent: String): Unit {
        cjStrings[cjStringName] = cjStringContent
    }

    public func GetCJStrings(): HashMap<String, String> {
        let out = HashMap<String, String>()
        for ((key, value) in cjStrings) { out[key] = value }
        return out
    }

    public func AddCodeGenAddedFuncsOrVars(ty: Type, codegenAddedName: String): Unit {
        if (!cgPkgContext.GetGlobalOptions().enIncrementalCompilation) {
            return
        }
        if (!(ty.IsClass() || ty.IsStruct() || ty.IsEnum())) {
            return
        }
        let customTy = (ty as CustomType) ?? return
        let declMangledName = customTy.GetCustomTypeDef().GetIdentifierWithoutPrefix()
        if (!codegenAddedFuncsOrVars.contains(declMangledName)) {
            codegenAddedFuncsOrVars[declMangledName] = HashSet<String>()
        }
        codegenAddedFuncsOrVars[declMangledName].add(codegenAddedName)
    }

    public func GetCodeGenAddedFuncsOrVars(): HashMap<String, HashSet<String>> {
        return codegenAddedFuncsOrVars
    }

    public func PushUnwindBlockStack(unwindBlock: LLVMBasicBlockRef): Unit {
        unwindBlockStack.add(unwindBlock)
    }

    public func TopUnwindBlockStack(): Option<LLVMBasicBlockRef> {
        if (unwindBlockStack.isEmpty()) {
            return None
        }
        let top = unwindBlockStack[unwindBlockStack.size - 1]
        if (top.isNull()) {
            return None
        }
        return top
    }

    public func PopUnwindBlockStack(): Unit {
        if (!unwindBlockStack.isEmpty()) {
            unwindBlockStack.remove(at: unwindBlockStack.size - 1)
        }
    }

    public func AddGeneratedStructType(structTypeName: String): Unit {
        CJC_ASSERT(!structTypeName.isEmpty())
        generatedStructType.add(structTypeName)
    }

    public func GetGeneratedStructType(): TreeSet<String> {
        return generatedStructType
    }

    public func IsGeneratedStructType(structTypeName: String): Bool {
        return generatedStructType.contains(structTypeName)
    }

    public func AddNullableReference(value: LLVMValueRef): Unit {
        impl.AddNullableReference(value)
    }

    public func AddGlobalsOfCompileUnit(globalsName: String): Unit {
        globalsOfCompileUnit.add(globalsName)
    }

    public func IsGlobalsOfCompileUnit(globalsName: String): Bool {
        return globalsOfCompileUnit.contains(globalsName)
    }

    public func IsGlobalsOfCompileUnitCString(globalsName: CString): Bool {
        return CGContext.ContainsCString(globalsOfCompileUnit, globalsName)
    }

    public func RegisterStaticGIName(staticGIName: String): Unit {
        staticGINames.add(staticGIName)
    }

    public func GetStaticGINames(): HashSet<String> {
        return staticGINames
    }

    public func RegisterReflectGeneratedStaticGIName(staticGIName: String): Unit {
        reflectGeneratedStaticGINames.add(staticGIName)
    }

    public func GetReflectGeneratedStaticGINames(): ArrayList<String> {
        return reflectGeneratedStaticGINames
    }

    public func GetGenericTypeUniqueName(genericTypeName: String, upperBounds: ArrayList<Type>): String {
        let upperBoundsKey = GenericUpperBoundsKey(upperBounds)
        if (let Some(keys) <- genericTypeUpperBoundKeys.get(genericTypeName)) {
            var idx: Int64 = 0
            while (idx < keys.size) {
                if (keys[idx] == upperBoundsKey) {
                    return genericTypeName + "." + idx.toString()
                }
                idx++
            }
            keys.add(upperBoundsKey)
            return genericTypeName + "." + (keys.size - 1).toString()
        }
        let keys = ArrayList<String>()
        keys.add(upperBoundsKey)
        genericTypeUpperBoundKeys[genericTypeName] = keys
        return genericTypeName + ".0"
    }

    private func GenericUpperBoundsKey(upperBounds: ArrayList<Type>): String {
        var out = ""
        var idx: Int64 = 0
        for (upperBound in upperBounds) {
            if (idx > 0) {
                out += ";"
            }
            out += CGType.GetNameOfTypeInfoGV(upperBound.StripAllRefs())
            idx++
        }
        return out
    }

    public func AddDependentPartialOrderOfTypes(smaller: LLVMValueRef, bigger: LLVMValueRef): Unit {
        for (pair in dependentPartialOrderOfTypes) {
            if (pair.smaller.toUIntNative() == smaller.toUIntNative() &&
                pair.bigger.toUIntNative() == bigger.toUIntNative()) {
                return
            }
        }
        dependentPartialOrderOfTypes.add(PartialOrderPair(smaller, bigger))
    }

    public func GetDependentPartialOrderOfTypes(): ArrayList<PartialOrderPair> {
        return dependentPartialOrderOfTypes
    }

    public func AddLLVMUsedVars(mangledNameOfGV: String): Unit {
        llvmUsedGVs.add(mangledNameOfGV)
    }

    public func GetLLVMUsedVars(): HashSet<String> {
        return llvmUsedGVs
    }

    public static func ContainsCString(values: HashSet<String>, name: CString): Bool {
        if (name.isNull()) {
            return false
        }
        for (value in values) {
            try (valueCString = unsafe { LibC.mallocCString(value) }.asResource()) {
                if (unsafe { strcmp(name, valueCString.value) } == 0) {
                    return true
                }
            }
        }
        return false
    }

    public func Add2CGTypePool(cgType: CGType): Unit {
        impl.AddCGType(cgType)
    }

    public func GetOrCreateCGType(cgMod: CGModule, chirTy: Type, extraInfo: TypeExtraInfo): CGType {
        var normalizedTy = chirTy
        let classTyOpt = DynamicCast<ClassType>(normalizedTy)
        if (classTyOpt.isSome() && IsAutoEnvInstBaseType(normalizedTy)) {
            let classTy = classTyOpt.getOrThrow()
            normalizedTy = classTy.GetSuperClassTy(builder: Some(cgMod.GetCGContext().GetCHIRBuilder())).getOrThrow()
            CJC_ASSERT(IsAutoEnvBaseType(normalizedTy) && !normalizedTy.GetTypeArgs().isEmpty())
        }
        if (let Some(cached) <- impl.FindCGType(extraInfo, normalizedTy)) {
            let cachedType = if (let Some(rawType) <- cached.llvmType) { rawType } else { LLVMNullType() }
            if (!IsLitStructPtrType(cachedType)) {
                return cached
            }
        }
        let created = CGTypeMgr.GetConcreteCGTypeFor(cgMod, normalizedTy, extraInfo: extraInfo)
        impl.SetCGType(extraInfo, normalizedTy, created)
        created.Complete()
        return created
    }
}
