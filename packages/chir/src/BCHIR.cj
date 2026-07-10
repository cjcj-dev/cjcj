package cjcj::chir

import std.collection.*
import cjcj::utils.CJC_ASSERT

public class BCHIRCodePosition {
    public let fileID: Int64
    public let line: Int64
    public let column: Int64

    public init(fileID: Int64, line: Int64, column: Int64) {
        this.fileID = fileID
        this.line = line
        this.column = column
    }

    public func ToString(): String {
        return "${fileID}:${line}:${column}"
    }
}

public class BCHIRDefinition {
    private var numArgs: Int64 = 0
    private var numLVars: Int64 = 0
    private let bytecode: ArrayList<Int64> = ArrayList<Int64>()
    private let mangledNamesAnnotations: HashMap<Int64, String> = HashMap<Int64, String>()
    private let codePositionsAnnotations: HashMap<Int64, BCHIRCodePosition> = HashMap<Int64, BCHIRCodePosition>()

    public init() {}

    public func PushOp(opCode: OpCode): Unit {
        bytecode.add(OpCodeIndex(opCode))
    }

    public func PushCell(value: Int64): Unit {
        bytecode.add(value)
    }

    public func Push8Bytes(value: Int64): Unit {
        bytecode.add(value & 0xffffffff)
        bytecode.add((value >> 32) & 0xffffffff)
    }

    public func Set(index: Int64, value: Int64): Unit {
        CJC_ASSERT(index >= 0 && index < bytecode.size)
        bytecode[index] = value
    }

    public func SetOp(index: Int64, opCode: OpCode): Unit {
        CJC_ASSERT(index >= 0 && index < bytecode.size)
        bytecode[index] = OpCodeIndex(opCode)
    }

    public func Get(index: Int64): Int64 {
        CJC_ASSERT(index >= 0 && index < bytecode.size)
        return bytecode[index]
    }

    public func Get8Bytes(index: Int64): Int64 {
        CJC_ASSERT(index >= 0 && index + 1 < bytecode.size)
        return bytecode[index] | (bytecode[index + 1] << 32)
    }

    public func Size(): Int64 {
        return bytecode.size
    }

    public func NextIndex(): Int64 {
        return bytecode.size
    }

    public func Resize(newSize: Int64): Unit {
        CJC_ASSERT(newSize > bytecode.size)
        while (bytecode.size < newSize) {
            bytecode.add(0)
        }
    }

    public func GetByteCode(): ArrayList<Int64> {
        let out = ArrayList<Int64>()
        for (cell in bytecode) {
            out.add(cell)
        }
        return out
    }

    public func GetByteCodeRef(): ArrayList<Int64> {
        return bytecode
    }

    public func SetNumLVars(num: Int64): Unit {
        numLVars = num
    }

    public func GetNumLVars(): Int64 {
        return numLVars
    }

    public func SetNumArgs(num: Int64): Unit {
        numArgs = num
    }

    public func GetNumArgs(): Int64 {
        return numArgs
    }

    public func AddMangledNameAnnotation(index: Int64, mangledName: String): Unit {
        mangledNamesAnnotations[index] = mangledName
    }

    public func AddCodePositionAnnotation(index: Int64, position: BCHIRCodePosition): Unit {
        codePositionsAnnotations[index] = position
    }

    public func GetMangledNameAnnotation(index: Int64): String {
        return mangledNamesAnnotations.get(index) ?? ""
    }

    public func GetCodePositionAnnotation(index: Int64): Option<BCHIRCodePosition> {
        return codePositionsAnnotations.get(index)
    }

    public func GetMangledNamesAnnotations(): HashMap<Int64, String> {
        return mangledNamesAnnotations
    }

    public func GetCodePositionsAnnotations(): HashMap<Int64, BCHIRCodePosition> {
        return codePositionsAnnotations
    }

    public func Clone(): BCHIRDefinition {
        let cloned = BCHIRDefinition()
        cloned.SetNumArgs(numArgs)
        cloned.SetNumLVars(numLVars)
        for (cell in bytecode) {
            cloned.PushCell(cell)
        }
        for (key in mangledNamesAnnotations.keys()) {
            if (let Some(value) <- mangledNamesAnnotations.get(key)) {
                cloned.AddMangledNameAnnotation(key, value)
            }
        }
        for (key in codePositionsAnnotations.keys()) {
            if (let Some(value) <- codePositionsAnnotations.get(key)) {
                cloned.AddCodePositionAnnotation(key, value)
            }
        }
        return cloned
    }
}

