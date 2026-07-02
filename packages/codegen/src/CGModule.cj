package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Attribute
import cangjie_compiler::chir.Block
import cangjie_compiler::chir.CustomTypeDef
import cangjie_compiler::chir.EnumType
import cangjie_compiler::chir.ExtendDef
import cangjie_compiler::chir.ExprKind
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.FuncType
import cangjie_compiler::chir.Function
import cangjie_compiler::chir.GenericType
import cangjie_compiler::chir.GlobalVar
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.TypeKind
import cangjie_compiler::chir.Value
import cangjie_compiler::mangle.GetTypeArgsQualifiedName
import cangjie_compiler::option.ArchType
import cangjie_compiler::option.EnvironmentType
import cangjie_compiler::option.OSType
import cangjie_compiler::option.TripleInfo
import cangjie_compiler::utils.CJC_ASSERT_WITH_MSG

private let CJ_PERSONALITY_FUNC_NAME: String = "__cj_personality_v0$"

public func SetCangjieGC(rawFunction: LLVMValueRef): Unit {
    if (rawFunction.isNull()) {
        return
    }
    try (gcName = unsafe { LibC.mallocCString("cangjie") }.asResource()) {
        unsafe { LLVMSetGC(rawFunction, gcName.value) }
    }
}

public open class CGValue {
    private var rawVal: LLVMValueRef
    private var cgType: Option<CGType>
    private var sRetArg: Bool

    public init() {
        rawVal = LLVMNullValue()
        cgType = None
        sRetArg = false
    }

    public init(rawVal: LLVMValueRef, cgType: CGType, isSRetArg!: Bool = false) {
        this.rawVal = rawVal
        this.cgType = cgType
        sRetArg = isSRetArg
    }

    public func GetRawValue(): LLVMValueRef { return rawVal }
    public func GetCGType(): Option<CGType> { return cgType }
    public func GetLLVMType(): LLVMTypeRef {
        if (let Some(valueType) <- cgType) {
            return valueType.GetLLVMType()
        }
        return LLVMNullType()
    }
    public func IsSRetArg(): Bool { return sRetArg }
}

public class MTableInterfaceInfo {
    public let interfaceTy: Type
    public let candidateTy: Option<Type>

    public init(interfaceTy: Type, candidateTy: Option<Type>) {
        this.interfaceTy = interfaceTy
        this.candidateTy = candidateTy
    }
}

public class CGModule {
    private let cgCtx: CGContext
    private var module: Option<LLVMModuleHandle>
    private let functions: HashMap<String, CGFunction> = HashMap<String, CGFunction>()
    private let globalVariables: HashMap<String, CGValue> = HashMap<String, CGValue>()
    private let localValueMapping: HashMap<Value, CGValue> = HashMap<Value, CGValue>()
    private let basicBlocks: HashMap<Int64, LLVMBasicBlockRef> = HashMap<Int64, LLVMBasicBlockRef>()
    private let linkNameUsedInMeta: HashSet<String> = HashSet<String>()
    private let externalExtensionDefs: ArrayList<LLVMValueRef> = ArrayList<LLVMValueRef>()
    private let nonExternalExtensionDefs: ArrayList<LLVMValueRef> = ArrayList<LLVMValueRef>()
    private let extensionDefStartIndices: HashMap<String, Int64> = HashMap<String, Int64>()
    private let extensionDefInterfaces: HashMap<String, ArrayList<MTableInterfaceInfo>> =
        HashMap<String, ArrayList<MTableInterfaceInfo>>()
    private var cffi: Option<CGCFFI> = None
    private let ghostCFuncArgValues: ArrayList<CGValue> = ArrayList<CGValue>()
    // Keyed on the SPECIFIC instantiated enum type (ToString), not the shared generic EnumDef
    // nodeId: all Option<X> instantiations share one EnumDef, so a nodeId key falsely blocks
    // classifying Option<Int> while Option<String> is mid-classification, leaving cgEnumTypeKind
    // UNKNOWN -> GenLLVMType bakes the i32 (else-branch) selector. Per-instantiated-type keying
    // only blocks genuine self-recursion, matching C++'s per-type cache (CGType.cpp:165-173).
    private let enumClassificationStack: HashSet<String> = HashSet<String>()
    private var diBuilder: Option<DIBuilder> = None
    // Faithful to C++ CGModule::delayGenTypeInfo (CGModule.h:316): concrete TypeInfo definitions are
    // queued here and drained iteratively by GenTypeInfo() rather than defined recursively inline, so a
    // recursive type (a field/type-arg referencing the type being defined) does not infinitely recurse.
    private let delayGenTypeInfo: ArrayList<CGType> = ArrayList<CGType>()

    public init(subCHIRPackage: SubCHIRPackage, cgPkgCtx: CGPkgContext) {
        cgCtx = CGContext(subCHIRPackage, cgPkgCtx)
        let moduleName = "${subCHIRPackage.subCHIRPackageIdx}-" + cgPkgCtx.GetCurrentPkgName()
        let moduleHandle = LLVMModuleHandle.Create(moduleName, cgCtx.GetLLVMContext())
        module = moduleHandle
        InitModuleFlags(moduleHandle)
        moduleHandle.SetDataLayout(CGModule.GetDataLayoutString(cgCtx.GetCompileOptions().target))
        moduleHandle.SetTargetTriple(CGModule.GetTargetTripleString(cgCtx.GetCompileOptions().target))
        InitDebugInfo()
        cffi = CreateCGCFFI()
    }

    public func GetCGContext(): CGContext { return cgCtx }
    public func GetLLVMContext(): LLVMContextHandle { return cgCtx.GetLLVMContext() }
    public func GetCGCFFI(): CGCFFI { return cffi.getOrThrow() }
    public func CreateGhostCFuncArgValue(llvmValue: LLVMValueRef, ty: CGType): CGValue {
        let value = CGValue(llvmValue, ty)
        ghostCFuncArgValues.add(value)
        return value
    }

