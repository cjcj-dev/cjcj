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
import cjcj::utils.CJC_ASSERT

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
private let FlagZero: UInt32 = 0u32
private let FlagArtificial: UInt32 = 64u32
private let FlagPrototyped: UInt32 = 256u32
private let FlagObjectPointer: UInt32 = 1024u32
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
    private let lexicalBlocks: HashMap<String, LLVMMetadataRef> = HashMap<String, LLVMMetadataRef>()
    private let typeCache: HashMap<Int64, LLVMMetadataRef> = HashMap<Int64, LLVMMetadataRef>()

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
        if (!lineInfoOnly && chirFunc.GetParentCustomTypeDef().isSome() &&
            cgMod.GetCGContext().GetCompileOptions().enableCompileDebug) {
            throw IllegalStateException(
                "BLOCKED: DIBuilder SetSubprogram member full-debug scope/decl path is not ported from C++ DIBuilder.cpp:247-270")
        }
        let scope = namespaceScope
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
            flags, SPFlagDefinition, LLVMNullMetadata(), LLVMNullMetadata())
        unsafe { LLVMSetSubprogram(function, subprogram) }
        curScope = subprogram
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
            return cached
        }
        let diType = CreateDIType(baseTy, isReadOnly: isReadOnly)
        typeCache[baseTy.objectId] = diType
        return diType
    }

    private func CreateDIType(ty: Type, isReadOnly!: Bool = false): LLVMMetadataRef {
        let _ = ty
        let _ = isReadOnly
        throw IllegalStateException(
            "BLOCKED: DIBuilder full debug type lowering is not ported from C++ DIBuilder.cpp:566-1563")
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