public class BCHIRNamedDefinition {
    public let name: String
    public let definition: BCHIRDefinition

    public init(name: String, definition: BCHIRDefinition) {
        this.name = name
        this.definition = definition
    }
}

public class BCHIRSClassInfo {
    public let superClasses: ArrayList<String> = ArrayList<String>()
    public let vtable: HashMap<String, String> = HashMap<String, String>()
    public var finalizer: String = ""

    public init() {}

    public func Clone(): BCHIRSClassInfo {
        let out = BCHIRSClassInfo()
        for (name in superClasses) {
            out.superClasses.add(name)
        }
        for (key in vtable.keys()) {
            if (let Some(value) <- vtable.get(key)) {
                out.vtable[key] = value
            }
        }
        out.finalizer = finalizer
        return out
    }
}

public class BCHIRClassInfo {
    public let superClasses: ArrayList<Int64> = ArrayList<Int64>()
    public let vtable: HashMap<Int64, Int64> = HashMap<Int64, Int64>()
    public var finalizerIdx: Int64 = 0
    public var mangledName: String = ""

    public init() {}

    public func Clone(): BCHIRClassInfo {
        let out = BCHIRClassInfo()
        for (id in superClasses) {
            out.superClasses.add(id)
        }
        for (key in vtable.keys()) {
            if (let Some(value) <- vtable.get(key)) {
                out.vtable[key] = value
            }
        }
        out.finalizerIdx = finalizerIdx
        out.mangledName = mangledName
        return out
    }
}

public enum BCHIRDefaultFunctionKind {
    | THROW_ARITHMETIC_EXCEPTION | THROW_OVERFLOW_EXCEPTION | THROW_INDEX_OUT_OF_BOUNDS_EXCEPTION
    | THROW_NEGATIVE_ARRAY_SIZE_EXCEPTION | CALL_TO_STRING | THROW_ARITHMETIC_EXCEPTION_MSG
    | THROW_OUT_OF_MEMORY_ERROR | CHECK_IS_ERROR | THROW_ERROR | CALL_PRINT_STACK_TRACE
    | CALL_PRINT_STACK_TRACE_ERROR | MAIN | INVALID
}

public func BCHIRDefaultFunctionKindIndex(kind: BCHIRDefaultFunctionKind): Int64 {
    return match (kind) {
        case BCHIRDefaultFunctionKind.THROW_ARITHMETIC_EXCEPTION => 0
        case BCHIRDefaultFunctionKind.THROW_OVERFLOW_EXCEPTION => 1
        case BCHIRDefaultFunctionKind.THROW_INDEX_OUT_OF_BOUNDS_EXCEPTION => 2
        case BCHIRDefaultFunctionKind.THROW_NEGATIVE_ARRAY_SIZE_EXCEPTION => 3
        case BCHIRDefaultFunctionKind.CALL_TO_STRING => 4
        case BCHIRDefaultFunctionKind.THROW_ARITHMETIC_EXCEPTION_MSG => 5
        case BCHIRDefaultFunctionKind.THROW_OUT_OF_MEMORY_ERROR => 6
        case BCHIRDefaultFunctionKind.CHECK_IS_ERROR => 7
        case BCHIRDefaultFunctionKind.THROW_ERROR => 8
        case BCHIRDefaultFunctionKind.CALL_PRINT_STACK_TRACE => 9
        case BCHIRDefaultFunctionKind.CALL_PRINT_STACK_TRACE_ERROR => 10
        case BCHIRDefaultFunctionKind.MAIN => 11
        case BCHIRDefaultFunctionKind.INVALID => 12
    }
}

extend BCHIRDefaultFunctionKind <: Equatable<BCHIRDefaultFunctionKind> {
    public operator func ==(right: BCHIRDefaultFunctionKind): Bool {
        return BCHIRDefaultFunctionKindIndex(this) == BCHIRDefaultFunctionKindIndex(right)
    }

    public operator func !=(right: BCHIRDefaultFunctionKind): Bool {
        return !(this == right)
    }
}

