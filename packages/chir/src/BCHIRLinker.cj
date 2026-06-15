package cangjie_compiler::chir

import std.collection.*

public class BCHIRLinker {
    private let topBchir: BCHIR = BCHIR()
    private let functionBodyIndex: HashMap<String, Int64> = HashMap<String, Int64>()
    private let functionPlaceholders: HashMap<String, ArrayList<Int64>> = HashMap<String, ArrayList<Int64>>()
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
            LinkFunctions(pkg, topDef)
            LinkGlobalNames(pkg)
            if (!pkg.GetMainMangledName().isEmpty()) {
                topBchir.SetMainMangledName(pkg.GetMainMangledName())
                topBchir.SetMainExpectedArgs(pkg.GetMainExpectedArgs())
            }
            topBchir.packageName = pkg.packageName
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

    public func GetLinkedBCHIR(): BCHIR {
        return topBchir
    }

    public func GetGlobalId(name: String): Option<Int64> {
        return globalIds.get(name)
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

    private func LinkGlobalInitializers(pkg: BCHIR, topDef: BCHIRDefinition): Unit {
        for (entry in pkg.GetGlobalVars()) {
            TraverseAndLink(pkg, entry.definition, topDef)
            if (let Some(id) <- globalIds.get(entry.name)) {
                topDef.PushOp(OpCode.GVAR_SET)
                topDef.PushCell(id)
            }
        }
    }

    private func LinkFunctions(pkg: BCHIR, topDef: BCHIRDefinition): Unit {
        for (entry in pkg.GetFunctions()) {
            let bodyIndex = topDef.NextIndex()
            ResolveFunctionPlaceholders(entry.name, bodyIndex, topDef)
            BCHIRPushOpWithName(topDef, OpCode.FRAME, entry.name)
            topDef.PushCell(entry.definition.GetNumLVars())
            TraverseAndLink(pkg, entry.definition, topDef)
        }
    }

    private func TraverseAndLink(pkg: BCHIR, definition: BCHIRDefinition, topDef: BCHIRDefinition): Unit {
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
            let next = current + GetLinkedInstructionSize(definition, current, opCode)
            LinkInstructionArguments(pkg, definition, topDef, current, opCode, offset)
            current = next
        }
    }

    private func LinkInstructionArguments(pkg: BCHIR, definition: BCHIRDefinition, topDef: BCHIRDefinition,
        current: Int64, opCode: OpCode, offset: Int64): Unit {
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
            topDef.PushCell(LinkString(pkg, definition.Get(current + 1)))
        } else if (opCode == OpCode.JUMP) {
            topDef.PushCell(definition.Get(current + 1) + offset)
        } else if (opCode == OpCode.BRANCH) {
            topDef.PushCell(definition.Get(current + 1) + offset)
            topDef.PushCell(definition.Get(current + 2) + offset)
        } else if (opCode == OpCode.ALLOCATE_CLASS || opCode == OpCode.BOX || opCode == OpCode.INSTANCEOF) {
            let name = definition.GetMangledNameAnnotation(current)
            topDef.PushCell(GetClassId(name))
            var argIndex: Int64 = 2
            while (argIndex <= GetOpCodeArgSize(opCode)) {
                topDef.PushCell(definition.Get(current + argIndex))
                argIndex++
            }
        } else if (opCode == OpCode.INVOKE || opCode == OpCode.INVOKE_EXC) {
            topDef.PushCell(definition.Get(current + 1))
            topDef.PushCell(GetMethodId(definition.GetMangledNameAnnotation(current)))
            if (opCode == OpCode.INVOKE_EXC) {
                topDef.PushCell(definition.Get(current + 3) + offset)
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

    private func LinkString(pkg: BCHIR, oldIndex: Int64): Int64 {
        return topBchir.AddString(pkg.GetString(oldIndex))
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
                let superId = GetClassId(superName)
                classInfo.superClasses.add(superId)
                LinkClass(pkg, superName)
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
}
