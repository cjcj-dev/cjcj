package cjcj::codegen

import std.collection.*
import cjcj::basic.SourceManager
import cjcj::chir.Attribute
import cjcj::chir.DebugLocation
import cjcj::chir.ExprKind
import cjcj::chir.FuncType
import cjcj::chir.FuncKind
import cjcj::chir.Function
import cjcj::chir.GenericType
import cjcj::chir.Position
import cjcj::chir.Type
import cjcj::mangle.MANGLE_CANGJIE_PREFIX
import cjcj::mangle.MANGLE_FUNC_PARA_INIT_PREFIX
import cjcj::mangle.MANGLE_GLOBAL_VARIABLE_INIT_PREFIX
import cjcj::option.MockMode
import cjcj::chir.ClassType
import cjcj::chir.BoxType
import cjcj::chir.CustomType
import cjcj::chir.CustomTypeDef
import cjcj::chir.CustomDefKind
import cjcj::chir.EnumType
import cjcj::chir.EnumCtorInfo
import cjcj::chir.ExtendDef
import cjcj::chir.NumericType
import cjcj::chir.MemberVarInfo
import cjcj::chir.CPointerType
import cjcj::chir.CStringType
import cjcj::chir.RawArrayType
import cjcj::chir.RefType
import cjcj::chir.StructType
import cjcj::chir.TupleType
import cjcj::chir.TypeKind
import cjcj::chir.VArrayType
import cjcj::chir.GetCustomTypeIdentifier
import cjcj::chir.GetFuncTypeWithoutThisPtrFromAutoEnvBaseType
import cjcj::utils.{CJC_ASSERT, StaticCast}

// GAP_TODO(C07-debug-location-parity):
// - EmitExpressionIR.cpp:64-66 enableCompileDebug parameter loads
//   call IRBuilder2::CreateLoadInstForParameter before dispatch; this is not ported.
// - Dispatcher-level EmitLocation sites still not ported from C++:
//   ApplyImpl.cpp:346; ArithmeticOpImpl.cpp:342,370; TupleExprImpl.cpp:199,236;
//   MemoryExprDispatcher.cpp:73,108,185,264,285, especially line 108 removable=true;
//   OtherExprDispatcher.cpp has multiple dispatcher-level sites; IRBuilder.cpp:217,264.
let LLVM_MODULE_FLAG_WARNING: Int32 = 1
private let LLVM_DWARF_LANG_CPP14: Int32 = 32
private let LLVM_DWARF_EMISSION_NONE: Int32 = 0
private let LLVM_DWARF_EMISSION_FULL: Int32 = 1
private let LLVM_DWARF_EMISSION_LINE_TABLES_ONLY: Int32 = 2
private let DW_ATE_signed: UInt32 = 5u32
private let DW_ATE_unsigned: UInt32 = 7u32
private let DW_ATE_unsigned_char: UInt32 = 8u32
private let DW_ATE_float: UInt32 = 4u32
private let DW_ATE_boolean: UInt32 = 2u32
private let DW_ATE_UTF: UInt32 = 16u32
private let DW_TAG_const_type: UInt32 = 0x26u32
private let DW_TAG_typedef: UInt32 = 0x16u32
private let DW_TAG_subprogram: UInt32 = 0x2eu32
private let DW_TAG_class_type: UInt32 = 0x02u32
private let FlagZero: UInt32 = 0u32
private let FlagArtificial: UInt32 = 64u32
private let FlagVirtual: UInt32 = 32u32
private let FlagPrototyped: UInt32 = 256u32
private let FlagObjectPointer: UInt32 = 1024u32
private let FlagProtected: UInt32 = 2u32
private let FlagPublic: UInt32 = 3u32
private let FlagStaticMember: UInt32 = 4096u32
private let FlagTypePassByReference: UInt32 = 8388608u32
private let SPFlagPureVirtual: UInt32 = 2u32
private let SPFlagDefinition: UInt32 = 8u32
let DWARF_VERSION: UInt64 = 4u64
private let INST_VIRTUAL_FUNC: String = "$InstVirtualFunc"
private let GENERIC_VIRTUAL_FUNC: String = "$GenericVirtualFunc"

public class DIBuilder {
    private let cgMod: CGModule
    private let raw: LLVMDIBuilderRef
    private let enabled: Bool
    private let enableLineInfo: Bool
    private var finalized: Bool = false
    private var defaultFile: LLVMMetadataRef = LLVMNullMetadata()
    private var compileUnit: LLVMMetadataRef = LLVMNullMetadata()
    private var namespaceScope: LLVMMetadataRef = LLVMNullMetadata()
    private var refDIType: LLVMMetadataRef = LLVMNullMetadata()
    private var curScope: LLVMMetadataRef = LLVMNullMetadata()
    private var curLocation: Position = Position()
    private var needSubprogram: Bool = false
    private var paramNo: UIntNative = 0
    private var genericID: UInt64 = 0
    private let lexicalBlocks: HashMap<String, LLVMMetadataRef> = HashMap<String, LLVMMetadataRef>()
    private let typeCache: HashMap<Int64, LLVMMetadataRef> = HashMap<Int64, LLVMMetadataRef>()
    private let enumCtorCache: HashMap<Int64, LLVMMetadataRef> = HashMap<Int64, LLVMMetadataRef>()