    // Mirror C++ CGModule::DelayGenTypeInfo (CGModule.h:287): queue a CGType whose TypeInfo global has
    // been declared but not yet defined.
    public func DelayGenTypeInfo(cgType: CGType): Unit {
        delayGenTypeInfo.add(cgType)
    }

    // Mirror C++ CGModule::GenTypeInfo (CGModule.cpp:124-130): drain the delayed-TypeInfo stack,
    // defining each queued type. Draining a type may enqueue further types (its fields/type args); the
    // loop runs until the stack is empty. LIFO to match C++ std::stack ordering.
    public func GenTypeInfo(): Unit {
        while (!delayGenTypeInfo.isEmpty()) {
            let cgType = delayGenTypeInfo.remove(at: delayGenTypeInfo.size - 1)
            cgType.GenTypeInfo()
        }
    }

    public func OwnsCustomTypeDef(def: CustomTypeDef): Bool {
        return cgCtx.GetSubCHIRPackage().OwnsCustomDef(def)
    }

    public func OwnsTypeTemplateName(name: String): Bool {
        return cgCtx.GetSubCHIRPackage().OwnsTypeTemplateName(name)
    }

    public func GetLLVMModule(): Option<LLVMModuleHandle> {
        return module
    }

    public func GenerateTypeNameConstantString(typeMangledName: String, isWeakODR: Bool,
        qualifiedName!: String = ""): LLVMValueRef {
        let context = GetLLVMContext().raw
        let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(context), 0u32) }
        let moduleHandle = module ?? return unsafe { LLVMConstNull(i8PtrType) }
        let value = if (!qualifiedName.isEmpty()) { qualifiedName } else { typeMangledName }
        var strConstant = LLVMNullValue()
        try (valueCString = unsafe { LibC.mallocCString(value) }.asResource()) {
            strConstant = unsafe { LLVMConstStringInContext(context, valueCString.value, UInt32(value.size), 0) }
        }
        let globalName = typeMangledName + ".name"
        var klassName = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(globalName) }.asResource()) {
            klassName = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameCString.value) }
            if (klassName.isNull()) {
                klassName = unsafe { LLVMAddGlobal(moduleHandle.raw, LLVMTypeOf(strConstant), nameCString.value) }
            }
        }
        unsafe {
            LLVMSetInitializer(klassName, strConstant)
            LLVMSetAlignment(klassName, 1u32)
            LLVMSetGlobalConstant(klassName, 1)
            LLVMSetUnnamedAddress(klassName, LLVMUnnamedAddrValue(LLVMUnnamedAddr.GlobalUnnamedAddr))
        }
        addAttribute(klassName, CJTYPE_NAME_ATTR)
        AddLinkageTypeMetadata(klassName, if (isWeakODR) { LLVMLinkage.WeakODR } else { LLVMLinkage.Private }, false)
        return unsafe { LLVMConstBitCast(klassName, i8PtrType) }
    }

    public func GetEnumCaseClassName(chirEnumType: EnumType, ctorIndex: Int64): String {
        let enumDef = chirEnumType.GetEnumDef()
        var name = enumDef.GetPackageName() + ":" + enumDef.GetSrcCodeIdentifier() + ":" + ctorIndex.toString()
        if (!CGType.GetOrCreate(this, chirEnumType).IsDynamicGI() && !chirEnumType.GetTypeArgs().isEmpty()) {
            name += "<" + GetTypeArgsQualifiedName(chirEnumType.GetTypeArgs()) + ">"
        }
        return name
    }

    public func GetOrCreateEnumCtorTIOrTT(chirEnumType: EnumType, ctorIndex: Int64): LLVMValueRef {
        let isTT = CGType.GetOrCreate(this, chirEnumType).IsDynamicGI()
        let className = GetEnumCaseClassName(chirEnumType, ctorIndex) + if (isTT) { ".tt" } else { ".ti" }
        let globalType = if (isTT) {
            CGType.GetOrCreateTypeTemplateType(cgCtx.GetLLVMContext())
        } else {
            CGType.GetOrCreateTypeInfoType(cgCtx.GetLLVMContext())
        }
        if (let Some(moduleHandle) <- module) {
            var global = LLVMNullValue()
            try (nameCString = unsafe { LibC.mallocCString(className) }.asResource()) {
                global = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameCString.value) }
                if (global.isNull()) {
                    global = unsafe { LLVMAddGlobal(moduleHandle.raw, globalType, nameCString.value) }
                    EnumCtorTIOrTTGenerator(this, chirEnumType, ctorIndex).Emit()
                }
            }
            return global
        }
        return LLVMNullValue()
    }

    public func ReleaseLLVMModule(): Option<LLVMModuleHandle> {
        FinalizeDebugInfo()
        let released = module
        module = None
        if (let Some(moduleHandle) <- released) {
            moduleHandle.EnableContextDisposalOnClose()
        }
        return released
    }

    public func ResetLLVMModule(newModule: LLVMModuleHandle): Unit {
        if (let Some(oldModule) <- module) {
            oldModule.close()
        }
        module = newModule
    }

    public func Clear(): Unit {
        FinalizeDebugInfo()
        if (let Some(moduleHandle) <- module) {
            moduleHandle.close()
            module = None
        }
        functions.clear()
        globalVariables.clear()
        localValueMapping.clear()
        basicBlocks.clear()
        linkNameUsedInMeta.clear()
        externalExtensionDefs.clear()
        nonExternalExtensionDefs.clear()
        extensionDefStartIndices.clear()
        extensionDefInterfaces.clear()
        cffi = None
        ghostCFuncArgValues.clear()
        enumClassificationStack.clear()
        cgCtx.Clear()
        cgCtx.GetLLVMContext().close()
    }

    public func GetOrInsertCGFunction(chirValue: Value, forWrapper!: Bool = false): CGFunction {
        let name = GetCodeGenGlobalName(chirValue)
        if (functions.contains(name)) {
            return functions[name]
        }
        let cgFuncType = CGType.GetOrCreateWithNode(this, chirValue, allowBasePtr: true, forWrapper: forWrapper)
        let functionType = if (let Some(chirType) <- chirValue.GetType()) {
            if (let Some(funcTy) <- (chirType as FuncType)) {
                if (funcTy.IsCFunc()) {
                    GetCGCFFI().GetCFuncType(funcTy)
                } else if (let Some(functionCGType) <- (cgFuncType as CGFunctionType)) {
                    functionCGType.GetLLVMFunctionType()
                } else {
                    cgFuncType.GetLLVMType()
                }
            } else if (let Some(functionCGType) <- (cgFuncType as CGFunctionType)) {
                functionCGType.GetLLVMFunctionType()
            } else {
                cgFuncType.GetLLVMType()
            }
        } else if (let Some(functionCGType) <- (cgFuncType as CGFunctionType)) {
            functionCGType.GetLLVMFunctionType()
        } else {
            cgFuncType.GetLLVMType()
        }
        let rawFunction = if (let Some(moduleHandle) <- module) {
            var createdFunction = LLVMNullValue()
            try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
                createdFunction = unsafe { LLVMGetNamedFunction(moduleHandle.raw, nameCString.value) }
                if (createdFunction.isNull()) {
                    createdFunction = unsafe { LLVMAddFunction(moduleHandle.raw, nameCString.value, functionType) }
                }
            }
            createdFunction
        } else {
            LLVMNullValue()
        }
        let cgFunc = CGFunction(rawFunction, cgFuncType, chirValue, this)
        AddGenericParamMappings(rawFunction, cgFunc, chirValue, cgFuncType)
        ApplyFunctionABIAttributes(rawFunction, chirValue, cgFuncType)
        MaybeSetCangjieGC(rawFunction, chirValue)
        functions[name] = cgFunc
        return cgFunc
    }

    private func AddGenericParamMappings(rawFunction: LLVMValueRef, cgFunc: CGFunction, chirValue: Value,
        cgType: CGType): Unit {
        let fn = (chirValue as Function) ?? return
        let functionType = (cgType as CGFunctionType) ?? return
        let _ = functionType.GetLLVMFunctionType()
        for (genericTy in fn.GetGenericTypeParams()) {
            if (let Some(paramIdx) <- functionType.GetGenericParamIndex(genericTy)) {
                let typeInfoParam = unsafe { LLVMGetParam(rawFunction, UInt32(paramIdx)) }
                AddGenericParamMapping(cgFunc, genericTy, { _: IRBuilder2 => typeInfoParam })
            }
        }
        if (let Some(outerInfoIndex) <- functionType.GetMethodTypeInfoIndex()) {
            AddOuterGenericParamMappings(rawFunction, cgFunc, fn, outerInfoIndex)
        }
    }

    private func AddGenericParamMapping(cgFunc: CGFunction, genericTy: GenericType,
        provider: (IRBuilder2) -> LLVMValueRef): Unit {
        cgFunc.genericParamsMap[genericTy.ToString()] = provider
        cgFunc.genericParamsMap[genericTy.GetIdentifier()] = provider
        cgFunc.genericParamsMap[genericTy.GetSrcCodeIdentifier()] = provider
    }

    private func AddOuterGenericParamMappings(rawFunction: LLVMValueRef, cgFunc: CGFunction, fn: Function,
        outerInfoIndex: Int64): Unit {
        let parentDef = fn.GetParentCustomTypeDef() ?? return
        let outerTypeInfo = unsafe { LLVMGetParam(rawFunction, UInt32(outerInfoIndex)) }
        if (!parentDef.GetGenericTypeParams().isEmpty()) {
            if (let Some(parentTy) <- parentDef.GetType()) {
                cgFunc.genericParamsMap[parentTy.ToString()] = { _: IRBuilder2 => outerTypeInfo }
            }
        }
        if (let Some(extendDef) <- (parentDef as ExtendDef)) {
            AddExtendGenericParamMappings(cgFunc, extendDef, outerTypeInfo)
            return
        }
        var idx: Int64 = 0
        for (genericTy in parentDef.GetGenericTypeParams()) {
            let capturedIdx = idx
            AddGenericParamMapping(cgFunc, genericTy, {
                irBuilder: IRBuilder2 => irBuilder.GetTypeInfoFromTypeInfoArgs(outerTypeInfo, capturedIdx)
            })
            idx++
        }
    }

    private func AddExtendGenericParamMappings(cgFunc: CGFunction, extendDef: ExtendDef,
        outerTypeInfo: LLVMValueRef): Unit {
        let extendedTy = extendDef.GetExtendedType() ??
            throw IllegalStateException("extend function has no extended type: " + extendDef.GetIdentifier())
        for (genericTy in extendDef.GetGenericTypeParams()) {
            let path = ArrayList<Int64>()
            if (!CollectGenericTypeInfoPath(extendedTy, genericTy, path)) {
                throw IllegalStateException("extend generic type is not reachable from extended type: " +
                    genericTy.ToString())
            }
            let capturedPath = CopyTypeInfoPath(path)
            AddGenericParamMapping(cgFunc, genericTy, {
                irBuilder: IRBuilder2 =>
                if (capturedPath.isEmpty()) {
                    outerTypeInfo
                } else {
                    LoadTypeInfoWithPath(irBuilder, outerTypeInfo, capturedPath)
                }
            })
        }
    }

    private func CollectGenericTypeInfoPath(srcTy: Type, genericTy: GenericType, path: ArrayList<Int64>): Bool {
        let baseTy = srcTy.StripAllRefs()
        if (baseTy.IsEqual(genericTy)) {
            return true
        }
        let typeArgs = baseTy.GetTypeArgs()
        var idx: Int64 = 0
        while (idx < typeArgs.size) {
            path.add(idx)
            if (CollectGenericTypeInfoPath(typeArgs[idx], genericTy, path)) {
                return true
            }
            path.remove(at: path.size - 1)
            idx++
        }
        return false
    }

    private func CopyTypeInfoPath(path: ArrayList<Int64>): ArrayList<Int64> {
        let out = ArrayList<Int64>()
        for (idx in path) {
            out.add(idx)
        }
        return out
    }

    private func LoadTypeInfoWithPath(irBuilder: IRBuilder2, rootTypeInfo: LLVMValueRef,
        path: ArrayList<Int64>): LLVMValueRef {
        var currentTypeInfo = rootTypeInfo
        for (idx in path) {
            currentTypeInfo = irBuilder.GetTypeInfoFromTypeInfoArgs(currentTypeInfo, idx)
        }
        return currentTypeInfo
    }

    public func GetOrInsertFunction(funcName: String, functionType: LLVMTypeRef): LLVMValueRef {
        if (let Some(moduleHandle) <- module) {
            var result = LLVMNullValue()
            try (nameCString = unsafe { LibC.mallocCString(funcName) }.asResource()) {
                result = unsafe { LLVMGetNamedFunction(moduleHandle.raw, nameCString.value) }
                if (result.isNull()) {
                    result = unsafe { LLVMAddFunction(moduleHandle.raw, nameCString.value, functionType) }
                }
            }
            return result
        }
        return LLVMNullValue()
    }

    public func GetExceptionIntrinsicPersonality(): LLVMValueRef {
        let returnType = unsafe { LLVMInt32TypeInContext(GetLLVMContext().raw) }
        let functionType = unsafe { LLVMFunctionType(returnType, CPointer<LLVMTypeRef>(), 0u32, 1) }
        if (cgCtx.GetCompileOptions().target.IsMacOS()) {
            return GetOrInsertFunction(CJ_PERSONALITY_FUNC_NAME, functionType)
        }
        if (let Some(moduleHandle) <- module) {
            var result = LLVMNullValue()
            var created = false
            try (nameCString = unsafe { LibC.mallocCString(CJ_PERSONALITY_FUNC_NAME) }.asResource()) {
                result = unsafe { LLVMGetNamedFunction(moduleHandle.raw, nameCString.value) }
                if (result.isNull()) {
                    result = unsafe { LLVMAddFunction(moduleHandle.raw, nameCString.value, functionType) }
                    created = true
                }
            }
            if (created && !result.isNull()) {
                AddLinkageTypeMetadata(result, LLVMLinkage.Private, false)
                try (entryBuilder = IRBuilder2(this)) {
                    let entryBlock = entryBuilder.CreateEntryBasicBlock(result, "entry")
                    try (personalityBuilder = IRBuilder2(this, entryBlock)) {
                        _ = personalityBuilder.CreateRet(unsafe { LLVMConstInt(returnType, 0u64, 0) })
                    }
                }
            }
            return result
        }
        return LLVMNullValue()
    }

    public func SetExceptionIntrinsicPersonality(rawFunction: LLVMValueRef): Unit {
        if (rawFunction.isNull()) {
            return
        }
        let personality = GetExceptionIntrinsicPersonality()
        if (!personality.isNull()) {
            unsafe { LLVMSetPersonalityFn(rawFunction, personality) }
        }
    }

    public func HasPersonalityFunction(rawFunction: LLVMValueRef): Bool {
        return !rawFunction.isNull() && unsafe { LLVMHasPersonalityFn(rawFunction) } != 0
    }

    public func GetPersonalityFunction(rawFunction: LLVMValueRef): LLVMValueRef {
        if (rawFunction.isNull() || !HasPersonalityFunction(rawFunction)) {
            return LLVMNullValue()
        }
        return unsafe { LLVMGetPersonalityFn(rawFunction) }
    }

    private func MaybeAttachExceptionPersonality(rawFunction: LLVMValueRef, chirValue: Value): Unit {
        if (rawFunction.isNull() || !chirValue.IsFuncWithBody() || chirValue.TestAttr(Attribute.FOREIGN) ||
            chirValue.TestAttr(Attribute.IMPORTED)) {
            return
        }
        if (let Some(functionValue) <- (chirValue as Function)) {
            if (functionValue.IsCFFIWrapper()) {
                return
            }
        }
        SetExceptionIntrinsicPersonality(rawFunction)
    }

    private func MaybeSetCangjieGC(rawFunction: LLVMValueRef, chirValue: Value): Unit {
        if (rawFunction.isNull()) {
            return
        }
        if (let Some(chirTy) <- chirValue.GetType()) {
            if (let Some(funcTy) <- (chirTy as FuncType)) {
                if (!funcTy.IsCFunc()) {
                    SetCangjieGC(rawFunction)
                }
            }
        }
    }

    private func ApplyFunctionABIAttributes(rawFunction: LLVMValueRef, chirValue: Value, cgFuncType: CGType): Unit {
        if (rawFunction.isNull()) {
            return
        }
        if (let Some(functionCGType) <- (cgFuncType as CGFunctionType)) {
            if (functionCGType.HasBasePtr()) {
                AddFnStringAttr(rawFunction, STRUCT_MUT_FUNC_ATTR)
                AddFnStringAttr(rawFunction, THIS_PARAM_HAS_BP)
            }
            if (let Some(chirType) <- chirValue.GetType()) {
                if (let Some(funcType) <- (chirType as FuncType)) {
                    if (funcType.IsCFunc()) {
                        GetCGCFFI().AddFunctionAttr(funcType, rawFunction)
                        return
                    }
                }
            }
            if (!functionCGType.HasSRet()) {
                return
            }
            if (let Some(chirType) <- chirValue.GetType()) {
                if (let Some(funcType) <- (chirType as FuncType)) {
                    let retCGType = CGType.GetOrCreate(this, funcType.GetReturnType())
                    AddSRetAttribute(rawFunction, retCGType.GetLLVMType())
                    AddNoAliasAttribute(rawFunction)
                    return
                }
            }
            AddSRetAttribute(rawFunction)
            AddNoAliasAttribute(rawFunction)
        }
    }

    public func GetOrInsertGlobalVariable(chirGV: GlobalVar): CGValue {
        let name = GetCodeGenGlobalName(chirGV)
        if (globalVariables.contains(name)) {
            return globalVariables[name]
        }
        let chirType = if (let Some(valueType) <- chirGV.GetType()) {
            valueType
        } else {
            throw IllegalArgumentException("global variable has no CHIR type: " + name)
        }
        let cgType = CGType.GetOrCreate(this, chirType)
        let globalType = if (let Some(elementType) <- cgType.GetPointerElementType()) {
            elementType.GetLLVMType()
        } else {
            cgType.GetLLVMType()
        }
        let rawGlobal = if (let Some(moduleHandle) <- module) {
            var createdGlobal = LLVMNullValue()
            try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
                createdGlobal = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameCString.value) }
                if (createdGlobal.isNull()) {
                    createdGlobal = unsafe { LLVMAddGlobal(moduleHandle.raw, globalType, nameCString.value) }
                }
            }
            createdGlobal
        } else {
            LLVMNullValue()
        }
        let cgValue = CGValue(rawGlobal, cgType)
        globalVariables[name] = cgValue
        return cgValue
    }

    public func GetMappedValue(chirValue: Value): Option<CGValue> {
        if (let Some(functionValue) <- (chirValue as Function)) {
            let name = GetCodeGenGlobalName(functionValue)
            if (functions.contains(name)) {
                return functions[name]
            }
            return None
        }
        if (let Some(globalValue) <- (chirValue as GlobalVar)) {
            let name = GetCodeGenGlobalName(globalValue)
            if (globalVariables.contains(name)) {
                return globalVariables[name]
            }
            return None
        }
        if (localValueMapping.contains(chirValue)) {
            return localValueMapping[chirValue]
        }
        return None
    }

    public func SetOrUpdateMappedCGValue(chirValue: Value, value: CGValue): Unit {
        if (let Some(functionValue) <- (chirValue as Function)) {
            if (let Some(cgFunction) <- (value as CGFunction)) {
                functions[GetCodeGenGlobalName(functionValue)] = cgFunction
                return
            }
            throw IllegalArgumentException("function mapping requires CGFunction: " + GetCodeGenGlobalName(functionValue))
        }
        if (let Some(globalValue) <- (chirValue as GlobalVar)) {
            globalVariables[GetCodeGenGlobalName(globalValue)] = value
            return
        }
        localValueMapping[chirValue] = value
    }

    public func RemoveMappedCGValue(chirValue: Value): Unit {
        if (let Some(functionValue) <- (chirValue as Function)) {
            functions.remove(GetCodeGenGlobalName(functionValue))
            return
        }
        if (let Some(globalValue) <- (chirValue as GlobalVar)) {
            globalVariables.remove(GetCodeGenGlobalName(globalValue))
            return
        }
        localValueMapping.remove(chirValue)
    }

    public func GetMappedCGValue(chirValue: Value): CGValue {
        if (let Some(mappedValue) <- GetMappedValue(chirValue)) {
            return mappedValue
        }
        if (let Some(functionValue) <- (chirValue as Function)) {
            return GetOrInsertCGFunction(functionValue)
        }
        if (let Some(globalValue) <- (chirValue as GlobalVar)) {
            return GetOrInsertGlobalVariable(globalValue)
        }
        CJC_ASSERT_WITH_MSG(false, "Should not reach here: value not dominate all uses in CHIR.")
        throw IllegalStateException("Should not reach here: value not dominate all uses in CHIR.")
    }

    public func GetCGTypeForExpressionResult(valueType: Type, ownerExpr: Expression): CGType {
        if (ownerExpr.GetExprKind() != ExprKind.TUPLE) {
            return CGType.GetOrCreate(this, valueType)
        }
        if (ShouldUseRefCGTypeForTupleExpressionResult(valueType)) {
            return CGType.GetOrCreate(this, cgCtx.GetCGPkgContext().GetCHIRBuilder().context.GetRefTy(valueType))
        }
        return CGType.GetOrCreate(this, valueType)
    }

    public func SetOrUpdateMappedBB(chirBlock: Block, llvmBlock: LLVMBasicBlockRef): Unit {
        basicBlocks[chirBlock.nodeId] = llvmBlock
    }

    public func GetMappedBB(chirBlock: Block): Option<LLVMBasicBlockRef> {
        if (basicBlocks.contains(chirBlock.nodeId)) {
            return basicBlocks[chirBlock.nodeId]
        }
        return None
    }

    public func CreateOrGetMappedBB(irBuilder: IRBuilder2, functionValue: LLVMValueRef, chirBlock: Block): LLVMBasicBlockRef {
        if (let Some(mappedBlock) <- GetMappedBB(chirBlock)) {
            return mappedBlock
        }
        let blockName = PREFIX_FOR_BB_NAME + chirBlock.GetIdentifierWithoutPrefix()
        let createdBlock = irBuilder.CreateBasicBlockAtEnd(functionValue, blockName)
        SetOrUpdateMappedBB(chirBlock, createdBlock)
        return createdBlock
    }

    public func MapFunctionParameters(chirFunc: Function, cgFunc: CGFunction): Unit {
        MaybeAttachExceptionPersonality(cgFunc.GetRawFunction(), chirFunc)
        if (let Some(chirTy) <- chirFunc.GetType()) {
            if (let Some(funcTy) <- (chirTy as FuncType)) {
                if (funcTy.IsCFunc()) {
                    MapCFuncParameters(chirFunc, cgFunc, funcTy)
                    return
                }
            }
        }
        var idx: Int64 = 0
        while (idx < chirFunc.GetNumOfParams()) {
            let param = chirFunc.GetParam(idx)
            let rawArg = cgFunc.GetArgByIndexFromCHIR(idx)
            let paramCGType = if (let Some(paramTy) <- param.GetType()) {
                let valueCGType = GetCGTypeForValue(param)
                if (!paramTy.IsRef() && (paramTy.IsStruct() || paramTy.IsTuple() ||
                    valueCGType.IsStructType() || valueCGType.IsVArrayType())) {
                    CGType.GetOrCreate(this, cgCtx.GetCGPkgContext().GetCHIRBuilder().context.GetRefTy(paramTy))
                } else {
                    valueCGType
                }
            } else {
                GetCGTypeForValue(param)
            }
            if (chirFunc.IsConstructor() && idx == 0) {
                AddParamAttr(cgFunc.GetRawFunction(), UInt32(idx), "noalias")
            }
            if (paramCGType.IsStructPtrType() || paramCGType.IsVArrayPtrType()) {
                AddParamAttr(cgFunc.GetRawFunction(), UInt32(idx), "noalias")
            }
            SetOrUpdateMappedCGValue(param, CGValue(rawArg, paramCGType))
            idx++
        }
    }

    private func MapCFuncParameters(chirFunc: Function, cgFunc: CGFunction, chirFuncTy: FuncType): Unit {
        if (chirFunc.GetNumOfParams() == 0) {
            return
        }
        var builder: Option<IRBuilder2> = None
        var llvmArgIdx: UInt32 = 0u32
        if (HasAttributeAtIndex(cgFunc.GetRawFunction(), 1u32, "sret")) {
            llvmArgIdx++
        }
        var chirArgIdx: Int64 = 0
        while (chirArgIdx < chirFunc.GetNumOfParams()) {
            let chirFuncArg = chirFunc.GetParam(chirArgIdx)
            let chirFuncArgTy = chirFuncArg.GetType().getOrThrow()
            var llvmValue = LLVMNullValue()
            if (IsZeroSizedTypeInC(this, chirFuncArgTy)) {
                let localBuilder = InitCFuncParamBuilder(builder, chirFunc, cgFunc)
                builder = localBuilder
                llvmValue = localBuilder.CreateEntryAlloca(CGType.GetOrCreate(this, chirFuncArgTy))
            } else {
                llvmValue = unsafe { LLVMGetParam(cgFunc.GetRawFunction(), llvmArgIdx) }
                let argIt = LLVMFuncArgIt(cgFunc.GetRawFunction(), llvmArgIdx)
                if (GetCGCFFI().NeedProcessParam(chirFuncTy, chirArgIdx)) {
                    let localBuilder = InitCFuncParamBuilder(builder, chirFunc, cgFunc)
                    builder = localBuilder
                    llvmValue = ProcessCFuncParamOnDemand(chirFuncArgTy, argIt, localBuilder)
                    llvmArgIdx = argIt.idx
                }
                llvmArgIdx++
            }
            FixedCGTypeOfFuncArg(this, chirFuncArg, llvmValue)
            chirArgIdx++
        }
        if (let Some(localBuilder) <- builder) {
            localBuilder.close()
        }
    }

    private func InitCFuncParamBuilder(builder: Option<IRBuilder2>, chirFunc: Function,
        cgFunc: CGFunction): IRBuilder2 {
        if (let Some(existing) <- builder) {
            return existing
        }
        let created = IRBuilder2(this)
        created.SetInsertCGFunction(cgFunc)
        let chirEntryBB = chirFunc.GetEntryBlock().getOrThrow()
        let entryBB = created.CreateBasicBlockAtEnd(cgFunc.GetRawFunction(),
            "entry:" + chirEntryBB.GetIdentifierWithoutPrefix())
        created.SetInsertPoint(entryBB)
        SetOrUpdateMappedBB(chirEntryBB, entryBB)
        return created
    }

    private func ProcessCFuncParamOnDemand(chirParamTy: Type, arg: LLVMFuncArgIt,
        builder: IRBuilder2): LLVMValueRef {
        let cgType = CGType.GetOrCreate(this, chirParamTy)
        if (chirParamTy.IsVArray()) {
            return builder.CreateBitCast(arg.GetValue(), unsafe { LLVMPointerType(cgType.GetLLVMType(), 0u32) })
        }
        let place = builder.CreateEntryAlloca(cgType)
        GetCGCFFI().ProcessParam(chirParamTy, arg, place, builder)
        return place
    }

    public func EraseUselessInstsAndDeclarations(): Unit {
        EraseUselessInstsAndDeclarationsImpl(this)
    }

    public func EraseUselessGVAndFunctions(): Unit {
        EraseUselessGVAndFunctionsImpl(this)
    }

    public func Opt(): Unit {
        for ((_, cgFunction) in functions) {
            cgFunction.Opt()
        }
    }

    public func Verify(): Bool {
        if (let Some(moduleHandle) <- module) {
            let verifyResult = VerifyModule(moduleHandle)
            if (!verifyResult.message.isEmpty()) {
                eprintln(verifyResult.message)
            }
            return verifyResult.ok
        }
        return false
    }

    private func InitModuleFlags(moduleHandle: LLVMModuleHandle): Unit {
        AddUInt32ModuleFlag(moduleHandle.raw, "CJBC", 1u64)
        AddUInt32ModuleFlag(moduleHandle.raw, "Cangjie_OPT", 0u64)
        if (cgCtx.GetCompileOptions().target.IsMacOS()) {
            AddStringModuleFlag(moduleHandle.raw, "Cangjie_PACKAGE_ID",
                CGModule.NormalizePackageIdentifier(cgCtx.GetCurrentPkgName()))
        }
    }

    public func InitDebugInfo(): Unit {
        if (let Some(moduleHandle) <- module) {
            AddUInt32ModuleFlag(moduleHandle.raw, "Debug Info Version",
                UInt64(unsafe { LLVMDebugMetadataVersion() }))
            AddUInt32ModuleFlag(moduleHandle.raw, "Dwarf Version", DWARF_VERSION)
            let builder = DIBuilder(this)
            builder.CreateCompileUnit(moduleHandle.name)
            builder.CreateNameSpace(cgCtx.GetCurrentPkgName())
            diBuilder = builder
        }
    }

    public func GetDIBuilder(): Option<DIBuilder> { return diBuilder }

    public func FinalizeDebugInfo(): Unit {
        if (let Some(builder) <- diBuilder) {
            builder.Finalize()
            diBuilder = None
        }
    }

    private func AddStringModuleFlag(moduleRef: LLVMModuleRef, key: String, value: String): Unit {
        try (keyCString = unsafe { LibC.mallocCString(key) }.asResource(),
            valueCString = unsafe { LibC.mallocCString(value) }.asResource()) {
            let metadata = unsafe {
                LLVMMDStringInContext2(GetLLVMContext().raw, valueCString.value, UIntNative(value.size))
            }
            unsafe {
                LLVMAddModuleFlag(moduleRef, LLVM_MODULE_FLAG_WARNING, keyCString.value,
                    UIntNative(key.size), metadata)
            }
        }
    }

    private func AddUInt32ModuleFlag(moduleRef: LLVMModuleRef, key: String, value: UInt64): Unit {
        let metadata = CreateUInt32Metadata(GetLLVMContext(), value)
        try (keyCString = unsafe { LibC.mallocCString(key) }.asResource()) {
            unsafe {
                LLVMAddModuleFlag(moduleRef, LLVM_MODULE_FLAG_WARNING, keyCString.value,
                    UIntNative(key.size), metadata)
            }
        }
    }

    public func GenerateUnitTypeValue(): LLVMValueRef {
        let unitType = CGType.GetUnitType(GetLLVMContext())
        if (let Some(moduleHandle) <- module) {
            var unitValue = LLVMNullValue()
            try (unitName = unsafe { LibC.mallocCString(UNIT_VAL_STR) }.asResource()) {
                unitValue = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, unitName.value) }
                if (unitValue.isNull()) {
                    unitValue = unsafe { LLVMAddGlobal(moduleHandle.raw, unitType, unitName.value) }
                    unsafe { LLVMSetInitializer(unitValue, LLVMGetUndef(unitType)) }
                    let linkage = if (cgCtx.GetCompileOptions().target.IsMinGW()) {
                        LLVMLinkage.Private
                    } else {
                        LLVMLinkage.WeakODR
                    }
                    AddLinkageTypeMetadata(unitValue, linkage, false)
                }
            }
            return unitValue
        }
        return unsafe { LLVMConstNull(unitType) }
    }

    public func GetModuleTargetData(): LLVMTargetDataHandle {
        if (let Some(moduleHandle) <- module) {
            return LLVMTargetDataHandle.FromModule(moduleHandle)
        }
        return LLVMTargetDataHandle(LLVMNullTargetData(), owned: false)
    }

    public func CopyDataLayoutString(): String {
        return GetModuleTargetData().CopyStringRep()
    }

    public func GetPointerSize(addressSpace!: UInt32 = 0u32): UInt32 {
        return GetModuleTargetData().GetPointerSize(addressSpace: addressSpace)
    }

    public func GetIntPtrType(addressSpace!: UInt32 = 0u32): LLVMTypeRef {
        return GetModuleTargetData().GetIntPtrType(GetLLVMContext(), addressSpace: addressSpace)
    }

    public func GetTypeSize(codeGenType: LLVMTypeRef): UInt64 {
        return GetModuleTargetData().GetTypeAllocSize(codeGenType)
    }

    public func GetTypeSizeInBits(codeGenType: LLVMTypeRef): UInt64 {
        return GetModuleTargetData().GetTypeSizeInBits(codeGenType)
    }

    public func GetTypeStoreSize(codeGenType: LLVMTypeRef): UInt64 {
        return GetModuleTargetData().GetTypeStoreSize(codeGenType)
    }

    public func GetABITypeAlignment(codeGenType: LLVMTypeRef): UInt32 {
        return GetModuleTargetData().GetABITypeAlignment(codeGenType)
    }

    public func GetCallFrameTypeAlignment(codeGenType: LLVMTypeRef): UInt32 {
        return GetModuleTargetData().GetCallFrameTypeAlignment(codeGenType)
    }

    public func GetPrefTypeAlignment(codeGenType: LLVMTypeRef): UInt32 {
        return GetModuleTargetData().GetPrefTypeAlignment(codeGenType)
    }

    public func GetPreferredAlignmentOfGlobal(globalVar: LLVMValueRef): UInt32 {
        return GetModuleTargetData().GetPreferredAlignmentOfGlobal(globalVar)
    }

    public func GetElementContainingOffset(structTy: LLVMTypeRef, offset: UInt64): UInt32 {
        return GetModuleTargetData().GetElementContainingOffset(structTy, offset)
    }

    public func GetOffsetOfElement(structTy: LLVMTypeRef, element: UInt32): UInt64 {
        return GetModuleTargetData().GetOffsetOfElement(structTy, element)
    }

    public func ClearLinkNameUsedInMeta(): Unit { linkNameUsedInMeta.clear() }
    public func IsLinkNameUsedInMeta(linkageName: String): Bool { return linkNameUsedInMeta.contains(linkageName) }
    public func GetLinkNamesUsedInMeta(): HashSet<String> { return linkNameUsedInMeta }
    public func AddNonExternalExtensionDef(extensionDef: LLVMValueRef): Unit { nonExternalExtensionDefs.add(extensionDef) }
    public func AddExternalExtensionDef(extensionDef: LLVMValueRef): Unit { externalExtensionDefs.add(extensionDef) }
    public func GetNonExternalExtensionDefs(): ArrayList<LLVMValueRef> { return nonExternalExtensionDefs }
    public func GetExternalExtensionDefs(): ArrayList<LLVMValueRef> { return externalExtensionDefs }
    public func GetNonExternalExtensionDefsNum(): Int64 { return nonExternalExtensionDefs.size }

    public func RegisterExtensionDefStart(chirTy: Type, startIdx: Int64): Unit {
        extensionDefStartIndices[CGType.GetRuntimeTypeName(chirTy.StripAllRefs())] = startIdx
    }

    public func GetExtensionDefStart(chirTy: Type): Option<Int64> {
        return extensionDefStartIndices.get(CGType.GetRuntimeTypeName(chirTy.StripAllRefs()))
    }

    public func RegisterExtensionDefInterfaces(chirTy: Type, interfaces: ArrayList<MTableInterfaceInfo>): Unit {
        let copied = ArrayList<MTableInterfaceInfo>()
        for (interfaceInfo in interfaces) {
            copied.add(interfaceInfo)
        }
        extensionDefInterfaces[CGType.GetRuntimeTypeName(chirTy.StripAllRefs())] = copied
    }

    public func GetExtensionDefInterfaces(chirTy: Type): ArrayList<MTableInterfaceInfo> {
        let out = ArrayList<MTableInterfaceInfo>()
        if (let Some(interfaces) <- extensionDefInterfaces.get(CGType.GetRuntimeTypeName(chirTy.StripAllRefs()))) {
            for (interfaceInfo in interfaces) {
                out.add(interfaceInfo)
            }
        }
        return out
    }

    public func EnterEnumClassification(typeKey: String): Bool {
        if (enumClassificationStack.contains(typeKey)) {
            return false
        }
        enumClassificationStack.add(typeKey)
        return true
    }

    public func ExitEnumClassification(typeKey: String): Unit {
        enumClassificationStack.remove(typeKey)
    }

    public func IsEnumClassificationActive(typeKey: String): Bool {
        return enumClassificationStack.contains(typeKey)
    }

    private func CreateCGCFFI(): CGCFFI {
        let target = cgCtx.GetCompileOptions().target
        if (target.os == OSType.WINDOWS && target.arch == ArchType.X86_64) {
            return WindowsAmd64CJNativeCGCFFI(this)
        } else if ((target.os == OSType.LINUX || target.os == OSType.DARWIN) && target.arch == ArchType.X86_64) {
            return LinuxAmd64CJNativeCGCFFI(this)
        } else if (target.arch == ArchType.AARCH64 && target.os == OSType.LINUX) {
            return LinuxAarch64CJNativeCGCFFI(this)
        } else if (target.arch == ArchType.AARCH64 && target.os == OSType.DARWIN) {
            return CreateAppleAArch64CGCFFI()
        } else if (target.arch == ArchType.AARCH64 && target.os == OSType.IOS) {
            return CreateAppleAArch64CGCFFI()
        } else if (target.arch == ArchType.ARM32) {
            return LinuxOhosArm32CJNativeCGCFFI(this)
        }
        return LinuxAmd64CJNativeCGCFFI(this)
    }

    @When[os == "macOS"]
    private func CreateAppleAArch64CGCFFI(): CGCFFI {
        return MacAArch64CJNativeCGCFFI(this)
    }

    @When[os != "macOS"]
    private func CreateAppleAArch64CGCFFI(): CGCFFI {
        return LinuxAmd64CJNativeCGCFFI(this)
    }

    public static func GetDataLayoutString(target: TripleInfo): String {
        if (target.IsMacOS() && target.arch == ArchType.AARCH64) {
            return "e-m:o-i64:64-i128:128-n32:64-S128"
        }
        if (target.arch == ArchType.ARM32) {
            return "e-m:e-p:32:32-Fi8-i64:64-v128:64:128-a:0:32-n32-S64"
        }
        if (target.IsMinGW()) {
            return "e-m:w-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
        }
        return "e-m:e-i64:64-f80:128-n8:16:32:64-S128"
    }

    public static func GetTargetTripleString(target: TripleInfo): String {
        if (target.IsMacOS()) {
            if (target.arch == ArchType.AARCH64) {
                return "arm64-apple-macosx12.0.0"
            }
            return target.ArchToString() + "-apple-macosx12.0.0"
        }
        if (target.arch == ArchType.AARCH64 && target.env == EnvironmentType.OHOS) {
            return target.ArchToString() + "-unknown-linux-ohos"
        }
        if (target.arch == ArchType.ARM32) {
            return "armv7a-linux-gnu"
        }
        let defaultTriple = LLVMGetDefaultTargetTripleString()
        if (!defaultTriple.isEmpty()) {
            return defaultTriple
        }
        return target.GetEffectiveTripleString()
    }

    private static func NormalizePackageIdentifier(pkgName: String): String {
        let out = ArrayList<UInt8>()
        for (byte in pkgName.toArray()) {
            if (byte == b'/') {
                out.add(b'.')
            } else {
                out.add(byte)
            }
        }
        return String.fromUtf8(out.toArray())
    }

    private func GetCGTypeForValue(chirValue: Value): CGType {
        if (let Some(valueType) <- chirValue.GetType()) {
            return CGType.GetOrCreate(this, valueType)
        }
        return CGType(this, cgCtx, Type(TypeKind.TYPE_INVALID))
    }

    private func ShouldUseRefCGTypeForTupleExpressionResult(valueType: Type): Bool {
        let stripped = valueType.StripAllRefs()
        if (stripped.IsStruct() || stripped.IsTuple()) {
            return true
        }
        if (let Some(enumTy) <- (stripped as EnumType)) {
            if (let Some(enumCGType) <- (CGType.GetOrCreate(this, enumTy) as CGEnumType)) {
                return enumCGType.IsOptionLikeNonRef() || enumCGType.IsAllAssociatedValuesAreNonRef() ||
                    enumCGType.IsZeroSizeEnum()
            }
        }
        return false
    }
}
