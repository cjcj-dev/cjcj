package cjcj::chir

import std.collection.*

public class BCHIRLinker {
    private let topBchir: BCHIR = BCHIR()
    private let functionBodyIndex: HashMap<String, Int64> = HashMap<String, Int64>()
    private let functionPlaceholders: HashMap<String, ArrayList<Int64>> = HashMap<String, ArrayList<Int64>>()
    private let fileNameIds: HashMap<String, Int64> = HashMap<String, Int64>()
    private let typeIds: HashMap<Int64, Int64> = HashMap<Int64, Int64>()
    private let stringIds: HashMap<String, Int64> = HashMap<String, Int64>()
    private let globalIds: HashMap<String, Int64> = HashMap<String, Int64>()
    private let classIds: HashMap<String, Int64> = HashMap<String, Int64>()
    private let methodIds: HashMap<String, Int64> = HashMap<String, Int64>()
    private var nextGlobalId: Int64 = 0
    private var nextClassId: Int64 = 1
    private var nextMethodId: Int64 = 1
    private var dummyAbortFuncIdx: Int64 = 0

    public init() {}

    public func Run(packages: ArrayList<BCHIR>): BCHIR {
        let topDef = topBchir.GetLinkedByteCode()
        topDef.Resize(0)
        topDef.PushOp(OpCode.JUMP)
        let jumpToInit = topDef.NextIndex()
        topDef.PushCell(0)
        GenerateDummyAbortFunction(topDef)
        for (pkg in packages) {
            LinkGlobalNames(pkg)
            if (!pkg.GetMainMangledName().isEmpty()) {
                topBchir.SetMainMangledName(pkg.GetMainMangledName())
                topBchir.SetMainExpectedArgs(pkg.GetMainExpectedArgs())
            }
            topBchir.packageName = pkg.packageName
        }
        for (pkg in packages) {
            LinkFunctions(pkg, topDef)
        }
        topDef.Set(jumpToInit, topDef.NextIndex())
        for (pkg in packages) {
            LinkGlobalInitializers(pkg, topDef)
        }
        topDef.PushOp(OpCode.EXIT)
        topBchir.SetNumGlobalVars(nextGlobalId)
        for (pkg in packages) {
            LinkClasses(pkg)
        }
        topBchir.LinkDefaultFunctions(functionBodyIndex)
        return topBchir
    }

    public func RunForConstEval(packages: ArrayList<BCHIR>): HashMap<Int64, InterpreterValue> {
        let globalInitValues = HashMap<Int64, InterpreterValue>()
        let topDef = topBchir.GetLinkedByteCode()
        topDef.Resize(0)
        topDef.PushOp(OpCode.JUMP)
        let jumpOverDummy = topDef.NextIndex()
        topDef.PushCell(0)
        GenerateDummyAbortFunction(topDef)
        topDef.Set(jumpOverDummy, topDef.NextIndex())

        var pkgIndex: Int64 = 0
        while (pkgIndex < packages.size) {
            let pkg = packages[pkgIndex]
            LinkAndInitGlobalVars(pkg, globalInitValues)
            if (!pkg.GetMainMangledName().isEmpty()) {
                topBchir.SetMainMangledName(pkg.GetMainMangledName())
                topBchir.SetMainExpectedArgs(pkg.GetMainExpectedArgs())
            }
            topBchir.packageName = pkg.packageName
            pkgIndex++
        }

        topDef.PushOp(OpCode.JUMP)
        let jumpOverFunctions = topDef.NextIndex()
        topDef.PushCell(0)
        for (pkg in packages) {
            LinkFunctions(pkg, topDef)
        }
        topDef.Set(jumpOverFunctions, topDef.NextIndex())

        if (!packages.isEmpty()) {
            GenerateCallsToConstInitFunctions(packages[packages.size - 1].initFuncsForConsts, topDef)
        }
        topDef.PushOp(OpCode.EXIT)
        topBchir.SetNumGlobalVars(nextGlobalId)
        for (pkg in packages) {
            LinkClasses(pkg)
        }
        topBchir.LinkDefaultFunctions(functionBodyIndex)
        return globalInitValues
    }

    public func GetLinkedBCHIR(): BCHIR {
        return topBchir
    }

    public func GetGlobalId(name: String): Option<Int64> {
        return globalIds.get(name)
    }

    public func GetGVARId(name: String): Int64 {
        return globalIds.get(name) ?? -1
    }

    private func GenerateDummyAbortFunction(topDef: BCHIRDefinition): Unit {
        dummyAbortFuncIdx = topDef.NextIndex()
        BCHIRPushOpWithName(topDef, OpCode.FRAME, "linker_dummy_abort_function")
        topDef.PushCell(0)
        topDef.PushOp(OpCode.ABORT)
    }

