package cjcj::frontend

import cjcj::chir.{BuiltinType, CHIRBuilder, CHIRDeserializer, CHIRSerializer, CustomDefKind, CustomType,
    Function, GetBuiltinTypeWithVTable, GlobalVar}
import cjcj::chir.Block as CHIRBlock
import cjcj::chir.Package as PluginCHIRPackage
import cjcj::chir.Terminator as CHIRTerminator
import cjcj::macro_pkg.{CloseSymbolTable, GetMethodPointer, OpenSymbolTableSafely, RuntimeHandle}
import cjcj::utils.CJC_ASSERT
import std.collection.*

@C
struct PluginResult {
    let data: CPointer<UInt8>
    let size: Int64
    let success: Bool

    init() {
        data = CPointer<UInt8>()
        size = 0
        success = false
    }
}

class ExecutePlugin {
    private let builder: CHIRBuilder
    private var handle: RuntimeHandle = RuntimeHandle()
    private var serializedData: Array<UInt8> = Array<UInt8>()
    private var pluginResult: PluginResult = PluginResult()

    private let srcCodeImportedFuncNames: HashSet<String> = HashSet<String>()
    private let srcCodeImportedVarNames: HashSet<String> = HashSet<String>()
    private let initFuncsForConstVarNames: ArrayList<String> = ArrayList<String>()
    private let unreachableBlockNames: HashMap<String, (String, String)> = HashMap<String, (String, String)>()

    init(builder: CHIRBuilder) {
        this.builder = builder
    }

    ~init() {
        if (handle.opened) {
            let _ = CloseSymbolTable(handle)
        }
    }

    func SerializePackage(pkg: PluginCHIRPackage): Bool {
        serializedData = CHIRSerializer.Serialize(pkg)
        if (serializedData.isEmpty()) {
            return false
        }
        return true
    }

    func Execute(pluginPath: String): Bool {
        handle = OpenSymbolTableSafely(pluginPath)
        if (!handle.opened) {
            return false
        }
        let functionPointer = GetMethodPointer(handle, "executeCHIRPlugins")
        if (functionPointer.isNull()) {
            return false
        }
        let execute = CFunc<(CPointer<UInt8>, Int64) -> PluginResult>(functionPointer)
        let dataHandle = unsafe { acquireArrayRawData(serializedData) }
        try {
            pluginResult = unsafe { execute(dataHandle.pointer, serializedData.size) }
        } finally {
            unsafe { releaseArrayRawData<UInt8>(dataHandle) }
        }
        return pluginResult.success
    }

    func DeserializePluginResult(
        srcCodeImportedFuncs: ArrayList<Function>,
        srcCodeImportedVars: ArrayList<GlobalVar>,
        initFuncsForConstVar: ArrayList<Function>,
        maybeUnreachable: HashMap<CHIRBlock, CHIRTerminator>
    ): Option<PluginCHIRPackage> {
        CHIRPtrToString(srcCodeImportedFuncs, srcCodeImportedVars, initFuncsForConstVar, maybeUnreachable)

        builder.MergeAllocatedInstance()
        builder.GetChirContext().FreeWholePackage()
        builder.GetChirContext().Init()

        try {
            if (!CHIRDeserializer.Deserialize(pluginResult.data, pluginResult.size, builder)) {
                return None
            }
        } catch (e: Exception) {
            return None
        }

        StringToCHIRPtr(srcCodeImportedFuncs, srcCodeImportedVars, initFuncsForConstVar, maybeUnreachable)
        return builder.GetChirContext().GetCurPackage()
    }

