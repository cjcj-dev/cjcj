package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.CHIRBuilder
import cangjie_compiler::chir.Function
import cangjie_compiler::chir.Package
import cangjie_compiler::chir.Type
import cangjie_compiler::option.GlobalOptions

public class CallBaseToReplaceInfo {
    public let callWithoutTI: LLVMValueRef
    public let callerName: String
    public let calleeName: String
    public let thisParamType: Type
    public let isCalleeMutOrCtor: Bool

    public init(callWithoutTI: LLVMValueRef, callerName: String, calleeName: String, thisParamType: Type,
        isCalleeMutOrCtor: Bool) {
        this.callWithoutTI = callWithoutTI
        this.callerName = callerName
        this.calleeName = calleeName
        this.thisParamType = thisParamType
        this.isCalleeMutOrCtor = isCalleeMutOrCtor
    }
}

public class VirtualCallInfo4LICM {
    public let prepForVirtualCallBB: LLVMBasicBlockRef
    public var lookupVirtualInst: LLVMValueRef
    public var getOuterTypeInst: LLVMValueRef = LLVMNullValue()
    public let thisTypeText: String
    public let outerTypeText: String
    public let virtualMethodOffset: Int64

    public init(prepForVirtualCallBB: LLVMBasicBlockRef, lookupVirtualInst: LLVMValueRef, thisTypeText: String,
        outerTypeText: String, virtualMethodOffset: Int64) {
        this.prepForVirtualCallBB = prepForVirtualCallBB
        this.lookupVirtualInst = lookupVirtualInst
        this.thisTypeText = thisTypeText
        this.outerTypeText = outerTypeText
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
    private let generatedStructType: HashSet<String> = HashSet<String>()
    private let globalsOfCompileUnit: HashSet<String> = HashSet<String>()
    private let staticGINames: HashSet<String> = HashSet<String>()
    private let reflectGeneratedStaticGINames: ArrayList<String> = ArrayList<String>()
    private let cjStrings: HashMap<String, String> = HashMap<String, String>()
    private let codegenAddedFuncsOrVars: HashMap<String, HashSet<String>> = HashMap<String, HashSet<String>>()
    private let llvmUsedGVs: HashSet<String> = HashSet<String>()
    private let callBasesToReplace: ArrayList<CallBaseToReplaceInfo> = ArrayList<CallBaseToReplaceInfo>()
    private let dependentPartialOrderOfTypes: ArrayList<PartialOrderPair> = ArrayList<PartialOrderPair>()

    public var debugValue: LLVMValueRef = LLVMNullValue()

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
        cjStrings.clear()
        codegenAddedFuncsOrVars.clear()
        llvmUsedGVs.clear()
        callBasesToReplace.clear()
        dependentPartialOrderOfTypes.clear()
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

    public func GetImplicitUsedFunc(funcMangledName: String): Option<Function> {
        return cgPkgContext.GetImplicitUsedFunc(funcMangledName)
    }

    public func GetCjStringType(): LLVMTypeRef {
        var result = LLVMNullType()
        try (nameCString = unsafe { LibC.mallocCString("record.std.core:String") }.asResource()) {
            result = unsafe { LLVMStructCreateNamed(llvmContext.raw, nameCString.value) }
        }
        return result
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
        let declMangledName = ty.ToString()
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
        return unwindBlockStack[unwindBlockStack.size - 1]
    }

    public func PopUnwindBlockStack(): Unit {
        if (!unwindBlockStack.isEmpty()) {
            unwindBlockStack.remove(at: unwindBlockStack.size - 1)
        }
    }

    public func AddGeneratedStructType(structTypeName: String): Unit {
        if (!structTypeName.isEmpty()) {
            generatedStructType.add(structTypeName)
        }
    }

    public func GetGeneratedStructType(): HashSet<String> {
        return generatedStructType
    }

    public func IsGeneratedStructType(structTypeName: String): Bool {
        return generatedStructType.contains(structTypeName)
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

    public func AddDependentPartialOrderOfTypes(smaller: LLVMValueRef, bigger: LLVMValueRef): Unit {
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
        let key = extraInfo.Key() + "|" + chirTy.ToString()
        if (let Some(cached) <- impl.FindCGType(key)) {
            return cached
        }
        let created = CGTypeMgr.GetConcreteCGTypeFor(cgMod, chirTy, extraInfo: extraInfo)
        impl.SetCGType(key, created)
        created.Complete()
        return created
    }
}