public class BCHIR {
    public var packageName: String = ""
    public let initFuncsForConsts: ArrayList<String> = ArrayList<String>()
    private let globalVars: ArrayList<BCHIRNamedDefinition> = ArrayList<BCHIRNamedDefinition>()
    private let functions: ArrayList<BCHIRNamedDefinition> = ArrayList<BCHIRNamedDefinition>()
    private var globalInitFunc: String = ""
    private var globalInitLiteralFunc: String = ""
    private let sClassTable: HashMap<String, BCHIRSClassInfo> = HashMap<String, BCHIRSClassInfo>()
    private let types: ArrayList<Type> = ArrayList<Type>()
    private let strings: ArrayList<String> = ArrayList<String>()
    private let stringArrays: ArrayList<InterpreterValue> = ArrayList<InterpreterValue>()
    private let fileNames: ArrayList<String> = ArrayList<String>()
    private var mainMangledName: String = ""
    private let linkedByteCode: BCHIRDefinition = BCHIRDefinition()
    private let classTable: HashMap<Int64, BCHIRClassInfo> = HashMap<Int64, BCHIRClassInfo>()
    private let defaultFuncPtrs: ArrayList<Int64> = ArrayList<Int64>()
    private var expectedNumberOfArgumentsByMain: Int64 = 0
    private var numGlobalVars: Int64 = 0
    private var isCorePackage: Bool = false

    public init() {
        var idx: Int64 = 0
        while (idx < BCHIRDefaultFunctionKindIndex(BCHIRDefaultFunctionKind.INVALID)) {
            defaultFuncPtrs.add(0)
            idx++
        }
    }

    public func Clone(): BCHIR {
        let out = BCHIR()
        out.packageName = packageName
        out.globalInitFunc = globalInitFunc
        out.globalInitLiteralFunc = globalInitLiteralFunc
        out.mainMangledName = mainMangledName
        out.expectedNumberOfArgumentsByMain = expectedNumberOfArgumentsByMain
        out.numGlobalVars = numGlobalVars
        out.isCorePackage = isCorePackage
        for (entry in globalVars) {
            out.AddGlobalVar(entry.name, entry.definition.Clone())
        }
        for (entry in functions) {
            out.AddFunction(entry.name, entry.definition.Clone())
        }
        for (name in sClassTable.keys()) {
            if (let Some(info) <- sClassTable.get(name)) {
                out.AddSClass(name, info.Clone())
            }
        }
        for (ty in types) {
            out.AddType(ty)
        }
        for (text in strings) {
            out.AddString(text)
        }
        for (text in fileNames) {
            out.AddFileName(text)
        }
        for (key in classTable.keys()) {
            if (let Some(info) <- classTable.get(key)) {
                out.AddClass(key, info.Clone())
            }
        }
        var idx: Int64 = 0
        while (idx < defaultFuncPtrs.size) {
            out.defaultFuncPtrs[idx] = defaultFuncPtrs[idx]
            idx++
        }
        for (name in initFuncsForConsts) {
            out.initFuncsForConsts.add(name)
        }
        out.GetLinkedByteCode().Resize(linkedByteCode.Size())
        var cellIdx: Int64 = 0
        while (cellIdx < linkedByteCode.Size()) {
            out.Set(cellIdx, linkedByteCode.Get(cellIdx))
            cellIdx++
        }
        return out
    }

    public func GetLinkedByteCode(): BCHIRDefinition { return linkedByteCode }
    public func Get(index: Int64): Int64 { return linkedByteCode.Get(index) }
    public func Get8Bytes(index: Int64): Int64 { return linkedByteCode.Get8Bytes(index) }
    public func Set(index: Int64, value: Int64): Unit { linkedByteCode.Set(index, value) }
    public func SetOp(index: Int64, opCode: OpCode): Unit { linkedByteCode.SetOp(index, opCode) }
    public func Resize(newSize: Int64): Unit { linkedByteCode.Resize(newSize) }

    public func AddString(text: String): Int64 {
        strings.add(text)
        return strings.size - 1
    }