    private func CHIRPtrToString(
        srcCodeImportedFuncs: ArrayList<Function>,
        srcCodeImportedVars: ArrayList<GlobalVar>,
        initFuncsForConstVar: ArrayList<Function>,
        maybeUnreachable: HashMap<CHIRBlock, CHIRTerminator>
    ): Unit {
        for (function in srcCodeImportedFuncs) {
            srcCodeImportedFuncNames.add(function.GetIdentifierWithoutPrefix())
        }
        srcCodeImportedFuncs.clear()
        for (variable in srcCodeImportedVars) {
            srcCodeImportedVarNames.add(variable.GetIdentifierWithoutPrefix())
        }
        srcCodeImportedVars.clear()
        for (function in initFuncsForConstVar) {
            initFuncsForConstVarNames.add(function.GetIdentifierWithoutPrefix())
        }
        initFuncsForConstVar.clear()
        for ((block, terminator) in maybeUnreachable) {
            let functionName = block.GetTopLevelFunc().getOrThrow().GetIdentifierWithoutPrefix()
            let blockName = block.GetIdentifierWithoutPrefix()
            if (let Some(parentBlock) <- terminator.GetParentBlock()) {
                let terminatorName = parentBlock.GetIdentifierWithoutPrefix()
                unreachableBlockNames[functionName] = (blockName, terminatorName)
            }
        }
        maybeUnreachable.clear()
    }

    private func StringToCHIRPtr(
        srcCodeImportedFuncs: ArrayList<Function>,
        srcCodeImportedVars: ArrayList<GlobalVar>,
        initFuncsForConstVar: ArrayList<Function>,
        maybeUnreachable: HashMap<CHIRBlock, CHIRTerminator>
    ): Unit {
        let chirPkg = builder.GetChirContext().GetCurPackage().getOrThrow()
        for (definition in chirPkg.GetAllExtendDef()) {
            if (let Some(builtinType) <- (definition.GetExtendedType() as BuiltinType)) {
                GetBuiltinTypeWithVTable(builtinType, builder).AddExtend(definition)
            } else {
                let customType = (definition.GetExtendedType() as CustomType).getOrThrow()
                let customTypeDef = customType.GetCustomTypeDef()
                CJC_ASSERT(customTypeDef.GetCustomKind() != CustomDefKind.TYPE_EXTEND)
                customTypeDef.AddExtend(definition)
            }
        }
        builder.UpdateTypeInCorePackage()

        for (name in srcCodeImportedFuncNames) {
            for (function in chirPkg.GetGlobalFuncsWithBody()) {
                if (function.GetIdentifierWithoutPrefix() == name) {
                    srcCodeImportedFuncs.add(function)
                    break
                }
            }
        }

        for (name in srcCodeImportedVarNames) {
            for (variable in chirPkg.GetGlobalVarsWithInit()) {
                if (variable.GetIdentifierWithoutPrefix() == name) {
                    srcCodeImportedVars.add(variable)
                    break
                }
            }
        }

        for (name in initFuncsForConstVarNames) {
            for (function in chirPkg.GetGlobalFunctions()) {
                if (function.GetIdentifierWithoutPrefix() == name) {
                    initFuncsForConstVar.add(function)
                    break
                }
            }
        }

        for ((functionName, blockNames) in unreachableBlockNames) {
            for (function in chirPkg.GetGlobalFuncsWithBody()) {
                if (function.GetIdentifierWithoutPrefix() != functionName) {
                    continue
                }
                let allBlocks = function.GetBody().getOrThrow().GetAllBlocks()
                var unreachableBlock: Option<CHIRBlock> = None
                var terminator: Option<CHIRTerminator> = None
                for (block in allBlocks) {
                    if (unreachableBlock.isSome() && terminator.isSome()) {
                        break
                    }
                    if (block.GetIdentifierWithoutPrefix() == blockNames[0]) {
                        unreachableBlock = block
                    }
                    if (block.GetIdentifierWithoutPrefix() == blockNames[1]) {
                        terminator = block.GetTerminator()
                    }
                }
                if (let Some(block) <- unreachableBlock) {
                    if (let Some(value) <- terminator) {
                        maybeUnreachable[block] = value
                    }
                }
            }
        }
    }

    func FreeCachedData(): Bool {
        let functionPointer = GetMethodPointer(handle, "freeSerializedMemory")
        if (functionPointer.isNull()) {
            return false
        }
        let freeSerializedMemory = CFunc<() -> Unit>(functionPointer)
        unsafe { freeSerializedMemory() }
        return true
    }
}