    private func LinkGlobalNames(pkg: BCHIR): Unit {
        for (entry in pkg.GetGlobalVars()) {
            if (!globalIds.contains(entry.name)) {
                globalIds[entry.name] = FreshGlobalId()
            }
        }
    }

    private func LinkAndInitGlobalVars(pkg: BCHIR, globalInitValues: HashMap<Int64, InterpreterValue>): Unit {
        for (entry in pkg.GetGlobalVars()) {
            if (!globalIds.contains(entry.name)) {
                let id = FreshGlobalId()
                globalIds[entry.name] = id
                globalInitValues[id] = ByteCodeToIval(entry.definition, pkg)
            }
        }
    }

    private func GenerateCallsToConstInitFunctions(constInitFuncs: ArrayList<String>, topDef: BCHIRDefinition): Unit {
        for (name in constInitFuncs) {
            if (let Some(functionIndex) <- functionBodyIndex.get(name)) {
                topDef.PushOp(OpCode.FUNC)
                topDef.PushCell(functionIndex)
                topDef.PushOp(OpCode.APPLY)
                topDef.PushCell(1)
                topDef.PushOp(OpCode.DROP)
            }
        }
    }

    // C++: Interpreter/Utils.cpp:150-211 Interpreter::ByteCodeToIval.
    private func ByteCodeToIval(definition: BCHIRDefinition, bchir: BCHIR): InterpreterValue {
        let opCode = OpCodeFromIndex(definition.Get(0))
        return match (opCode) {
            case OpCode.UINT8 => InterpreterValue.MakeUInt(InterpreterValueKind.IUINT8, definition.Get(1))
            case OpCode.UINT16 => InterpreterValue.MakeUInt(InterpreterValueKind.IUINT16, definition.Get(1))
            case OpCode.UINT32 => InterpreterValue.MakeUInt(InterpreterValueKind.IUINT32, definition.Get(1))
            case OpCode.UINT64 => InterpreterValue.MakeUInt(InterpreterValueKind.IUINT64, definition.Get8Bytes(1))
            case OpCode.UINTNAT => IValUtils.PrimitiveUIntNat(definition.Get8Bytes(1))
            case OpCode.INT8 => InterpreterValue.MakeInt(InterpreterValueKind.IINT8, definition.Get(1))
            case OpCode.INT16 => InterpreterValue.MakeInt(InterpreterValueKind.IINT16, definition.Get(1))
            case OpCode.INT32 => InterpreterValue.MakeInt(InterpreterValueKind.IINT32, definition.Get(1))
            case OpCode.INT64 => InterpreterValue.MakeInt(InterpreterValueKind.IINT64, definition.Get8Bytes(1))
            case OpCode.INTNAT => IValUtils.PrimitiveIntNat(definition.Get8Bytes(1))
            case OpCode.FLOAT16 => InterpreterValue.MakeFloat(InterpreterValueKind.IFLOAT16,
                Float64(Float32.fromBits(UInt32(definition.Get(1)))))
            case OpCode.FLOAT32 => InterpreterValue.MakeFloat(InterpreterValueKind.IFLOAT32,
                Float64(Float32.fromBits(UInt32(definition.Get(1)))))
            case OpCode.FLOAT64 =>
                let raw = definition.Get8Bytes(1)
                let bits = if (raw >= 0) { UInt64(raw) } else { UInt64.Max - UInt64(-(raw + 1)) }
                InterpreterValue.MakeFloat(InterpreterValueKind.IFLOAT64, Float64.fromBits(bits))
            case OpCode.RUNE => InterpreterValue.MakeRune(Rune(definition.Get(1)))
            case OpCode.BOOL => InterpreterValue.MakeBool(definition.Get(1) != 0)
            case OpCode.UNIT => InterpreterValue.MakeUnit()
            case OpCode.NULLPTR => InterpreterValue.MakeNull()
            case OpCode.STRING => InterpreterValue.MakeString(bchir.GetString(definition.Get(1)))
            case _ => InterpreterValue.MakeInvalid()
        }
    }

    private func LinkGlobalInitializers(pkg: BCHIR, topDef: BCHIRDefinition): Unit {
        let fileMap = UnlinkedFilesToLinkedFiles(pkg.GetFileNames())
        let typeMap = UnlinkedTypesToLinkedTypes(pkg.GetTypes())
        let stringMap = UnlinkedStringsToLinkedStrings(pkg.GetStrings())
        for (entry in pkg.GetGlobalVars()) {
            TraverseAndLink(pkg, entry.definition, topDef, fileMap, typeMap, stringMap)
            if (let Some(id) <- globalIds.get(entry.name)) {
                topDef.PushOp(OpCode.GVAR_SET)
                topDef.PushCell(id)
            }
        }
    }