    public init(cgMod: CGModule) {
        this.cgMod = cgMod
        let options = cgMod.GetCGContext().GetCompileOptions()
        enabled = options.enableCompileDebug || options.enableCoverage
        enableLineInfo = options.displayLineInfo
        raw = if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
            unsafe { LLVMCreateDIBuilder(moduleHandle.raw) }
        } else {
            LLVMNullDIBuilder()
        }
    }

    public func CreateCompileUnit(pkgName: String): Unit {
        if (raw.isNull()) {
            return
        }
        var compileUnitName = pkgName
        let options = cgMod.GetCGContext().GetCompileOptions()
        if (options.enableCoverage) {
            if (options.parseTest && !options.compileTestsOnly) {
                compileUnitName += SourceManager.testPkgSuffix
            }
            if (pkgName.contains(".")) {
                compileUnitName += ".pkg"
            }
        }
        defaultFile = CreateFile(pkgName, ".")
        let unitFile = CreateFile(compileUnitName, ".")
        let emissionKind = LLVM_DWARF_EMISSION_FULL
        try (producer = unsafe { LibC.mallocCString("Cangjie Compiler") }.asResource(),
            empty = unsafe { LibC.mallocCString("") }.asResource()) {
            compileUnit = unsafe {
                LLVMDIBuilderCreateCompileUnit(raw, LLVM_DWARF_LANG_CPP14, unitFile, producer.value,
                    UIntNative("Cangjie Compiler".size), 0, empty.value, 0, 0u32, empty.value, 0,
                    emissionKind, 0u32, 0, 0, empty.value, 0, empty.value, 0)
            }
        }
    }

    public func CreateNameSpace(pkgName: String): Unit {
        if (raw.isNull() || compileUnit.isNull()) {
            return
        }
        try (pkgCString = unsafe { LibC.mallocCString(pkgName) }.asResource()) {
            namespaceScope = unsafe {
                LLVMDIBuilderCreateNameSpace(raw, compileUnit, pkgCString.value, UIntNative(pkgName.size), 0)
            }
        }
    }

    public func SetSubprogram(chirFunc: Function, function: LLVMValueRef): Unit {
        if (!enabled && !enableLineInfo) {
            return
        }
        // Reset the parameter number when generating a brand new one.
        paramNo = 1
        let funcTy = DeRef(chirFunc.GetType().getOrThrow())
        let lineInfoOnly = !enabled && enableLineInfo
        let funcName = if (lineInfoOnly) { "" } else { chirFunc.GetIdentifierWithoutPrefix() }
        let funcIdentifier = if (lineInfoOnly || IsParaInitFunc(chirFunc)) {
            ""
        } else {
            GenerateGenericFuncName(chirFunc.GetSrcCodeIdentifier(), chirFunc.GetOriginalGenericTypeParams())
        }
        let position = if (let Some(rawMethod) <- chirFunc.GetWrappedRawMethod()) {
            rawMethod.GetDebugLocation()
        } else {
            chirFunc.GetDebugLocation()
        }
        let diFile = GetOrCreateFile(position)
        let isGV = funcName.startsWith(MANGLE_CANGJIE_PREFIX + MANGLE_GLOBAL_VARIABLE_INIT_PREFIX)
        let isCompilerAddInit = chirFunc.GetSrcCodeIdentifier() == "init" && chirFunc.TestAttr(Attribute.NO_DEBUG_INFO)
        var scopeLine = if (isGV) { 0u32 } else { position.GetBeginPos().line }
        scopeLine = if (isCompilerAddInit) { position.GetEndPos().line } else { scopeLine }
        let scopeAndDecl = SetSubprogramPart2(chirFunc, funcName)
        let scope = scopeAndDecl[0]
        let declaration = scopeAndDecl[1]
        let funcType = if (lineInfoOnly || chirFunc.TestAttr(Attribute.NO_DEBUG_INFO)) {
            CreateDefaultFunctionType()
        } else {
            CreateFuncType((funcTy as FuncType).getOrThrow())
        }
        var flags = FlagPrototyped
        flags |= if (isGV) { FlagArtificial } else { FlagZero }
        if ((chirFunc.GetSrcCodeIdentifier() == INST_VIRTUAL_FUNC ||
            chirFunc.GetSrcCodeIdentifier() == GENERIC_VIRTUAL_FUNC) && scopeLine == 0u32) {
            // To properly step in to the closure function body, need to set a valid value for scopeLine.
            scopeLine = 1u32
        }
        let subprogram = CreateFunction(scope, funcIdentifier, funcName, diFile, scopeLine, funcType, scopeLine,
            flags, SPFlagDefinition, LLVMNullMetadata(), declaration)
        unsafe { LLVMSetSubprogram(function, subprogram) }
        curScope = subprogram
    }

    @When[os == "macOS" || os == "iOS"]
    private func SetSubprogramPart2(chirFunc: Function, funcName: String): (LLVMMetadataRef, LLVMMetadataRef) {
        let _ = chirFunc
        let _ = funcName
        return (namespaceScope, LLVMNullMetadata())
    }

    @When[os != "macOS" && os != "iOS"]
    private func SetSubprogramPart2(chirFunc: Function, funcName: String): (LLVMMetadataRef, LLVMMetadataRef) {
        var scope = namespaceScope
        var declaration = LLVMNullMetadata()
        let isMemberFunc = chirFunc.GetParentCustomTypeDef().isSome()
        if (isMemberFunc && cgMod.GetCGContext().GetCompileOptions().enableCompileDebug) {
            let parentTy = GetOuterTypeOfMemberFunc(chirFunc)
            let isWrapperFunc = if (let Some(classTy) <- (parentTy as ClassType)) {
                classTy.IsAutoEnv()
            } else {
                false
            }
            if (!parentTy.IsPrimitive() && !isWrapperFunc) {
                scope = GetOrCreateType(parentTy)
                let realScope = if (unsafe { LLVMSelfhostDINodeGetTag(scope) } == DW_TAG_typedef) {
                    unsafe { LLVMSelfhostDIDerivedTypeGetBaseType(scope) }
                } else {
                    scope
                }
                for (element in getElements(realScope)) {
                    if (unsafe { LLVMSelfhostDINodeGetTag(element) } != DW_TAG_subprogram) {
                        continue
                    }
                    var linkageName = ""
                    try (length = LibC.malloc<UIntNative>().asResource()) {
                        let rawName = unsafe { LLVMSelfhostDISubprogramGetLinkageName(element, length.value) }
                        linkageName = LLVMCStringToString(rawName, unsafe { length.value.read() }) ?? ""
                    }
                    if (linkageName == funcName) {
                        declaration = element
                        break
                    }
                }
            }
        }
        return (scope, declaration)
    }

    public func CreateAnonymousTypeForGenericType(typeTemplate: LLVMValueRef, ty: Type): Unit {
        if (!cgMod.GetCGContext().GetCompileOptions().enableCompileDebug) {
            return
        }
        let isInterface = ty.IsClass() && StaticCast<ClassType>(ty).GetClassDef().IsInterface()
        if (!ty.IsEnum() && !isInterface) {
            return
        }
        genericID++
        let diType = GetOrCreateType(ty)
        let genericName = "$" + genericID.toString()
        var globalVar = LLVMNullMetadata()
        try (
            nameCString = unsafe { LibC.mallocCString(genericName) }.asResource(),
            linkageCString = unsafe { LibC.mallocCString(genericName) }.asResource()
        ) {
            globalVar = unsafe {
                LLVMDIBuilderCreateGlobalVariableExpression(raw, namespaceScope, nameCString.value,
                    UIntNative(genericName.size), linkageCString.value, UIntNative(genericName.size), defaultFile, 0u32,
                    diType, 0, LLVMNullMetadata(), LLVMNullMetadata(), 0u32)
            }
        }
        LLVMSetGlobalMetadata(cgMod.GetLLVMContext(), typeTemplate, "dbg", globalVar)
    }

    public func FinalizeSubProgram(function: LLVMValueRef): Unit {
        let subprogram = unsafe { LLVMGetSubprogram(function) }
        if (subprogram.isNull()) {
            return
        }
        lexicalBlocks.clear()
        curLocation = Position()
        curScope = LLVMNullMetadata()
        unsafe { LLVMDIBuilderFinalizeSubprogram(raw, subprogram) }
        if (!needSubprogram) {
            unsafe { LLVMSetSubprogram(function, LLVMNullMetadata()) }
        }
        needSubprogram = false
    }

    public func CreateDILoc(chirNode: CHIRExprWrapper, removable!: Bool = false): LLVMMetadataRef {
        CJC_ASSERT(enabled || enableLineInfo)
        let currentBB = chirNode.GetExpression().GetParentBlock() ?? return LLVMNullMetadata()
        let rawBB = cgMod.GetMappedBB(currentBB) ?? return LLVMNullMetadata()
        let function = unsafe { LLVMGetBasicBlockParent(rawBB) }
        let subprogram = unsafe { LLVMGetSubprogram(function) }
        if (subprogram.isNull()) {
            return LLVMNullMetadata()
        }
        let position = chirNode.GetExpression().GetDebugLocation()
        if (removable && position.IsInvalidPos()) {
            return LLVMNullMetadata()
        }
        needSubprogram = true
        let scope = GetOrCreateScope(position, subprogram)
        if (let Some(parentFunc) <- chirNode.GetTopLevelFunc()) {
            if (parentFunc.GetFuncKind() == FuncKind.DEFAULT_PARAMETER_FUNC) {
                return HandleDefaultParamLocation(chirNode, scope)
            }
        }
        let begin = position.GetBeginPos()
        return unsafe {
            LLVMSelfhostDILocationGet(cgMod.GetLLVMContext().raw, begin.line, begin.column, scope,
                LLVMNullMetadata(), !begin.IsLegal())
        }
    }

    public func CreateDILoc(line: UInt32, column: UInt32): LLVMMetadataRef {
        let scope = if (!namespaceScope.isNull()) {
            namespaceScope
        } else {
            compileUnit
        }
        if (scope.isNull()) {
            return LLVMNullMetadata()
        }
        return unsafe {
            LLVMDIBuilderCreateDebugLocation(cgMod.GetLLVMContext().raw, line, column, scope, LLVMNullMetadata())
        }
    }

    private func HandleDefaultParamLocation(chirNode: CHIRExprWrapper, scope: LLVMMetadataRef): LLVMMetadataRef {
        let position = chirNode.GetExpression().GetDebugLocation()
        let exprKind = chirNode.GetExpression().GetExprKind()
        let isApply = exprKind == ExprKind.APPLY || exprKind == ExprKind.APPLY_WITH_EXCEPTION
        if (!position.GetBeginPos().IsZero() && isApply) {
            curLocation = Position(position.GetBeginPos().line, position.GetBeginPos().column)
        }
        return unsafe {
            LLVMSelfhostDILocationGet(cgMod.GetLLVMContext().raw, curLocation.line, curLocation.column, scope,
                LLVMNullMetadata(), false)
        }
    }

    private func GetOrCreateScope(position: DebugLocation, subprogram: LLVMMetadataRef): LLVMMetadataRef {
        let scopeInfo = position.GetScopeInfo()
        if (scopeInfo.size > 1) {
            curScope = GetOrCreateLexicalScope(position, subprogram, scopeInfo)
            return curScope
        }
        if (scopeInfo.size == 1) {
            curScope = subprogram
        }
        return if (scopeInfo.isEmpty() && !curScope.isNull()) { curScope } else { subprogram }
    }

    private func GetOrCreateLexicalScope(position: DebugLocation, subprogram: LLVMMetadataRef,
        scopeInfo: ArrayList<Int64>): LLVMMetadataRef {
        let key = ScopeInfoKey(scopeInfo)
        if (let Some(scope) <- lexicalBlocks.get(key)) {
            return scope
        }
        let parentInfo = ArrayList<Int64>()
        var idx: Int64 = 0
        while (idx < scopeInfo.size - 1) {
            parentInfo.add(scopeInfo[idx])
            idx++
        }
        let parentScope = if (parentInfo.size == 1) {
            subprogram
        } else {
            GetOrCreateLexicalScope(position, subprogram, parentInfo)
        }
        let file = unsafe { LLVMDIScopeGetFile(subprogram) }
        let begin = position.GetBeginPos()
        let lexicalBlock = unsafe {
            LLVMDIBuilderCreateLexicalBlock(raw, parentScope, file, begin.line, begin.column)
        }
        lexicalBlocks[ScopeInfoKey(position.GetScopeInfo())] = lexicalBlock
        return lexicalBlock
    }

    public func Finalize(): Unit {
        if (finalized || raw.isNull()) {
            return
        }
        if (enabled || enableLineInfo) {
            unsafe { LLVMDIBuilderFinalize(raw) }
        }
        unsafe { LLVMDisposeDIBuilder(raw) }
        finalized = true
    }

    public func GetDefaultFile(): LLVMMetadataRef { return defaultFile }
    public func GetCompileUnit(): LLVMMetadataRef { return compileUnit }
    public func GetNameSpace(): LLVMMetadataRef { return namespaceScope }

    private func CreateFunction(scope: LLVMMetadataRef, name: String, linkageName: String, file: LLVMMetadataRef,
        lineNo: UInt32, ty: LLVMMetadataRef, scopeLine: UInt32, flags: UInt32, spFlags: UInt32,
        templateParams: LLVMMetadataRef, declaration: LLVMMetadataRef): LLVMMetadataRef {
        var result = LLVMNullMetadata()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource(),
            linkageNameCString = unsafe { LibC.mallocCString(linkageName) }.asResource()) {
            result = unsafe {
                LLVMSelfhostDIBuilderCreateFunction(raw, scope, nameCString.value, UIntNative(name.size),
                    linkageNameCString.value, UIntNative(linkageName.size), file, lineNo, ty, scopeLine, flags,
                    spFlags, templateParams, declaration)
            }
        }
        return result
    }

    private func CreateDefaultFunctionType(): LLVMMetadataRef {
        return CreateSubroutineType(ArrayList<LLVMMetadataRef>())
    }

    private func CreateFuncType(funcType: FuncType, isImported!: Bool = false, hasThis!: Bool = false): LLVMMetadataRef {
        let eltTys = ArrayList<LLVMMetadataRef>()
        let returnType = GetOrCreateType(funcType.GetReturnType())
        let paramsTypes = funcType.GetParamTypes()
        eltTys.add(returnType)
        var skipFirstParm = false
        if (isImported) {
            eltTys.add(CreateRefType())
            skipFirstParm = true
        }
        var index: Int64 = 0
        while (index < paramsTypes.size) {
            if (skipFirstParm) {
                skipFirstParm = false
                index++
                continue
            }
            var cgType = GetOrCreateType(paramsTypes[index])
            if (hasThis && index == 0) {
                var flag = FlagObjectPointer
                flag |= FlagArtificial
                cgType = CreateMemberPointerType(cgType, cgType, 64u64, 0u32, flag)
            }
            eltTys.add(cgType)
            index++
        }
        return CreateSubroutineType(eltTys)
    }

    private func CreateSubroutineType(parameterTypes: ArrayList<LLVMMetadataRef>): LLVMMetadataRef {
        if (parameterTypes.isEmpty()) {
            return unsafe {
                LLVMSelfhostDIBuilderCreateSubroutineType(raw, CPointer<LLVMMetadataRef>(), 0, FlagZero)
            }
        }
        var result = LLVMNullMetadata()
        try (typePtr = LibC.malloc<LLVMMetadataRef>(count: parameterTypes.size).asResource()) {
            var idx: Int64 = 0
            while (idx < parameterTypes.size) {
                unsafe { (typePtr.value + idx).write(parameterTypes[idx]) }
                idx++
            }
            result = unsafe {
                LLVMSelfhostDIBuilderCreateSubroutineType(raw, typePtr.value, UIntNative(parameterTypes.size), FlagZero)
            }
        }
        return result
    }

    private func GetOrCreateFile(position: DebugLocation): LLVMMetadataRef {
        var dirPath = position.GetAbsPath()
        var fileName = ""
        var index = dirPath.size - 1
        while (index >= 0) {
            if (dirPath[index] == b'/' || dirPath[index] == b'\\') {
                fileName = dirPath[index + 1..]
                dirPath = dirPath[0..index]
                break
            }
            index--
        }
        if (!cgMod.GetCGContext().GetCompileOptions().removedPathPrefix.isEmpty()) {
            dirPath = RemovePathPrefix(dirPath, cgMod.GetCGContext().GetCompileOptions().removedPathPrefix)
        }
        return CreateFile(fileName, dirPath)
    }

    private func GetOrCreateType(ty: Type, isReadOnly!: Bool = false): LLVMMetadataRef {
        let baseTy = DeRef(ty)
        if (let Some(cached) <- typeCache.get(baseTy.objectId)) {
            return if (isReadOnly) {
                unsafe { LLVMDIBuilderCreateQualifiedType(raw, DW_TAG_const_type, cached) }
            } else {
                cached
            }
        }
        let diType = CreateDIType(baseTy)
        CJC_ASSERT(!diType.isNull())
        typeCache[baseTy.objectId] = diType
        return if (isReadOnly) {
            unsafe { LLVMDIBuilderCreateQualifiedType(raw, DW_TAG_const_type, diType) }
        } else {
            diType
        }
    }

    private func CreateDIType(ty: Type): LLVMMetadataRef {
        if (!enabled) {
            return LLVMNullMetadata()
        }
        var encoding = DW_ATE_unsigned
        let boxTy = ty as BoxType
        let baseTy = if (let Some(box) <- boxTy) { box.GetBaseType() } else { ty }
        match (baseTy.GetTypeKind()) {
            case TypeKind.TYPE_UNIT | TypeKind.TYPE_NOTHING | TypeKind.TYPE_VOID => return CreateUnitType()
            case TypeKind.TYPE_RUNE => encoding = DW_ATE_UTF
            case TypeKind.TYPE_UINT8 | TypeKind.TYPE_UINT16 | TypeKind.TYPE_UINT32 |
                TypeKind.TYPE_UINT64 | TypeKind.TYPE_UINT_NATIVE => encoding = DW_ATE_unsigned
            case TypeKind.TYPE_INT8 | TypeKind.TYPE_INT16 | TypeKind.TYPE_INT32 |
                TypeKind.TYPE_INT64 | TypeKind.TYPE_INT_NATIVE => encoding = DW_ATE_signed
            case TypeKind.TYPE_FLOAT16 | TypeKind.TYPE_FLOAT32 | TypeKind.TYPE_FLOAT64 => encoding = DW_ATE_float
            case TypeKind.TYPE_BOOLEAN => encoding = DW_ATE_boolean
            case TypeKind.TYPE_STRUCT =>
                return CreateStructType((baseTy as StructType).getOrThrow(), boxTy: boxTy)
            case TypeKind.TYPE_ENUM =>
                return CreateEnumType((baseTy as EnumType).getOrThrow(), boxTy: boxTy)
            case _ =>
                throw IllegalStateException("DIBuilder CreateDIType slice 2 is not ported for " + baseTy.ToString())
        }
        let tyName = baseTy.ToString()
        let size = GetBasicTypeSize(baseTy)
        let diType = createBasicType(tyName, size, encoding)
        let typeDefType = createTypedef(diType, tyName, defaultFile, 0u32, compileUnit)
        if (boxTy.isSome()) {
            var fwdDecl = createStructType(namespaceScope, tyName, defaultFile, 0u32, size + 64u64, 0u32,
                FlagZero, LLVMNullMetadata(), ArrayList<LLVMMetadataRef>(), 0u32, LLVMNullMetadata(), ty.ToString())
            let memberType = createMemberType(fwdDecl, "base", defaultFile, 0u32, size, 0u32, 64u64,
                FlagZero, typeDefType)
            fwdDecl = replaceArrays(fwdDecl, getOrCreateArray(ArrayList<LLVMMetadataRef>([memberType])))
            return fwdDecl
        }
        return typeDefType
    }

    private func GetBasicTypeSize(ty: Type): UInt64 {
        match (ty.GetTypeKind()) {
            case TypeKind.TYPE_INT8 | TypeKind.TYPE_UINT8 => return 8u64
            case TypeKind.TYPE_INT16 | TypeKind.TYPE_UINT16 | TypeKind.TYPE_FLOAT16 => return 16u64
            case TypeKind.TYPE_RUNE | TypeKind.TYPE_INT32 | TypeKind.TYPE_UINT32 | TypeKind.TYPE_FLOAT32 => return 32u64
            case TypeKind.TYPE_INT64 | TypeKind.TYPE_UINT64 | TypeKind.TYPE_FLOAT64 => return 64u64
            case TypeKind.TYPE_INT_NATIVE | TypeKind.TYPE_UINT_NATIVE =>
                return (ty as NumericType).getOrThrow().GetBitness()
            case TypeKind.TYPE_BOOLEAN => return 8u64
            case _ => return 0u64
        }
    }

    private func GetTypeSize(llvmType: LLVMTypeRef): UInt64 {
        CJC_ASSERT(unsafe { LLVMTypeIsSized(llvmType) } != 0)
        return cgMod.GetTypeSizeInBits(llvmType)
    }

    private func GetSizeInBits(diType: LLVMMetadataRef): UInt64 {
        var resolvedType = diType
        if (unsafe { LLVMSelfhostDINodeGetTag(resolvedType) } == DW_TAG_typedef) {
            resolvedType = unsafe { LLVMSelfhostDIDerivedTypeGetBaseType(resolvedType) }
        }
        return unsafe { LLVMDITypeGetSizeInBits(resolvedType) }
    }

    private func CreateUnitType(): LLVMMetadataRef {
        let llvmType = CGType.GetUnitCGType(cgMod).GetLLVMType()
        let align = cgMod.GetABITypeAlignment(llvmType)
        return createStructType(compileUnit, "Unit", defaultFile, 0u32, 8u64, align, FlagZero,
            LLVMNullMetadata(), ArrayList<LLVMMetadataRef>(), 0u32, LLVMNullMetadata(), UNIT_TYPE_STR)
    }

    private func CreateVArrayType(vArrTy: VArrayType): LLVMMetadataRef {
        let size = vArrTy.GetSize()
        let elementType = GetOrCreateType(vArrTy.GetElementType())
        let name = GenerateTypeName(vArrTy)
        let llvmType = CGType.GetOrCreate(cgMod, vArrTy).GetLLVMType()
        let typeSize = GetTypeSize(llvmType)
        // Align in 64-bit.
        let range = getOrCreateSubrange(0, Int64(size))
        let diType = createArrayType(typeSize, 0u32, elementType,
            getOrCreateArray(ArrayList<LLVMMetadataRef>([range])))
        return createTypedef(diType, name, defaultFile, 0u32, compileUnit)
    }

    private func CreateGenericType(genericTy: GenericType): LLVMMetadataRef {
        let name = GenerateTypeName(genericTy)
        let genericSize = 64u64
        var genericType = createStructType(compileUnit, name, defaultFile, 0u32, genericSize, 0u32,
            FlagZero, LLVMNullMetadata(), ArrayList<LLVMMetadataRef>(), 0u32, LLVMNullMetadata(),
            genericTy.GetIdentifier())
        let ti = CreateTypeInfoMember(genericType, defaultFile)
        let elements = ArrayList<LLVMMetadataRef>([ti])
        for (upperBound in genericTy.GetUpperBounds()) {
            let upperBoundType = GetOrCreateType(upperBound)
            elements.add(createInheritance(genericType, upperBoundType, 0u64, 0u32, FlagZero))
        }
        genericType = replaceArrays(genericType, getOrCreateArray(elements))
        return genericType
    }

    private func CreateCStringType(cStringType: CStringType): LLVMMetadataRef {
        let name = GenerateTypeName(cStringType)
        let uniqueName = cStringType.ToString()
        let diFile = defaultFile
        let refSizeInBits = GetSizeInBits(CreateRefType())
        // Generates the CString struct.
        var fwdDecl = createStructType(compileUnit, name, diFile, 0u32, refSizeInBits, 0u32, FlagZero,
            LLVMNullMetadata(), ArrayList<LLVMMetadataRef>(), 0u32, LLVMNullMetadata(), uniqueName)
        // Generates a member 'chars' of the 'Int8 *' type in CString struct.
        let elemSizeInBits = GetTypeSize(unsafe { LLVMInt8TypeInContext(cgMod.GetLLVMContext().raw) })
        let basicType = createBasicType("char", elemSizeInBits, DW_ATE_unsigned_char)
        let elemType = CreatePointerType(basicType, sizeInBits: elemSizeInBits)
        let eleType = createMemberType(fwdDecl, "chars", diFile, 0u32, elemSizeInBits, 8u32, 0u64,
            FlagZero, elemType) // 8 is default align size.
        fwdDecl = replaceArrays(fwdDecl, getOrCreateArray(ArrayList<LLVMMetadataRef>([eleType])))
        return fwdDecl
    }

    private func CreateCPointerType(ptrTy: CPointerType): LLVMMetadataRef {
        let name = GenerateTypeName(ptrTy)
        let diFile = defaultFile
        let uniqueName = ptrTy.ToString()
        let sizeInBits = GetSizeInBits(CreateRefType())
        var basicType = createBasicType("Int8", sizeInBits, DW_ATE_unsigned)
        if (!ptrTy.GetTypeArgs().isEmpty() && !ptrTy.GetTypeArgs()[0].IsCPointer()) {
            basicType = GetOrCreateType(ptrTy.GetTypeArgs()[0])
        }
        var fwdDecl = createStructType(compileUnit, name, diFile, 0u32, sizeInBits, 0u32, FlagZero,
            LLVMNullMetadata(), ArrayList<LLVMMetadataRef>(), 0u32, LLVMNullMetadata(), uniqueName)
        let elemType = CreatePointerType(basicType, sizeInBits: sizeInBits)
        let eleType = createMemberType(fwdDecl, "ptr", diFile, 0u32, sizeInBits, 8u32, 0u64,
            FlagZero, elemType) // 8 is default align size.
        fwdDecl = replaceArrays(fwdDecl, getOrCreateArray(ArrayList<LLVMMetadataRef>([eleType])))
        return fwdDecl
    }

    private func CreateArrayType(arrTy: RawArrayType): LLVMMetadataRef {
        let identifier = arrTy.ToString()
        let dims = arrTy.GetDims()
        CJC_ASSERT(dims != 0u64)
        let arrayTypeName = GenerateTypeName(arrTy)
        let diFile = defaultFile
        let scope = compileUnit
        let elements = ArrayList<LLVMMetadataRef>() // Array.Type has 3 elements.
        let elemTy = arrTy.GetElementType()
        let elemType = GetOrCreateType(elemTy)
        let arrayLayout = (CGType.GetOrCreate(cgMod, arrTy) as CGArrayType).getOrThrow().GetLayoutType()
        // when arrayLayout is nullptr, means this rawArray is not sized.
        let arrayLayoutSize = if (arrayLayout.isNull()) { 64u64 } else { GetTypeSize(arrayLayout) }
        // %ArrayBase is not include object now, so we should add 64bit for the object.
        let totalSize = 64u64 + arrayLayoutSize + GetSizeInBits(elemType)
        // Array type is a temporary type which do no have fixed definition file nor line.
        // type struct: {klass*, i32 arrayLength, [0 x T]}, where 'klass*' is invisible for user.
        var fwdDecl = createStructType(scope, arrayTypeName, diFile, 0u32, totalSize, 0u32, FlagZero,
            LLVMNullMetadata(), ArrayList<LLVMMetadataRef>(), 0u32, LLVMNullMetadata(), identifier)
        if (arrayLayout.isNull()) {
            elements.add(CreateTypeInfoMember(fwdDecl, diFile))
            fwdDecl = replaceArrays(fwdDecl, getOrCreateArray(elements))
            return fwdDecl
        }
        CreateArrayMemberType(arrTy, fwdDecl, elements, arrayLayout)
        return fwdDecl
    }

    // Array.Type has 3 elements.
    private func CreateArrayMemberType(arrTy: RawArrayType, fwdDecl: LLVMMetadataRef,
        elements: ArrayList<LLVMMetadataRef>, arrayLayout: LLVMTypeRef): Unit {
        let pointerSize = GetSizeInBits(CreateRefType())
        let sizeType = createBasicType("Int64", 64u64, DW_ATE_unsigned) // int64 type : size.
        CJC_ASSERT(!sizeType.isNull())
        elements.add(createMemberType(fwdDecl, "$ti", defaultFile, 0u32, pointerSize, 0u32, 0u64,
            FlagArtificial, CreateRefType()))
        elements.add(createMemberType(fwdDecl, "size", defaultFile, 0u32, GetSizeInBits(sizeType), 0u32,
            pointerSize, FlagZero, sizeType))
        // Offset for element is size of ArrayBase for chir2llvm.
        let elemTy = arrTy.GetElementType()
        var elemType = GetOrCreateType(elemTy)
        // Multi-dimension array or class/enum is pointer element.
        if (arrTy.GetDims() > 1u64 || IsReferenceType(elemTy, cgMod)) {
            elemType = CreatePointerType(elemType, sizeInBits: GetSizeInBits(CreateRefType()))
        }
        let bitInSize = GetSizeInBits(elemType)
        // layout is %ArrayBase, which is behind an object.
        let offset = cgMod.GetOffsetOfElement(arrayLayout, 1u32) * 8u64 + 64u64
        let align = cgMod.GetABITypeAlignment(arrayLayout)
        elements.add(createMemberType(fwdDecl, "elements", defaultFile, 0u32, bitInSize, align, offset,
            FlagZero, elemType))
        let _ = replaceArrays(fwdDecl, getOrCreateArray(elements))
    }

    private func CreateVarFuncType(funcTy: FuncType): LLVMMetadataRef {
        let size = GetSizeInBits(CreateRefType())
        let name = GenerateFuncName(funcTy)
        let tag = DW_TAG_class_type
        var fwdDecl = createReplaceableCompositeType(tag, name, namespaceScope, defaultFile, 0u32, 0u32, 64u64,
            0u32, FlagTypePassByReference, funcTy.ToString())
        fwdDecl = replaceWithDistinct(fwdDecl)
        let funcDIType = CreateFuncType(funcTy)
        let funcPtrType = createMemberType(fwdDecl, "ptr", defaultFile, 0u32, GetSizeInBits(CreateRefType()), 0u32,
            0u64, FlagZero, CreatePointerType(funcDIType, sizeInBits: size))
        let _ = replaceArrays(fwdDecl, getOrCreateArray(ArrayList<LLVMMetadataRef>([funcPtrType])))
        return fwdDecl
    }

    private func CreateTupleType(tupleTy: TupleType, boxTy: Option<BoxType>): LLVMMetadataRef {
        let tupleTypeName = GenerateTypeName(tupleTy)
        let scope = compileUnit
        let diFile = defaultFile
        let llvmType = CGType.GetOrCreate(cgMod, tupleTy).GetLLVMType()
        let identifier = tupleTy.ToString()
        let elements = ArrayList<LLVMMetadataRef>() // SmallVector Size: 16.
        if (CGType.GetOrCreate(cgMod, tupleTy).GetSize().isNone()) {
            var fwdDecl = createStructType(scope, tupleTypeName, diFile, 0u32, 64u64, 0u32, FlagZero,
                LLVMNullMetadata(), ArrayList<LLVMMetadataRef>(), 0u32, LLVMNullMetadata(), identifier)
            let memberType = CreateTypeInfoMember(fwdDecl, diFile)
            elements.add(memberType)
            fwdDecl = replaceArrays(fwdDecl, getOrCreateArray(elements))
            return fwdDecl
        }
        // Tuple type is a temporary type which do no have fixed definition file & line.
        let boxOffset = if (boxTy.isSome()) { 64u64 } else { 0u64 }
        let totalSize = GetTypeSize(llvmType) + boxOffset
        var fwdDecl = createStructType(scope, tupleTypeName, diFile, 0u32, totalSize, 0u32, FlagZero,
            LLVMNullMetadata(), elements, 0u32, LLVMNullMetadata(),
            "$" + boxOffset.toString() + "_" + identifier)
        if (let Some(box) <- boxTy) {
            typeCache[box.objectId] = fwdDecl
        }
        let align = cgMod.GetABITypeAlignment(llvmType)
        var idx: Int64 = 0
        for (ty in tupleTy.GetElementTypes()) {
            var elemType = GetOrCreateType(ty)
            let bitInSize = GetTypeSize(unsafe { LLVMStructGetTypeAtIndex(llvmType, UInt32(idx)) })
            let offset = cgMod.GetOffsetOfElement(llvmType, UInt32(idx)) * 8u64 + boxOffset
            if (IsReferenceType(ty, cgMod)) {
                elemType = CreatePointerType(elemType, sizeInBits: GetSizeInBits(CreateRefType()))
            }
            let memberType = createMemberType(fwdDecl, "_" + idx.toString(), diFile, 0u32, bitInSize, align,
                offset, FlagZero, elemType)
            elements.add(memberType)
            idx++
        }
        fwdDecl = replaceArrays(fwdDecl, getOrCreateArray(elements))
        return fwdDecl
    }

    private func GenerateTypeName(ty: Type): String {
        if (ty.IsPrimitive()) {
            return ty.ToString()
        }
        match (ty.GetTypeKind()) {
            case TypeKind.TYPE_RAWARRAY => return GenerateRawArrayName((ty as RawArrayType).getOrThrow())
            case TypeKind.TYPE_TUPLE => return GenerateTupleName((ty as TupleType).getOrThrow())
            case TypeKind.TYPE_FUNC => return GenerateFuncName((ty as FuncType).getOrThrow())
            case TypeKind.TYPE_VARRAY => return GenerateVArrayName((ty as VArrayType).getOrThrow())
            case TypeKind.TYPE_CPOINTER => return GenerateCPointerName((ty as CPointerType).getOrThrow())
            case TypeKind.TYPE_CSTRING => return ty.ToString()
            case TypeKind.TYPE_CLASS | TypeKind.TYPE_STRUCT | TypeKind.TYPE_ENUM =>
                return GenerateCustomTypeName((ty as CustomType).getOrThrow())
            case TypeKind.TYPE_GENERIC => return GenerateGenericTypeName((ty as GenericType).getOrThrow())
            case TypeKind.TYPE_REFTYPE => return GenerateTypeName((ty as RefType).getOrThrow().GetBaseType())
            case TypeKind.TYPE_VOID | TypeKind.TYPE_NOTHING | TypeKind.TYPE_UNIT => return "()"
            case _ => throw IllegalStateException("DIBuilder.GenerateTypeName unsupported type " + ty.ToString())
        }
    }

    private func GenerateRawArrayName(ty: RawArrayType): String {
        var typeName = ""
        var suffix = ""
        var idx: UInt64 = 0u64
        while (idx < ty.GetDims()) {
            typeName += "RawArray<"
            suffix += ">"
            idx++
        }
        return typeName + GenerateTypeName(ty.GetElementType()) + suffix
    }

    private func GenerateTupleName(ty: TupleType): String {
        var typeName = "Tuple<"
        for (arg in ty.GetTypeArgs()) {
            typeName += GenerateTypeName(arg) + ","
        }
        typeName = typeName[0..typeName.size - 1]
        return typeName + ">"
    }

    private func GenerateFuncName(ty: FuncType): String {
        var typeName = "("
        if (!ty.GetParamTypes().isEmpty()) {
            for (param in ty.GetParamTypes()) {
                typeName += GenerateTypeName(param) + ","
            }
            typeName = typeName[0..typeName.size - 1]
        }
        return typeName + ")->" + GenerateTypeName(ty.GetReturnType())
    }

    private func GenerateVArrayName(ty: VArrayType): String {
        return "VArray<" + GenerateTypeName(ty.GetElementType()) + ",$" + ty.GetSize().toString() + ">"
    }

    private func GenerateCPointerName(ty: CPointerType): String {
        var typeName = "CPointer<"
        for (arg in ty.GetTypeArgs()) {
            typeName += GenerateTypeName(arg) + ","
        }
        typeName = typeName[0..typeName.size - 1]
        return typeName + ">"
    }

    private func GenerateCustomTypeName(ty: CustomType, needPkgPrefix!: Bool = true): String {
        if (ty.IsAutoEnvBase()) {
            return GenerateClosureTypeName((ty as ClassType).getOrThrow())
        }
        let pkgName = ty.GetCustomTypeDef().GetPackageName()
        var typeName = if (needPkgPrefix) { pkgName + "::" } else { "" }
        typeName += GetCustomTypeIdentifier(ty)
        if (!ty.GetTypeArgs().isEmpty()) {
            typeName += "<"
            for (arg in ty.GetTypeArgs()) {
                typeName += GenerateTypeName(arg) + ","
            }
            typeName = typeName[0..typeName.size - 1]
            typeName += ">"
        }
        return typeName
    }

    private func GenerateClosureTypeName(ty: ClassType): String {
        var typeName = "("
        let (paramTypes, retType) = GetFuncTypeWithoutThisPtrFromAutoEnvBaseType(ty)
        if (!paramTypes.isEmpty()) {
            for (paramTy in paramTypes) {
                typeName += GenerateTypeName(paramTy) + ","
            }
            typeName = typeName[0..typeName.size - 1]
        }
        typeName += ")->"
        typeName += GenerateTypeName(retType)
        return typeName
    }

    private func GenerateGenericTypeName(ty: GenericType): String {
        return GENERIC_PREFIX + ty.GetSrcCodeIdentifier()
    }

    private func CreateStructType(structTy: StructType, boxTy!: Option<BoxType> = None): LLVMMetadataRef {
        let structDef = structTy.GetStructDef()
        let identifier = structTy.ToString()
        let cgStructType = CGType.GetOrCreate(cgMod, structTy)
        let position = structDef.GetDebugLocation()
        let diFile = GetOrCreateFile(position)
        let defPackage = createNameSpace(compileUnit, structDef.GetPackageName(), false)
        let name = GenerateCustomTypeName(structTy, needPkgPrefix: false)
        if (cgStructType.GetSize().isNone()) {
            let size = 64u64 + UInt64(structDef.GetAllInstanceVars().size) * 64u64
            var fwdDecl = createStructType(defPackage, name, diFile, position.GetBeginPos().line, size, 0u32,
                FlagZero, LLVMNullMetadata(), ArrayList<LLVMMetadataRef>(), 0u32, LLVMNullMetadata(), identifier)
            typeCache[structTy.objectId] = fwdDecl
            let elements = ArrayList<LLVMMetadataRef>()
            CreateInheritedInterface(elements, fwdDecl, structTy)
            CreateCustomTypeMember(structDef.GetAllInstanceVars(), elements, fwdDecl, diFile)
            CreateMethodType(structDef, elements, fwdDecl)
            CreateGetGenericFunc(structTy, fwdDecl, elements)
            fwdDecl = replaceArrays(fwdDecl, getOrCreateArray(elements))
            typeCache[structTy.objectId] = fwdDecl
            return fwdDecl
        }
        let cgType = cgStructType.GetLLVMType()
        let boxOffset = if (boxTy.isSome()) { 64u64 } else { 0u64 }
        var fwdDecl = createStructType(defPackage, name, diFile, position.GetBeginPos().line,
            GetTypeSize(cgType) + boxOffset, 0u32, FlagZero, LLVMNullMetadata(), ArrayList<LLVMMetadataRef>(),
            0u32, LLVMNullMetadata(), "$" + boxOffset.toString() + "_" + identifier)
        if (let Some(box) <- boxTy) {
            typeCache[box.objectId] = fwdDecl
        } else {
            typeCache[structTy.objectId] = fwdDecl
        }
        let elements = ArrayList<LLVMMetadataRef>()
        CreateInheritedInterface(elements, fwdDecl, structTy)
        CreateStructMemberType(structTy, cgType, elements, fwdDecl, boxTy: boxTy)
        CreateMethodType(structDef, elements, fwdDecl)
        fwdDecl = replaceArrays(fwdDecl, getOrCreateArray(elements))
        if (let Some(box) <- boxTy) {
            typeCache[box.objectId] = fwdDecl
        } else {
            typeCache[structTy.objectId] = fwdDecl
        }
        return fwdDecl
    }

    private func CreateStructMemberType(structTy: StructType, cgType: LLVMTypeRef,
        elements: ArrayList<LLVMMetadataRef>, fwdDecl: LLVMMetadataRef,
        boxTy!: Option<BoxType> = None): Unit {
        let structDef = structTy.GetStructDef()
        let diFile = GetOrCreateFile(structDef.GetDebugLocation())
        let memberTys = structTy.GetInstantiatedMemberTys(cgMod.GetCGContext().GetCHIRBuilder())
        CJC_ASSERT(memberTys.size == structDef.GetAllInstanceVars().size)
        let boxOffset = if (boxTy.isSome()) { 64u64 } else { 0u64 }
        let align = cgMod.GetABITypeAlignment(cgType)
        var idx: Int64 = 0
        for (member in structDef.GetAllInstanceVars()) {
            let elementTy = memberTys[idx]
            let elemTy = DeRef(elementTy)
            var elemType = GetOrCreateType(elemTy, isReadOnly: member.TestAttr(Attribute.READONLY))
            if (IsReferenceType(elemTy, cgMod) && !IsOption(elementTy)) {
                elemType = CreatePointerType(elemType)
            }
            let cgElemType = unsafe { LLVMStructGetTypeAtIndex(cgType, UInt32(idx)) }
            let bitInSize = GetTypeSize(cgElemType)
            let offset = cgMod.GetOffsetOfElement(cgType, UInt32(idx)) * 8u64 + boxOffset
            elements.add(createMemberType(fwdDecl, member.name, diFile, 1u32, bitInSize, align, offset,
                FlagZero, elemType))
            idx++
        }
    }

    private func CreateInheritedInterface(elements: ArrayList<LLVMMetadataRef>, fwdDecl: LLVMMetadataRef,
        customTy: CustomType): Unit {
        let builder = cgMod.GetCGContext().GetCHIRBuilder()
        for (interfaceTy in customTy.GetImplementedInterfaceTysWithoutExtend(builder)) {
            elements.add(createInheritance(fwdDecl, GetOrCreateType(interfaceTy), 0u64, 0u32, FlagZero))
        }
        for (extendDef in customTy.GetCustomTypeDef().GetExtends()) {
            for (interfaceTy in extendDef.GetImplementedInterfaceTys()) {
                elements.add(createInheritance(fwdDecl, GetOrCreateType(interfaceTy), 0u64, 0u32, FlagZero))
            }
        }
    }

    private func CreateMethodType(customDef: CustomTypeDef, elements: ArrayList<LLVMMetadataRef>,
        fwdDecl: LLVMMetadataRef): Unit {
        let options = cgMod.GetCGContext().GetCompileOptions()
        let isMockMode = options.mock == MockMode.ON || options.enableCompileTest
        if (customDef.TestAttr(Attribute.IMPORTED) && !isMockMode) {
            return
        }
        let allMethods = customDef.GetType().getOrThrow().GetDeclareAndExtendMethods(
            cgMod.GetCGContext().GetCHIRBuilder())
        if (allMethods.isEmpty()) {
            return
        }
        let diFile = GetOrCreateFile(customDef.GetDebugLocation())
        for (method in allMethods) {
            if (method.TestAttr(Attribute.NO_DEBUG_INFO)) {
                continue
            }
            let hasThis = !method.TestAttr(Attribute.STATIC)
            let name = if (IsParaInitFunc(method)) { "" } else {
                GenerateGenericFuncName(method.GetSrcCodeIdentifier(), method.GetOriginalGenericTypeParams())
            }
            let subprogramTy = CreateFuncType((method.GetType().getOrThrow() as FuncType).getOrThrow(), hasThis: hasThis)
            var flags = FlagPrototyped
            flags |= if (method.TestAttr(Attribute.PUBLIC)) { FlagPublic } else { FlagZero }
            flags |= if (method.TestAttr(Attribute.STATIC)) { FlagStaticMember } else { FlagZero }
            flags |= if (method.TestAttr(Attribute.PROTECTED)) { FlagProtected } else { FlagZero }
            let spFlags = if (method.TestAttr(Attribute.ABSTRACT)) { SPFlagPureVirtual } else { 0u32 }
            let position = method.GetDebugLocation()
            elements.add(createMethod(fwdDecl, name, method.GetIdentifierWithoutPrefix(), diFile,
                position.GetBeginPos().line, subprogramTy, 0u32, 0, LLVMNullMetadata(), flags, spFlags))
        }
    }

    private func CreateCustomTypeMember(members: ArrayList<MemberVarInfo>,
        elements: ArrayList<LLVMMetadataRef>, fwdDecl: LLVMMetadataRef, diFile: LLVMMetadataRef): Unit {
        var memberType = CreateTypeInfoMember(fwdDecl, diFile)
        elements.add(memberType)
        var offset = 0u64
        for (member in members) {
            let elemType = GetOrCreateType(member.ty)
            let bitInSize = GetSizeInBits(elemType)
            offset += bitInSize
            memberType = createMemberType(fwdDecl, member.name, diFile, member.loc.GetBeginPos().line,
                bitInSize, 0u32, offset, FlagZero, elemType)
            elements.add(memberType)
        }
    }

    private func CreateGetGenericFunc(customTy: CustomType, fwdDecl: LLVMMetadataRef,
        elements: ArrayList<LLVMMetadataRef>): Unit {
        if (!customTy.IsGenericRelated()) {
            return
        }
        let defType = GetOrCreateType(customTy.GetCustomTypeDef().GetType().getOrThrow())
        let subroutineType = CreateSubroutineType(ArrayList<LLVMMetadataRef>([defType]))
        let funcElement = createFunction(fwdDecl, "$GetGenericDef", "$GetGenericDef", defaultFile, 0u32,
            subroutineType, 0u32, FlagPrototyped, 0u32)
        elements.add(funcElement)
        unsafe { LLVMDIBuilderFinalizeSubprogram(raw, funcElement) }
    }

    private func CreateEnumType(enumTy: EnumType, boxTy!: Option<BoxType> = None): LLVMMetadataRef {
        let enumDef = enumTy.GetEnumDef()
        let enumMembers = ArrayList<LLVMMetadataRef>()
        let identifier = enumTy.ToString()
        let cgType = (CGType.GetOrCreate(cgMod, enumTy) as CGEnumType).getOrThrow()
        if (CGType.GetOrCreate(cgMod, enumTy).GetSize().isNone()) {
            let position = enumDef.GetDebugLocation()
            let diFile = GetOrCreateFile(position)
            let defPackage = createNameSpace(compileUnit, enumDef.GetPackageName(), false)
            CJC_ASSERT(cgType.IsOptionLike() || cgType.IsAllAssociatedValuesAreNonRef())
            var prefix = "E3$"
            if (cgType.IsOptionLike()) {
                prefix = if (enumTy.IsOption()) { "" } else { "E2$" }
            }
            let name = prefix + GenerateCustomTypeName(enumTy, needPkgPrefix: false)
            var size = 64u64 + UInt64(enumDef.GetAllInstanceVars().size) * 64u64
            if (cgType.IsOptionLike()) {
                size += 32u64
            }
            var fwdDecl = createStructType(defPackage, name, diFile, position.GetBeginPos().line, size, 0u32,
                FlagZero, LLVMNullMetadata(), ArrayList<LLVMMetadataRef>(), 0u32, LLVMNullMetadata(), identifier)
            typeCache[enumTy.objectId] = fwdDecl
            CreateInheritedInterface(enumMembers, fwdDecl, enumTy)
            if (cgType.IsOptionLike()) {
                let constructorType = GetOrCreateEnumCtorType(enumTy)
                let ctorSize = if (cgType.IsOptionLike()) { 8u64 } else { 32u64 }
                enumMembers.add(createMemberType(fwdDecl, "constructor", diFile, 0u32, ctorSize, 0u32,
                    64u64, FlagZero, constructorType))
            }
            CreateMethodType(enumDef, enumMembers, fwdDecl)
            CreateGetGenericFunc(enumTy, fwdDecl, enumMembers)
            fwdDecl = replaceArrays(fwdDecl, getOrCreateArray(enumMembers))
            typeCache[enumTy.objectId] = fwdDecl
            return fwdDecl
        }
        let isOption = enumTy.IsOption() && !enumTy.IsBoxed(cgMod.GetCGContext().GetCHIRBuilder())
        var fwdDecl = if (enumDef.IsAllCtorsTrivial()) {
            CreateTrivial(enumTy, enumMembers)
        } else if (isOption || cgType.IsOptionLike()) {
            CreateEnumOptionType(enumTy, enumMembers, boxTy: boxTy)
        } else if (cgType.IsAllAssociatedValuesAreNonRef()) {
            CreateEnumWithNonRefArgsType(enumTy, enumMembers)
        } else {
            CreateEnumWithArgsType(enumTy, enumMembers, boxTy: boxTy)
        }
        typeCache[enumTy.objectId] = fwdDecl
        CreateInheritedInterface(enumMembers, fwdDecl, enumTy)
        CreateMethodType(enumDef, enumMembers, fwdDecl)
        fwdDecl = replaceArrays(fwdDecl, getOrCreateArray(enumMembers))
        typeCache[enumTy.objectId] = fwdDecl
        return fwdDecl
    }

    private func GetOrCreateEnumCtorType(enumTy: EnumType): LLVMMetadataRef {
        if (let Some(cached) <- enumCtorCache.get(enumTy.objectId)) {
            return cached
        }
        let enumDef = enumTy.GetEnumDef()
        var name = GenerateCustomTypeName(enumTy, needPkgPrefix: false)
        let position = enumDef.GetDebugLocation()
        let diFile = GetOrCreateFile(position)
        let ctors = ArrayList<LLVMMetadataRef>()
        var fieldIdx: Int64 = 0
        let cgType = (CGType.GetOrCreate(cgMod, enumTy) as CGEnumType).getOrThrow()
        let isOption = enumTy.IsOption() && !enumTy.IsBoxed(cgMod.GetCGContext().GetCHIRBuilder())
        let isOptionLike = isOption || cgType.IsOptionLike()
        if (isOptionLike) {
            var index: Int64 = 0
            for (ctor in enumDef.GetCtors()) {
                let nonArgIndex: Int64 = if (cgType.IsAntiOptionLike()) { 0 } else { 1 }
                let ctorName = if (nonArgIndex == index && !enumTy.IsOption()) { "N$_" + ctor.name } else { ctor.name }
                ctors.add(createEnumerator(ctorName, fieldIdx))
                fieldIdx++
                index++
            }
            if (isOption) {
                name = "E2$" + name
            }
        } else {
            for (ctor in enumDef.GetCtors()) {
                ctors.add(createEnumerator(ctor.name, fieldIdx))
                fieldIdx++
            }
        }
        let size = if (isOptionLike) { 8u64 } else { 32u64 }
        let basicType = createBasicType("Int32", size, DW_ATE_signed)
        let enumCtorType = createEnumerationType(namespaceScope, name, diFile, position.GetBeginPos().line,
            size, 0u32, ctors, basicType, enumTy.ToString(), true)
        enumCtorCache[enumTy.objectId] = enumCtorType
        return enumCtorType
    }

    private func CreateTrivial(enumTy: EnumType, enumMembers: ArrayList<LLVMMetadataRef>): LLVMMetadataRef {
        let enumDef = enumTy.GetEnumDef()
        let defPackage = createNameSpace(compileUnit, enumDef.GetPackageName(), false)
        let position = enumDef.GetDebugLocation()
        let diFile = GetOrCreateFile(position)
        let typeName = GenerateCustomTypeName(enumTy, needPkgPrefix: false)
        let fwdDecl = createStructType(defPackage, "E0$" + typeName, diFile, position.GetBeginPos().line,
            32u64, 0u32, FlagZero, LLVMNullMetadata(), ArrayList<LLVMMetadataRef>(), 0u32,
            LLVMNullMetadata(), "$" + enumTy.ToString())
        let constructorType = GetOrCreateEnumCtorType(enumTy)
        enumMembers.add(createMemberType(fwdDecl, "constructor", diFile, 0u32, 32u64, 0u32, 0u64,
            FlagZero, constructorType))
        typeCache[enumTy.objectId] = fwdDecl
        return fwdDecl
    }

    private func CreateEnumWithNonRefArgsType(enumTy: EnumType,
        enumMembers: ArrayList<LLVMMetadataRef>): LLVMMetadataRef {
        let enumDef = enumTy.GetEnumDef()
        let defPackage = createNameSpace(compileUnit, enumDef.GetPackageName(), false)
        let position = enumDef.GetDebugLocation()
        let diFile = GetOrCreateFile(position)
        let typeName = GenerateCustomTypeName(enumTy, needPkgPrefix: false)
        let cgType = (CGType.GetOrCreate(cgMod, enumTy) as CGEnumType).getOrThrow()
        let fwdDecl = createStructType(defPackage, "E3$" + typeName, diFile, position.GetBeginPos().line,
            UInt64(cgType.GetsizeOfConstructorUnion()) + 32u64, 0u32, FlagZero, LLVMNullMetadata(),
            ArrayList<LLVMMetadataRef>(), 0u32, LLVMNullMetadata(), "$" + enumTy.ToString())
        typeCache[enumTy.objectId] = fwdDecl
        let constructorType = GetOrCreateEnumCtorType(enumTy)
        var fieldIdx: Int64 = 0
        for (ctor in enumTy.GetConstructorInfos(cgMod.GetCGContext().GetCHIRBuilder())) {
            let enumLayer = ArrayList<LLVMMetadataRef>()
            let size = 32u64
            let ctorName = GenerateCustomTypeName(enumTy, needPkgPrefix: false) + "_ctor_" + fieldIdx.toString()
            let paramTypes = ctor.funcType.getOrThrow().GetParamTypes()
            if (paramTypes.isEmpty()) {
                var subEnumType = createStructType(defPackage, ctorName, diFile, 0u32, size, 0u32, FlagZero,
                    LLVMNullMetadata(), ArrayList<LLVMMetadataRef>(), 0u32, LLVMNullMetadata(), "")
                enumLayer.add(createMemberType(subEnumType, "constructor", diFile, 0u32, size, 0u32,
                    0u64, FlagZero, constructorType))
                subEnumType = replaceArrays(subEnumType, getOrCreateArray(enumLayer))
                enumMembers.add(createInheritance(fwdDecl, subEnumType, 0u64, 0u32, FlagZero))
                fieldIdx++
                continue
            }
            let useAndroidArm32Layout = CGEnumType.NeedAndroidArm32AlignedEnumLayout(
                cgMod.GetCGContext().GetCompileOptions().target)
            var totalSize = 32u64
            let sizeOfCtors = ArrayList<UInt64>()
            sizeOfCtors.add(totalSize)
            for (_ in paramTypes) { sizeOfCtors.add(0u64) }
            let fields = ArrayList<Type>()
            var layout = AssociatedNonRefLayout()
            if (useAndroidArm32Layout) {
                fields.add(cgMod.GetCGContext().GetCHIRBuilder().context.GetInt32Ty())
                for (paramType in paramTypes) { fields.add(paramType) }
                layout = CGEnumType.ComputeAssociatedNonRefLayout(cgMod, fields)
                totalSize = UInt64(layout.size) * 8u64
            } else {
                var argIndex: Int64 = 0
                for (arg in paramTypes) {
                    var argTy = GetOrCreateType(arg)
                    if (IsReferenceType(arg, cgMod) || arg.IsRawArray()) {
                        argTy = CreatePointerType(argTy, sizeInBits: GetSizeInBits(CreateRefType()))
                    }
                    let argSize = GetSizeInBits(argTy)
                    sizeOfCtors[argIndex + 1] = argSize
                    totalSize += argSize
                    argIndex++
                }
            }
            var subEnumType = createStructType(defPackage, ctorName, diFile, 0u32, totalSize, 0u32,
                FlagZero, LLVMNullMetadata(), ArrayList<LLVMMetadataRef>(), 0u32, LLVMNullMetadata(), "")
            enumLayer.add(createMemberType(subEnumType, "constructor", diFile, 0u32, size, 0u32,
                0u64, FlagZero, constructorType))
            var offsetIndex: Int64 = 1
            var offset = 0u64
            var argIndex: Int64 = 0
            for (arg in paramTypes) {
                var argTy = GetOrCreateType(arg)
                if (IsReferenceType(arg, cgMod)) {
                    argTy = CreatePointerType(argTy, sizeInBits: GetSizeInBits(CreateRefType()))
                }
                let memberOffset = if (useAndroidArm32Layout) {
                    UInt64(layout.offsets[argIndex + 1]) * 8u64
                } else {
                    offset += sizeOfCtors[argIndex]
                    offset
                }
                enumLayer.add(createMemberType(subEnumType, "arg_" + offsetIndex.toString(), diFile, 0u32,
                    GetSizeInBits(argTy), 0u32, memberOffset, FlagZero, argTy))
                offsetIndex++
                argIndex++
            }
            subEnumType = replaceArrays(subEnumType, getOrCreateArray(enumLayer))
            enumMembers.add(createInheritance(fwdDecl, subEnumType, 0u64, 0u32, FlagZero))
            fieldIdx++
        }
        return fwdDecl
    }

    private func CreateEnumOptionType(enumTy: EnumType, enumMembers: ArrayList<LLVMMetadataRef>,
        boxTy!: Option<BoxType> = None): LLVMMetadataRef {
        let argTy = GetOptionLikeArgTy(enumTy, cgMod)
        let enumDef = enumTy.GetEnumDef()
        let position = enumDef.GetDebugLocation()
        let diFile = GetOrCreateFile(position)
        if (IsBoxSelf(argTy, cgMod)) {
            return CreateBoxSelfOptionType(enumTy, enumMembers)
        }
        let argTypeIsOption = IsOptionOrOptionLike(argTy)
        let isRefArg = IsReferenceType(argTy, cgMod) && !argTypeIsOption
        if (isRefArg) {
            var argType = GetOrCreateType(argTy)
            let size = if (enumTy.IsOption()) { GetSizeInBits(CreateRefType()) } else { GetSizeInBits(argType) }
            if (enumTy.IsOption()) {
                argType = CreatePointerType(argType, sizeInBits: size)
            }
            if (let Some(cached) <- typeCache.get(enumTy.objectId)) {
                for (element in getElements(cached)) {
                    enumMembers.add(element)
                }
                return cached
            }
            let boxOffset = if (boxTy.isSome()) { 64u64 } else { 0u64 }
            let defPackage = createNameSpace(compileUnit, enumDef.GetPackageName(), false)
            let name = if (enumTy.IsOption()) { GenerateCustomTypeName(enumTy, needPkgPrefix: false) } else {
                "E2$" + GenerateCustomTypeName(enumTy, needPkgPrefix: false)
            }
            let fwdDecl = createStructType(defPackage, name, diFile, position.GetBeginPos().line,
                size + boxOffset, unsafe { LLVMDITypeGetAlignInBits(argType) }, FlagZero, LLVMNullMetadata(),
                ArrayList<LLVMMetadataRef>(), 0u32, LLVMNullMetadata(),
                "$" + boxOffset.toString() + "_" + enumTy.ToString())
            if (let Some(box) <- boxTy) {
                typeCache[box.objectId] = fwdDecl
            }
            let offsetBits = if (argTy.IsRawArray()) { size } else { 0u64 }
            let valueType = createMemberType(fwdDecl, "val", diFile, 0u32, size, 0u32,
                offsetBits + boxOffset, FlagZero, argType)
            if (!enumTy.IsOption()) {
                enumMembers.add(createMemberType(fwdDecl, "constructor_R", diFile, 0u32, 8u64, 0u32,
                    64u64, FlagZero, GetOrCreateEnumCtorType(enumTy)))
            }
            enumMembers.add(valueType)
            return fwdDecl
        } else if (argTypeIsOption) {
            return CreateNestedOptionType(enumTy, enumMembers, boxTy: boxTy)
        } else {
            return CreateNonRefOptionType(enumTy, enumMembers, boxTy: boxTy)
        }
    }

    private func CreateBoxSelfOptionType(enumTy: EnumType,
        enumMembers: ArrayList<LLVMMetadataRef>): LLVMMetadataRef {
        let enumDef = enumTy.GetEnumDef()
        let position = enumDef.GetDebugLocation()
        let diFile = GetOrCreateFile(position)
        let defPackage = createNameSpace(compileUnit, enumDef.GetPackageName(), false)
        let name = "E2$" + GenerateCustomTypeName(enumTy, needPkgPrefix: false)
        let fwdDecl = createStructType(defPackage, name, diFile, position.GetBeginPos().line, 128u64, 0u32,
            FlagZero, LLVMNullMetadata(), ArrayList<LLVMMetadataRef>(), 0u32, LLVMNullMetadata(), enumTy.ToString())
        enumMembers.add(createMemberType(fwdDecl, "constructor_R", diFile, 0u32, 8u64, 0u32, 64u64,
            FlagZero, GetOrCreateEnumCtorType(enumTy)))
        enumMembers.add(createMemberType(fwdDecl, "val", diFile, 0u32, 64u64, 0u32, 64u64,
            FlagZero, CreatePointerType(fwdDecl)))
        return fwdDecl
    }

    private func CreateNestedOptionType(enumTy: EnumType, enumMembers: ArrayList<LLVMMetadataRef>,
        boxTy!: Option<BoxType> = None): LLVMMetadataRef {
        let enumDef = enumTy.GetEnumDef()
        let position = enumDef.GetDebugLocation()
        let diFile = GetOrCreateFile(position)
        let optionTy = (GetOptionLikeArgTy(enumTy, cgMod) as EnumType).getOrThrow()
        let argTy = GetOptionLikeArgTy(optionTy, cgMod)
        let constructorType = GetOrCreateEnumCtorType(enumTy)
        let hasCoreOption = argTy.IsEnum() && IsOptionOrOptionLike(argTy)
        if (IsReferenceType(optionTy, cgMod) && !hasCoreOption) {
            let defPackage = createNameSpace(compileUnit, enumDef.GetPackageName(), false)
            let name = if (enumTy.IsOption()) { GenerateCustomTypeName(enumTy, needPkgPrefix: false) } else {
                "E2$" + GenerateCustomTypeName(enumTy, needPkgPrefix: false)
            }
            let boxOffset = if (boxTy.isSome()) { 64u64 } else { 0u64 }
            let fwdDecl = createStructType(defPackage, name, diFile, position.GetBeginPos().line,
                64u64 + 64u64 + boxOffset, 0u32, FlagZero, LLVMNullMetadata(), ArrayList<LLVMMetadataRef>(),
                0u32, LLVMNullMetadata(), "$" + boxOffset.toString() + "_" + enumTy.ToString())
            if (let Some(box) <- boxTy) {
                typeCache[box.objectId] = fwdDecl
            } else {
                typeCache[enumTy.objectId] = fwdDecl
            }
            var argType = GetOrCreateType(optionTy)
            if (!optionTy.IsOption()) {
                argType = CreatePointerType(argType)
            }
            enumMembers.add(createMemberType(fwdDecl, "constructor", diFile, 0u32, 8u64, 0u32,
                boxOffset, FlagZero, constructorType))
            enumMembers.add(createMemberType(fwdDecl, "val", diFile, 0u32, GetSizeInBits(argType), 0u32,
                64u64 + boxOffset, FlagZero, argType))
            return fwdDecl
        }
        return CreateNonRefOptionType(enumTy, enumMembers, boxTy: boxTy)
    }

    private func CreateNonRefOptionType(enumTy: EnumType, enumMembers: ArrayList<LLVMMetadataRef>,
        boxTy!: Option<BoxType> = None): LLVMMetadataRef {
        let enumDef = enumTy.GetEnumDef()
        let position = enumDef.GetDebugLocation()
        let diFile = GetOrCreateFile(position)
        let argTy = GetOptionLikeArgTy(enumTy, cgMod)
        let argType = GetOrCreateType(argTy)
        let constructorType = GetOrCreateEnumCtorType(enumTy)
        let cgType = CGType.GetOrCreate(cgMod, enumTy).GetLLVMType()
        let totalSize = GetTypeSize(cgType)
        let defPackage = createNameSpace(compileUnit, enumDef.GetPackageName(), false)
        let name = if (enumTy.IsOption()) { GenerateCustomTypeName(enumTy, needPkgPrefix: false) } else {
            "E2$" + GenerateCustomTypeName(enumTy, needPkgPrefix: false)
        }
        let boxOffset = if (boxTy.isSome()) { 64u64 } else { 0u64 }
        let fwdDecl = createStructType(defPackage, name, diFile, position.GetBeginPos().line,
            totalSize + boxOffset, unsafe { LLVMDITypeGetAlignInBits(argType) }, FlagZero, LLVMNullMetadata(),
            ArrayList<LLVMMetadataRef>(), 0u32, LLVMNullMetadata(),
            "$" + boxOffset.toString() + "_" + enumTy.ToString())
        let align = cgMod.GetABITypeAlignment(cgType)
        let ctorCodeGenType = unsafe { LLVMStructGetTypeAtIndex(cgType, 0u32) }
        enumMembers.add(createMemberType(fwdDecl, "constructor", diFile, 0u32,
            GetTypeSize(ctorCodeGenType), align, boxOffset, FlagZero, constructorType))
        let valCodeGenType = unsafe { LLVMStructGetTypeAtIndex(cgType, 1u32) }
        let valOffset = cgMod.GetOffsetOfElement(cgType, 1u32) * 8u64 + boxOffset
        enumMembers.add(createMemberType(fwdDecl, "val", diFile, 0u32, GetTypeSize(valCodeGenType), align,
            valOffset, FlagZero, argType))
        return fwdDecl
    }

    private func IsOptionOrOptionLike(ty: Type): Bool {
        if (!ty.IsEnum()) {
            return false
        }
        return (CGType.GetOrCreate(cgMod, ty) as CGEnumType).getOrThrow().IsOptionLike()
    }

    private func CreateEnumWithArgsType(enumTy: EnumType, enumMembers: ArrayList<LLVMMetadataRef>,
        boxTy!: Option<BoxType> = None): LLVMMetadataRef {
        let enumDef = enumTy.GetEnumDef()
        let defPackage = createNameSpace(compileUnit, enumDef.GetPackageName(), false)
        let position = enumDef.GetDebugLocation()
        let diFile = GetOrCreateFile(position)
        let name = GenerateCustomTypeName(enumTy, needPkgPrefix: false)
        let ctorInfos = enumTy.GetConstructorInfos(cgMod.GetCGContext().GetCHIRBuilder())
        var maxSize = 0u64
        var ctorIndex: Int64 = 0
        for (ctor in ctorInfos) {
            let layoutType = CGType.GetOrCreateEnumCtorLayoutType(cgMod, enumTy, ctorIndex,
                ctor.funcType.getOrThrow().GetParamTypes())
            let size = GetTypeSize(layoutType)
            if (size > maxSize) {
                maxSize = size
            }
            ctorIndex++
        }
        maxSize += 64u64
        let fwdDecl = createStructType(defPackage, "E1$" + name, diFile, position.GetBeginPos().line,
            maxSize, 0u32, FlagVirtual, LLVMNullMetadata(), ArrayList<LLVMMetadataRef>(), 0u32,
            LLVMNullMetadata(), "$" + enumTy.ToString())
        if (let Some(box) <- boxTy) {
            typeCache[box.objectId] = fwdDecl
        } else {
            typeCache[enumTy.objectId] = fwdDecl
        }
        ctorIndex = 0
        for (ctor in ctorInfos) {
            let enumClassType = CreateEnumClassType(enumTy, ctor, fwdDecl, ctorIndex)
            enumMembers.add(createInheritance(fwdDecl, enumClassType, 0u64, 0u32, FlagZero))
            ctorIndex++
        }
        return fwdDecl
    }

    private func CreateEnumClassType(enumTy: EnumType, constructor: EnumCtorInfo,
        subEnumType: LLVMMetadataRef, ctorIndex: Int64): LLVMMetadataRef {
        let enumClassElements = ArrayList<LLVMMetadataRef>()
        let paramTypes = constructor.funcType.getOrThrow().GetParamTypes()
        let enumCtorLayoutType = CGType.GetOrCreateEnumCtorLayoutType(cgMod, enumTy, ctorIndex, paramTypes)
        let sizeofPointer = 64u64
        let totalSize = GetTypeSize(enumCtorLayoutType) + sizeofPointer
        let enumDef = enumTy.GetEnumDef()
        let position = enumDef.GetDebugLocation()
        let diFile = GetOrCreateFile(position)
        let name = GenerateCustomTypeName(enumTy, needPkgPrefix: false)
        let ctorName = name + "_ctor_" + ctorIndex.toString()
        var enumClassType = createStructType(subEnumType, ctorName, diFile, 0u32, totalSize, 0u32,
            FlagZero, LLVMNullMetadata(), ArrayList<LLVMMetadataRef>(), 0u32, LLVMNullMetadata(), "")
        enumClassElements.add(createMemberType(enumClassType, "constructor", diFile, 0u32, 32u64, 0u32,
            64u64, FlagZero, GetOrCreateEnumCtorType(enumTy)))
        let align = cgMod.GetABITypeAlignment(enumCtorLayoutType)
        var argIndex: Int64 = 1
        for (argTy in paramTypes) {
            var argType = GetOrCreateType(argTy)
            if (IsReferenceType(argTy, cgMod) && !IsOption(argTy)) {
                argType = CreatePointerType(argType, sizeInBits: GetSizeInBits(CreateRefType()))
            }
            let offset = cgMod.GetOffsetOfElement(enumCtorLayoutType, UInt32(argIndex)) * 8u64 + sizeofPointer
            enumClassElements.add(createMemberType(enumClassType, "arg_" + argIndex.toString(), diFile, 0u32,
                GetSizeInBits(argType), align, offset, FlagZero, argType))
            argIndex++
        }
        enumClassType = replaceArrays(enumClassType, getOrCreateArray(enumClassElements))
        return enumClassType
    }

    private func CreateMemberPointerType(pointeeType: LLVMMetadataRef, classType: LLVMMetadataRef, sizeInBits: UInt64,
        alignInBits: UInt32, flags: UInt32): LLVMMetadataRef {
        return unsafe {
            LLVMDIBuilderCreateMemberPointerType(raw, pointeeType, classType, sizeInBits, alignInBits, flags)
        }
    }

    private func CreateFile(filename: String, directory: String): LLVMMetadataRef {
        var result = LLVMNullMetadata()
        try (filenameCString = unsafe { LibC.mallocCString(filename) }.asResource(),
            directoryCString = unsafe { LibC.mallocCString(directory) }.asResource()) {
            result = unsafe {
                LLVMDIBuilderCreateFile(raw, filenameCString.value, UIntNative(filename.size),
                    directoryCString.value, UIntNative(directory.size))
            }
        }
        return result
    }

    private func createBasicType(name: String, sizeInBits: UInt64, encoding: UInt32): LLVMMetadataRef {
        var result = LLVMNullMetadata()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe {
                LLVMDIBuilderCreateBasicType(raw, nameCString.value, UIntNative(name.size), sizeInBits, encoding,
                    FlagZero)
            }
        }
        return result
    }

    private func createTypedef(diType: LLVMMetadataRef, name: String, file: LLVMMetadataRef,
        lineNo: UInt32, scope: LLVMMetadataRef): LLVMMetadataRef {
        var result = LLVMNullMetadata()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe {
                LLVMDIBuilderCreateTypedef(raw, diType, nameCString.value, UIntNative(name.size), file,
                    lineNo, scope, 0u32)
            }
        }
        return result
    }

    private func createStructType(scope: LLVMMetadataRef, name: String, file: LLVMMetadataRef,
        lineNo: UInt32, sizeInBits: UInt64, alignInBits: UInt32, flags: UInt32,
        derivedFrom: LLVMMetadataRef, elements: ArrayList<LLVMMetadataRef>, runtimeLang: UInt32,
        vtableHolder: LLVMMetadataRef, uniqueId: String): LLVMMetadataRef {
        var result = LLVMNullMetadata()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource(),
            uniqueIdCString = unsafe { LibC.mallocCString(uniqueId) }.asResource(),
            elementsPtr = LibC.malloc<LLVMMetadataRef>(count: elements.size).asResource()) {
            var idx: Int64 = 0
            while (idx < elements.size) {
                unsafe { (elementsPtr.value + idx).write(elements[idx]) }
                idx++
            }
            result = unsafe {
                LLVMDIBuilderCreateStructType(raw, scope, nameCString.value, UIntNative(name.size), file, lineNo,
                    sizeInBits, alignInBits, flags, derivedFrom, elementsPtr.value, UInt32(elements.size),
                    runtimeLang, vtableHolder, uniqueIdCString.value, UIntNative(uniqueId.size))
            }
        }
        return result
    }

    private func getOrCreateArray(elements: ArrayList<LLVMMetadataRef>): LLVMMetadataRef {
        if (elements.isEmpty()) {
            return unsafe { LLVMDIBuilderGetOrCreateArray(raw, CPointer<LLVMMetadataRef>(), 0) }
        }
        var result = LLVMNullMetadata()
        try (elementsPtr = LibC.malloc<LLVMMetadataRef>(count: elements.size).asResource()) {
            var idx: Int64 = 0
            while (idx < elements.size) {
                unsafe { (elementsPtr.value + idx).write(elements[idx]) }
                idx++
            }
            result = unsafe { LLVMDIBuilderGetOrCreateArray(raw, elementsPtr.value, UIntNative(elements.size)) }
        }
        return result
    }

    private func getOrCreateSubrange(lowerBound: Int64, count: Int64): LLVMMetadataRef {
        return unsafe { LLVMDIBuilderGetOrCreateSubrange(raw, lowerBound, count) }
    }

    private func createArrayType(sizeInBits: UInt64, alignInBits: UInt32, ty: LLVMMetadataRef,
        subscripts: LLVMMetadataRef): LLVMMetadataRef {
        return unsafe { LLVMSelfhostDIBuilderCreateArrayType(raw, sizeInBits, alignInBits, ty, subscripts) }
    }

    private func createReplaceableCompositeType(tag: UInt32, name: String, scope: LLVMMetadataRef,
        file: LLVMMetadataRef, lineNo: UInt32, runtimeLang: UInt32, sizeInBits: UInt64, alignInBits: UInt32,
        flags: UInt32, uniqueId: String): LLVMMetadataRef {
        var result = LLVMNullMetadata()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource(),
            uniqueIdCString = unsafe { LibC.mallocCString(uniqueId) }.asResource()) {
            result = unsafe {
                LLVMDIBuilderCreateReplaceableCompositeType(raw, tag, nameCString.value, UIntNative(name.size),
                    scope, file, lineNo, runtimeLang, sizeInBits, alignInBits, flags, uniqueIdCString.value,
                    UIntNative(uniqueId.size))
            }
        }
        return result
    }

    private func replaceWithDistinct(composite: LLVMMetadataRef): LLVMMetadataRef {
        return unsafe { LLVMSelfhostMDNodeReplaceWithDistinct(composite) }
    }

    private func replaceArrays(composite: LLVMMetadataRef, elements: LLVMMetadataRef): LLVMMetadataRef {
        return unsafe { LLVMSelfhostDIBuilderReplaceArrays(raw, composite, elements) }
    }

    private func createNameSpace(scope: LLVMMetadataRef, name: String, exportSymbols: Bool): LLVMMetadataRef {
        var result = LLVMNullMetadata()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe {
                LLVMDIBuilderCreateNameSpace(raw, scope, nameCString.value, UIntNative(name.size),
                    if (exportSymbols) { 1 } else { 0 })
            }
        }
        return result
    }

    private func createInheritance(ty: LLVMMetadataRef, baseTy: LLVMMetadataRef, baseOffset: UInt64,
        vbPtrOffset: UInt32, flags: UInt32): LLVMMetadataRef {
        return unsafe { LLVMDIBuilderCreateInheritance(raw, ty, baseTy, baseOffset, vbPtrOffset, flags) }
    }

    private func createEnumerator(name: String, value: Int64): LLVMMetadataRef {
        var result = LLVMNullMetadata()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe {
                LLVMDIBuilderCreateEnumerator(raw, nameCString.value, UIntNative(name.size), value, 0)
            }
        }
        return result
    }

    private func createEnumerationType(scope: LLVMMetadataRef, name: String, file: LLVMMetadataRef,
        lineNo: UInt32, sizeInBits: UInt64, alignInBits: UInt32, elements: ArrayList<LLVMMetadataRef>,
        underlyingType: LLVMMetadataRef, uniqueIdentifier: String, isScoped: Bool): LLVMMetadataRef {
        var result = LLVMNullMetadata()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource(),
            uniqueIdCString = unsafe { LibC.mallocCString(uniqueIdentifier) }.asResource(),
            elementsPtr = LibC.malloc<LLVMMetadataRef>(count: elements.size).asResource()) {
            var idx: Int64 = 0
            while (idx < elements.size) {
                unsafe { (elementsPtr.value + idx).write(elements[idx]) }
                idx++
            }
            result = unsafe {
                LLVMSelfhostDIBuilderCreateEnumerationType(raw, scope, nameCString.value, UIntNative(name.size),
                    file, lineNo, sizeInBits, alignInBits, elementsPtr.value, UIntNative(elements.size),
                    underlyingType, uniqueIdCString.value, UIntNative(uniqueIdentifier.size), isScoped)
            }
        }
        return result
    }

    private func getElements(composite: LLVMMetadataRef): ArrayList<LLVMMetadataRef> {
        let count = unsafe {
            LLVMSelfhostDICompositeTypeGetElements(composite, CPointer<LLVMMetadataRef>(), 0)
        }
        let result = ArrayList<LLVMMetadataRef>()
        if (count == 0) {
            return result
        }
        try (elementsPtr = LibC.malloc<LLVMMetadataRef>(count: Int64(count)).asResource()) {
            let actual = unsafe { LLVMSelfhostDICompositeTypeGetElements(composite, elementsPtr.value, count) }
            var idx: UIntNative = 0
            while (idx < actual) {
                result.add(unsafe { (elementsPtr.value + Int64(idx)).read() })
                idx++
            }
        }
        return result
    }

    private func createMethod(scope: LLVMMetadataRef, name: String, linkageName: String, file: LLVMMetadataRef,
        lineNo: UInt32, ty: LLVMMetadataRef, vtableIndex: UInt32, thisAdjustment: Int32,
        vtableHolder: LLVMMetadataRef, flags: UInt32, spFlags: UInt32): LLVMMetadataRef {
        var result = LLVMNullMetadata()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource(),
            linkageNameCString = unsafe { LibC.mallocCString(linkageName) }.asResource()) {
            result = unsafe {
                LLVMSelfhostDIBuilderCreateMethod(raw, scope, nameCString.value, UIntNative(name.size),
                    linkageNameCString.value, UIntNative(linkageName.size), file, lineNo, ty, vtableIndex,
                    thisAdjustment, vtableHolder, flags, spFlags)
            }
        }
        return result
    }

    private func createFunction(scope: LLVMMetadataRef, name: String, linkageName: String, file: LLVMMetadataRef,
        lineNo: UInt32, ty: LLVMMetadataRef, scopeLine: UInt32, flags: UInt32,
        spFlags: UInt32): LLVMMetadataRef {
        var result = LLVMNullMetadata()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource(),
            linkageNameCString = unsafe { LibC.mallocCString(linkageName) }.asResource()) {
            result = unsafe {
                LLVMSelfhostDIBuilderCreateFunction(raw, scope, nameCString.value, UIntNative(name.size),
                    linkageNameCString.value, UIntNative(linkageName.size), file, lineNo, ty, scopeLine, flags,
                    spFlags, LLVMNullMetadata(), LLVMNullMetadata())
            }
        }
        return result
    }

    private func IsOption(ty: Type): Bool {
        if (!ty.IsEnum()) {
            return false
        }
        return (ty as EnumType).getOrThrow().IsOption()
    }

    private func CreateRefType(): LLVMMetadataRef {
        if (refDIType.isNull()) {
            let basicType = createBasicType("Int64", 64u64, DW_ATE_signed)
            refDIType = CreatePointerType(basicType)
        }
        return refDIType
    }

    private func CreatePointerType(diType: LLVMMetadataRef, sizeInBits!: UInt64 = 64u64): LLVMMetadataRef {
        return createPointerType(diType, sizeInBits: sizeInBits)
    }

    private func createPointerType(diType: LLVMMetadataRef, sizeInBits!: UInt64 = 64u64): LLVMMetadataRef {
        var result = LLVMNullMetadata()
        try (nameCString = unsafe { LibC.mallocCString("") }.asResource()) {
            result = unsafe {
                LLVMDIBuilderCreatePointerType(raw, diType, sizeInBits, 0u32, 0u32, nameCString.value, 0)
            }
        }
        return result
    }

    private func createNullPtrType(): LLVMMetadataRef {
        return unsafe { LLVMDIBuilderCreateNullPtrType(raw) }
    }

    private func createMemberType(scope: LLVMMetadataRef, name: String, file: LLVMMetadataRef, lineNo: UInt32,
        sizeInBits: UInt64, alignInBits: UInt32, offsetInBits: UInt64, flags: UInt32,
        diType: LLVMMetadataRef): LLVMMetadataRef {
        var result = LLVMNullMetadata()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe {
                LLVMDIBuilderCreateMemberType(raw, scope, nameCString.value, UIntNative(name.size), file, lineNo,
                    sizeInBits, alignInBits, offsetInBits, flags, diType)
            }
        }
        return result
    }

    private func CreateTypeInfoMember(fwdDecl: LLVMMetadataRef, diFile: LLVMMetadataRef): LLVMMetadataRef {
        return createMemberType(fwdDecl, "$ti", diFile, 0u32, 64u64, 0u32, 0u64, FlagZero,
            CreateRefType())
    }
}