    public func GetString(index: Int64): String {
        if (index < 0 || index >= strings.size) {
            return ""
        }
        return strings[index]
    }

    public func GetStrings(): ArrayList<String> {
        let out = ArrayList<String>()
        for (text in strings) { out.add(text) }
        return out
    }

    public func StoreStringArray(array: InterpreterValue): InterpreterValue {
        stringArrays.add(array.Clone())
        return InterpreterValue.MakePointer(stringArrays.size - 1)
    }

    public func GetTypes(): ArrayList<Type> {
        let out = ArrayList<Type>()
        for (ty in types) { out.add(ty) }
        return out
    }

    public func AddType(ty: Type): Int64 {
        types.add(ty)
        return types.size - 1
    }

    public func GetTypeAt(index: Int64): Option<Type> {
        if (index < 0 || index >= types.size) {
            return None
        }
        return types[index]
    }

    public func AddFunction(mangledName: String, definition: BCHIRDefinition): Unit {
        ReplaceNamedDefinition(functions, mangledName, definition)
    }

    public func GetFunctions(): ArrayList<BCHIRNamedDefinition> {
        return CopyNamedDefinitions(functions)
    }

    public func AddGlobalVar(mangledName: String, definition: BCHIRDefinition): Unit {
        ReplaceNamedDefinition(globalVars, mangledName, definition)
    }

    public func GetGlobalVars(): ArrayList<BCHIRNamedDefinition> {
        return CopyNamedDefinitions(globalVars)
    }

    public func AddFileName(name: String): Int64 {
        fileNames.add(name)
        return fileNames.size - 1
    }

    public func GetFileName(index: Int64): String {
        if (index < 0 || index >= fileNames.size) {
            return ""
        }
        return fileNames[index]
    }

    public func GetFileNames(): ArrayList<String> {
        let out = ArrayList<String>()
        for (name in fileNames) { out.add(name) }
        return out
    }

    public func SetFileNames(names: ArrayList<String>): Unit {
        fileNames.clear()
        for (name in names) { fileNames.add(name) }
    }

    public func GetNumGlobalVars(): Int64 { return numGlobalVars }
    public func SetNumGlobalVars(num: Int64): Unit { numGlobalVars = num }
    public func SetGlobalInitFunc(name: String): Unit { globalInitFunc = name }
    public func GetGlobalInitFunc(): String { return globalInitFunc }
    public func SetGlobalInitLiteralFunc(name: String): Unit { globalInitLiteralFunc = name }
    public func GetGlobalInitLiteralFunc(): String { return globalInitLiteralFunc }
    public func GetMainMangledName(): String { return mainMangledName }
    public func SetMainMangledName(mangledName: String): Unit { mainMangledName = mangledName }
    public func GetMainExpectedArgs(): Int64 { return expectedNumberOfArgumentsByMain }
    public func SetMainExpectedArgs(value: Int64): Unit { expectedNumberOfArgumentsByMain = value }
    public func SetAsCore(): Unit { isCorePackage = true }
    public func IsCore(): Bool { return isCorePackage }

    public func AddSClass(mangledName: String, classInfo: BCHIRSClassInfo): Unit {
        sClassTable[mangledName] = classInfo.Clone()
    }

    public func GetSClass(mangledName: String): Option<BCHIRSClassInfo> {
        return sClassTable.get(mangledName)
    }

    public func GetSClassTable(): HashMap<String, BCHIRSClassInfo> {
        return sClassTable
    }

    public func AddClass(id: Int64, classInfo: BCHIRClassInfo): Unit {
        classTable[id] = classInfo.Clone()
    }

    public func GetClass(id: Int64): Option<BCHIRClassInfo> {
        return classTable.get(id)
    }

    public func ClassExists(id: Int64): Bool {
        return classTable.contains(id)
    }

    public func SetVtableEntry(classId: Int64, methodId: Int64, index: Int64): Unit {
        if (!classTable.contains(classId)) {
            classTable[classId] = BCHIRClassInfo()
        }
        if (let Some(info) <- classTable.get(classId)) {
            info.vtable[methodId] = index
        }
    }