    private func LinkFunctions(pkg: BCHIR, topDef: BCHIRDefinition): Unit {
        let fileMap = UnlinkedFilesToLinkedFiles(pkg.GetFileNames())
        let typeMap = UnlinkedTypesToLinkedTypes(pkg.GetTypes())
        let stringMap = UnlinkedStringsToLinkedStrings(pkg.GetStrings())
        for (entry in pkg.GetFunctions()) {
            let bodyIndex = topDef.NextIndex()
            ResolveFunctionPlaceholders(entry.name, bodyIndex, topDef)
            BCHIRPushOpWithName(topDef, OpCode.FRAME, entry.name)
            topDef.PushCell(entry.definition.GetNumLVars())
            TraverseAndLink(pkg, entry.definition, topDef, fileMap, typeMap, stringMap)
        }
    }

    private func TraverseAndLink(pkg: BCHIR, definition: BCHIRDefinition, topDef: BCHIRDefinition,
        fileMap: ArrayList<Int64>, typeMap: ArrayList<Int64>, stringMap: ArrayList<Int64>): Unit {
        let offset = topDef.NextIndex()
        var current: Int64 = 0
        while (current < definition.Size()) {
            let opCode = OpCodeFromIndex(definition.Get(current))
            let outIndex = topDef.NextIndex()
            topDef.PushOp(opCode)
            let mangledName = definition.GetMangledNameAnnotation(current)
            if (!mangledName.isEmpty()) {
                topDef.AddMangledNameAnnotation(outIndex, mangledName)
            }
            if (let Some(position) <- definition.GetCodePositionAnnotation(current)) {
                topDef.AddCodePositionAnnotation(outIndex, BCHIRCodePosition(MapIndex(fileMap, position.fileID),
                    position.line, position.column))
            }
            let next = current + GetLinkedInstructionSize(definition, current, opCode)
            LinkInstructionArguments(pkg, definition, topDef, current, opCode, offset, typeMap, stringMap)
            current = next
        }
    }

    private func LinkInstructionArguments(pkg: BCHIR, definition: BCHIRDefinition, topDef: BCHIRDefinition,
        current: Int64, opCode: OpCode, offset: Int64, typeMap: ArrayList<Int64>, stringMap: ArrayList<Int64>): Unit {
        if (opCode == OpCode.GVAR) {
            let name = definition.GetMangledNameAnnotation(current)
            if (let Some(id) <- globalIds.get(name)) {
                topDef.PushCell(id)
            } else {
                topDef.SetOp(topDef.NextIndex() - 1, OpCode.FUNC)
                topDef.PushCell(FunctionIndexOrPlaceholder(name, topDef))
            }
        } else if (opCode == OpCode.FUNC) {
            let name = definition.GetMangledNameAnnotation(current)
            topDef.PushCell(FunctionIndexOrPlaceholder(name, topDef))
        } else if (opCode == OpCode.STRING) {
            topDef.PushCell(MapIndex(stringMap, definition.Get(current + 1)))
        } else if (opCode == OpCode.JUMP) {
            topDef.PushCell(definition.Get(current + 1) + offset)
        } else if (opCode == OpCode.BRANCH) {
            topDef.PushCell(definition.Get(current + 1) + offset)
            topDef.PushCell(definition.Get(current + 2) + offset)
        } else if (opCode == OpCode.ALLOCATE_CLASS || opCode == OpCode.ALLOCATE_CLASS_EXC) {
            let name = definition.GetMangledNameAnnotation(current)
            topDef.PushCell(GetClassId(name))
            topDef.PushCell(definition.Get(current + 2))
            if (opCode == OpCode.ALLOCATE_CLASS_EXC) {
                topDef.PushCell(definition.Get(current + 3) + offset)
            }
        } else if (opCode == OpCode.BOX || opCode == OpCode.INSTANCEOF) {
            let name = definition.GetMangledNameAnnotation(current)
            let classId = GetClassId(name)
            if (let None <- pkg.GetSClass(name)) {
                LinkClass(pkg, name)
            }
            topDef.PushCell(classId)
        } else if (opCode == OpCode.INVOKE || opCode == OpCode.INVOKE_EXC) {
            topDef.PushCell(definition.Get(current + 1))
            topDef.PushCell(GetMethodId(definition.GetMangledNameAnnotation(current)))
            if (opCode == OpCode.INVOKE_EXC) {
                topDef.PushCell(definition.Get(current + 3) + offset)
            }
        } else if (opCode == OpCode.INTRINSIC1) {
            topDef.PushCell(definition.Get(current + 1))
            topDef.PushCell(MapOptionalTypeIndex(typeMap, definition.Get(current + 2)))
        } else if (opCode == OpCode.SYSCALL) {
            let numberOfArgs = definition.Get(current + 2)
            topDef.PushCell(MapIndex(stringMap, definition.Get(current + 1)))
            topDef.PushCell(numberOfArgs)
            topDef.PushCell(MapIndex(typeMap, definition.Get(current + 3)))
            var argIndex: Int64 = 0
            while (argIndex < numberOfArgs) {
                topDef.PushCell(MapIndex(typeMap, definition.Get(current + 4 + argIndex)))
                argIndex++
            }
        } else if (opCode == OpCode.SWITCH) {
            LinkSwitch(definition, topDef, current, offset)
        } else if (opCode == OpCode.CAPPLY) {
            let argsSize = definition.Get(current + 1)
            topDef.PushCell(argsSize)
            var typeIndex: Int64 = 0
            while (typeIndex <= argsSize) {
                topDef.PushCell(MapIndex(typeMap, definition.Get(current + 2 + typeIndex)))
                typeIndex++
            }
        } else if (opCode == OpCode.GETREF || opCode == OpCode.STOREINREF || opCode == OpCode.FIELD_TPL) {
            let pathSize = definition.Get(current + 1)
            var argIndex: Int64 = 1
            while (argIndex <= GetOpCodeArgSize(opCode) + pathSize) {
                topDef.PushCell(definition.Get(current + argIndex))
                argIndex++
            }
        } else if (OpHasExceptionHandler(opCode)) {
            CopyExceptionOpArgs(definition, topDef, current, opCode, offset)
        } else {
            var argIndex: Int64 = 1
            while (argIndex <= GetOpCodeArgSize(opCode)) {
                topDef.PushCell(definition.Get(current + argIndex))
                argIndex++
            }
        }
    }