private func GetOptionLikeArgTy(enumTy: EnumType, cgMod: CGModule): Type {
    let cgType = (CGType.GetOrCreate(cgMod, enumTy) as CGEnumType).getOrThrow()
    let index: Int64 = if (cgType.IsAntiOptionLike()) { 1 } else { 0 }
    let someCtor = enumTy.GetConstructorInfos(cgMod.GetCGContext().GetCHIRBuilder())[index]
    return DeRef(someCtor.funcType.getOrThrow().GetParamTypes()[0])
}

@When[os != "macOS" && os != "iOS"]
private func GetOuterTypeOfMemberFunc(chirFunc: Function): Type {
    let parent = chirFunc.GetParentCustomTypeDef().getOrThrow()
    if (parent.GetCustomKind() != CustomDefKind.TYPE_EXTEND) {
        return parent.GetType().getOrThrow()
    }
    return (parent as ExtendDef).getOrThrow().GetExtendedType().getOrThrow()
}

private func IsBoxSelf(ty: Type, cgMod: CGModule): Bool {
    let boxedTy = ty as BoxType
    if (boxedTy.isNone()) {
        return false
    }
    let box = boxedTy.getOrThrow()
    let baseTy = box.GetBaseType()
    let cgType = CGType.GetOrCreate(cgMod, baseTy)
    if (baseTy.IsEnum() && (cgType as CGEnumType).getOrThrow().IsOptionLike()) {
        let enumTy = (baseTy as EnumType).getOrThrow()
        let argTy = DeRef(GetOptionLikeArgTy(enumTy, cgMod))
        return argTy == baseTy || argTy == box
    }
    return false
}