    public func SetClassFinalizer(classId: Int64, index: Int64): Unit {
        if (!classTable.contains(classId)) {
            classTable[classId] = BCHIRClassInfo()
        }
        if (let Some(info) <- classTable.get(classId)) {
            info.finalizerIdx = index
        }
    }

    public func GetClassFinalizer(classId: Int64): Int64 {
        if (let Some(info) <- classTable.get(classId)) {
            return info.finalizerIdx
        }
        return 0
    }

    public func GetClassTable(): HashMap<Int64, BCHIRClassInfo> {
        return classTable
    }

    public func GetDefaultFunctionPointer(kind: BCHIRDefaultFunctionKind): Int64 {
        let idx = BCHIRDefaultFunctionKindIndex(kind)
        if (idx < 0 || idx >= defaultFuncPtrs.size) {
            return 0
        }
        return defaultFuncPtrs[idx]
    }

    public func SetDefaultFunctionPointer(kind: BCHIRDefaultFunctionKind, index: Int64): Unit {
        let idx = BCHIRDefaultFunctionKindIndex(kind)
        if (idx >= 0 && idx < defaultFuncPtrs.size) {
            defaultFuncPtrs[idx] = index
        }
    }

    public func GetDefaultFuncPtrs(): ArrayList<Int64> {
        let out = ArrayList<Int64>()
        for (item in defaultFuncPtrs) { out.add(item) }
        return out
    }

    public func LinkDefaultFunctions(mangleToPointer: HashMap<String, Int64>): Unit {
        let names = BCHIRDefaultFunctionMangledNames()
        var idx: Int64 = 0
        while (idx < names.size) {
            if (let Some(pointer) <- mangleToPointer.get(names[idx])) {
                defaultFuncPtrs[idx] = pointer
            }
            idx++
        }
        if (let Some(pointer) <- mangleToPointer.get(mainMangledName)) {
            defaultFuncPtrs[BCHIRDefaultFunctionKindIndex(BCHIRDefaultFunctionKind.MAIN)] = pointer
        }
    }

    public func RemoveFunction(name: String): Unit {
        RemoveNamedDefinition(functions, name)
    }

    public func RemoveGlobalVar(name: String): Unit {
        RemoveNamedDefinition(globalVars, name)
    }

    public func RemoveClass(name: String): Unit {
        sClassTable.remove(name)
    }

    public func RemoveDefinition(name: String): Unit {
        RemoveFunction(name)
        RemoveGlobalVar(name)
        RemoveClass(name)
    }
}

public func BCHIRDefaultFunctionMangledNames(): ArrayList<String> {
    let names = ArrayList<String>()
    names.add("rt$ThrowArithmeticException")
    names.add("rt$ThrowOverflowException")
    names.add("rt$ThrowIndexOutOfBoundsException")
    names.add("rt$ThrowNegativeArraySizeException")
    names.add("rt$CallToString")
    names.add("rt$ThrowArithmeticException_msg")
    names.add("rt$ThrowOutOfMemoryError")
    names.add("rt$CheckIsError")
    names.add("rt$ThrowError")
    names.add("rt$CallPrintStackTrace")
    names.add("rt$CallPrintStackTraceError")
    return names
}

private func ReplaceNamedDefinition(items: ArrayList<BCHIRNamedDefinition>, name: String, definition: BCHIRDefinition): Unit {
    var idx: Int64 = 0
    while (idx < items.size) {
        if (items[idx].name == name) {
            items[idx] = BCHIRNamedDefinition(name, definition)
            return
        }
        idx++
    }
    items.add(BCHIRNamedDefinition(name, definition))
}

private func RemoveNamedDefinition(items: ArrayList<BCHIRNamedDefinition>, name: String): Unit {
    var idx: Int64 = 0
    while (idx < items.size) {
        if (items[idx].name == name) {
            items.remove(at: idx)
            return
        }
        idx++
    }
}

private func CopyNamedDefinitions(items: ArrayList<BCHIRNamedDefinition>): ArrayList<BCHIRNamedDefinition> {
    let out = ArrayList<BCHIRNamedDefinition>()
    for (item in items) {
        out.add(BCHIRNamedDefinition(item.name, item.definition.Clone()))
    }
    return out
}