    private func CopyExceptionOpArgs(definition: BCHIRDefinition, topDef: BCHIRDefinition, current: Int64,
        opCode: OpCode, offset: Int64): Unit {
        let argSize = GetOpCodeArgSize(opCode)
        var argIndex: Int64 = 1
        while (argIndex <= argSize) {
            let isLast = argIndex == argSize
            if (isLast) {
                topDef.PushCell(definition.Get(current + argIndex) + offset)
            } else {
                topDef.PushCell(definition.Get(current + argIndex))
            }
            argIndex++
        }
    }

    private func GetLinkedInstructionSize(definition: BCHIRDefinition, current: Int64, opCode: OpCode): Int64 {
        if (opCode == OpCode.SWITCH) {
            let caseCount = definition.Get(current + 2)
            return 1 + 2 + caseCount * 2 + 1 + caseCount
        }
        if (opCode == OpCode.SYSCALL) {
            return 4 + definition.Get(current + 2)
        }
        if (opCode == OpCode.CAPPLY) {
            return 3 + definition.Get(current + 1)
        }
        if (opCode == OpCode.GETREF || opCode == OpCode.STOREINREF || opCode == OpCode.FIELD_TPL) {
            return 2 + definition.Get(current + 1)
        }
        return 1 + GetOpCodeArgSize(opCode)
    }

    private func FunctionIndexOrPlaceholder(name: String, topDef: BCHIRDefinition): Int64 {
        if (let Some(index) <- functionBodyIndex.get(name)) {
            return index
        }
        let placeholder = topDef.NextIndex()
        if (let Some(placeholders) <- functionPlaceholders.get(name)) {
            placeholders.add(placeholder)
        } else {
            let placeholders = ArrayList<Int64>()
            placeholders.add(placeholder)
            functionPlaceholders[name] = placeholders
        }
        return dummyAbortFuncIdx
    }

    private func ResolveFunctionPlaceholders(name: String, index: Int64, topDef: BCHIRDefinition): Unit {
        functionBodyIndex[name] = index
        if (let Some(placeholders) <- functionPlaceholders.get(name)) {
            for (placeholder in placeholders) {
                topDef.Set(placeholder, index)
            }
            functionPlaceholders.remove(name)
        }
    }

    private func LinkClasses(pkg: BCHIR): Unit {
        for (name in pkg.GetSClassTable().keys()) {
            LinkClass(pkg, name)
        }
    }