private func IsParaInitFunc(chirFunc: Function): Bool {
    return chirFunc.GetIdentifierWithoutPrefix().startsWith(MANGLE_CANGJIE_PREFIX + MANGLE_FUNC_PARA_INIT_PREFIX)
}

private func GenerateGenericFuncName(funcName: String, genericTypeParams: ArrayList<GenericType>): String {
    var typeName = funcName
    if (!genericTypeParams.isEmpty()) {
        typeName += "<"
        for (ty in genericTypeParams) {
            typeName += ty.GetSrcCodeIdentifier()
            typeName += ","
        }
        typeName = typeName[0..typeName.size - 1]
        typeName += ">"
    }
    return typeName
}

private func ScopeInfoKey(scopeInfo: ArrayList<Int64>): String {
    var key = ""
    for (value in scopeInfo) {
        key += value.toString()
        key += ":"
    }
    return key
}

@When[os == "Windows"]
private func RemovePathPrefix(absolutePath: String, removedPathPrefix: ArrayList<String>): String {
    let split = b'\\'
    var res = absolutePath + "\\"
    let tempRes = LowerAscii(res)
    for (prefix in removedPathPrefix) {
        let lowerPrefix = LowerAscii(prefix)
        let pos = tempRes.indexOf(lowerPrefix) ?? -1
        if (pos == 0) {
            res = res[prefix.size..]
            if (res.isEmpty()) {
                return res
            }
            res = if (res[0] == split) { res[1..] } else { res }
            break
        }
    }
    return if (res.isEmpty()) { res } else { res[0..res.size - 1] }
}

@When[os != "Windows"]
private func RemovePathPrefix(absolutePath: String, removedPathPrefix: ArrayList<String>): String {
    let split = b'/'
    var res = absolutePath + "/"
    for (prefix in removedPathPrefix) {
        let pos = res.indexOf(prefix) ?? -1
        if (pos == 0) {
            res = res[prefix.size..]
            if (res.isEmpty()) {
                return res
            }
            res = if (res[0] == split) { res[1..] } else { res }
            break
        }
    }
    return if (res.isEmpty()) { res } else { res[0..res.size - 1] }
}

@When[os == "Windows"]
private func LowerAscii(value: String): String {
    let builder = StringBuilder()
    for (byte in value.toArray()) {
        if (byte >= b'A' && byte <= b'Z') {
            builder.append(String.fromUtf8([byte - b'A' + b'a']))
        } else {
            builder.append(String.fromUtf8([byte]))
        }
    }
    return builder.toString()
}

public func CreateUInt32Metadata(context: LLVMContextHandle, value: UInt64): LLVMMetadataRef {
    let constantValue = unsafe { LLVMConstInt(LLVMInt32TypeInContext(context.raw), value, 0) }
    return unsafe { LLVMValueAsMetadata(constantValue) }
}