    private func LinkClass(pkg: BCHIR, name: String): Unit {
        let classId = GetClassId(name)
        if (topBchir.ClassExists(classId)) {
            return
        }
        let classInfo = BCHIRClassInfo()
        classInfo.mangledName = name
        if (let Some(serialized) <- pkg.GetSClass(name)) {
            for (superName in serialized.superClasses) {
                LinkClass(pkg, superName)
            }
            for (superName in serialized.superClasses) {
                let superId = GetClassId(superName)
                AddUniqueClassId(classInfo, superId)
                if (let Some(superInfo) <- topBchir.GetClass(superId)) {
                    for (indirectSuperId in superInfo.superClasses) {
                        AddUniqueClassId(classInfo, indirectSuperId)
                    }
                }
            }
            for (methodName in serialized.vtable.keys()) {
                if (let Some(funcName) <- serialized.vtable.get(methodName)) {
                    classInfo.vtable[GetMethodId(methodName)] = functionBodyIndex.get(funcName) ?? dummyAbortFuncIdx
                }
            }
            if (!serialized.finalizer.isEmpty()) {
                classInfo.finalizerIdx = functionBodyIndex.get(serialized.finalizer) ?? 0
            }
        }
        topBchir.AddClass(classId, classInfo)
    }

    private func GetClassId(name: String): Int64 {
        if (let Some(id) <- classIds.get(name)) {
            return id
        }
        let next = nextClassId
        nextClassId++
        classIds[name] = next
        return next
    }

    private func GetMethodId(name: String): Int64 {
        if (let Some(id) <- methodIds.get(name)) {
            return id
        }
        let next = nextMethodId
        nextMethodId++
        methodIds[name] = next
        return next
    }

    private func FreshGlobalId(): Int64 {
        let next = nextGlobalId
        nextGlobalId++
        return next
    }

    private func UnlinkedFilesToLinkedFiles(fileNames: ArrayList<String>): ArrayList<Int64> {
        let out = ArrayList<Int64>()
        for (name in fileNames) {
            if (let Some(index) <- fileNameIds.get(name)) {
                out.add(index)
            } else {
                let next = topBchir.AddFileName(name)
                fileNameIds[name] = next
                out.add(next)
            }
        }
        return out
    }

    private func UnlinkedTypesToLinkedTypes(types: ArrayList<Type>): ArrayList<Int64> {
        let out = ArrayList<Int64>()
        for (ty in types) {
            let key = ty.objectId
            if (let Some(index) <- typeIds.get(key)) {
                out.add(index)
            } else {
                let next = topBchir.AddType(ty)
                typeIds[key] = next
                out.add(next)
            }
        }
        return out
    }

    private func UnlinkedStringsToLinkedStrings(strings: ArrayList<String>): ArrayList<Int64> {
        let out = ArrayList<Int64>()
        for (text in strings) {
            if (let Some(index) <- stringIds.get(text)) {
                out.add(index)
            } else {
                let next = topBchir.AddString(text)
                stringIds[text] = next
                out.add(next)
            }
        }
        return out
    }

    private func MapIndex(map: ArrayList<Int64>, oldIndex: Int64): Int64 {
        if (oldIndex >= 0 && oldIndex < map.size) {
            return map[oldIndex]
        }
        return oldIndex
    }

    private func MapOptionalTypeIndex(typeMap: ArrayList<Int64>, oldIndex: Int64): Int64 {
        if (oldIndex == 4294967295) {
            return oldIndex
        }
        return MapIndex(typeMap, oldIndex)
    }

    private func LinkSwitch(definition: BCHIRDefinition, topDef: BCHIRDefinition, current: Int64, offset: Int64): Unit {
        let caseCount = definition.Get(current + 2)
        let caseStart = current + 3
        topDef.PushCell(definition.Get(current + 1))
        topDef.PushCell(caseCount)
        var caseIndex: Int64 = 0
        while (caseIndex < caseCount) {
            topDef.Push8Bytes(definition.Get8Bytes(caseStart + caseIndex * 2))
            caseIndex++
        }
        let defaultTargetIndex = caseStart + caseCount * 2
        topDef.PushCell(definition.Get(defaultTargetIndex) + offset)
        var targetIndex: Int64 = 0
        while (targetIndex < caseCount) {
            topDef.PushCell(definition.Get(defaultTargetIndex + 1 + targetIndex) + offset)
            targetIndex++
        }
    }

    private func AddUniqueClassId(classInfo: BCHIRClassInfo, classId: Int64): Unit {
        for (existing in classInfo.superClasses) {
            if (existing == classId) {
                return
            }
        }
        classInfo.superClasses.add(classId)
    }
}
