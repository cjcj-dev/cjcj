package cjcj::macro_pkg

import std.collection.*
import std.convert.*

@When[os != "Windows"]
private let DLOPEN_MODE: Int32 = 0x101

@When[os != "Windows"]
foreign {
    func dlopen(filename: CString, flag: Int32): CPointer<Unit>
    func dlsym(handle: CPointer<Unit>, symbol: CString): CPointer<Unit>
    func dlclose(handle: CPointer<Unit>): Int32
    func free(ptr: CPointer<Unit>): Unit
}

@When[os == "Windows"]
foreign {
    func LoadLibraryA(filename: CString): CPointer<Unit>
    func GetProcAddress(handle: CPointer<Unit>, symbol: CString): CPointer<Unit>
    func FreeLibrary(handle: CPointer<Unit>): Int32
    func free(ptr: CPointer<Unit>): Unit
}

@C
struct RuntimeHeapParamC {
    let regionSize: UIntNative
    let heapSize: UIntNative
    let exemptionThreshold: Float64
    let heapUtilization: Float64
    let heapGrowth: Float64
    let allocationRate: Float64
    let allocationWaitTime: UIntNative

    init(regionSize: UIntNative, heapSize: UIntNative, exemptionThreshold: Float64, heapUtilization: Float64,
        heapGrowth: Float64, allocationRate: Float64, allocationWaitTime: UIntNative) {
        this.regionSize = regionSize
        this.heapSize = heapSize
        this.exemptionThreshold = exemptionThreshold
        this.heapUtilization = heapUtilization
        this.heapGrowth = heapGrowth
        this.allocationRate = allocationRate
        this.allocationWaitTime = allocationWaitTime
    }
}

@C
struct RuntimeGCParamC {
    let gcThreshold: UIntNative
    let garbageThreshold: Float64
    let gcInterval: UInt64
    let backupGCInterval: UInt64
    let gcThreads: Int32

    init(gcThreshold: UIntNative, garbageThreshold: Float64, gcInterval: UInt64,
        backupGCInterval: UInt64, gcThreads: Int32) {
        this.gcThreshold = gcThreshold
        this.garbageThreshold = garbageThreshold
        this.gcInterval = gcInterval
        this.backupGCInterval = backupGCInterval
        this.gcThreads = gcThreads
    }
}

@C
struct RuntimeLogParamC {
    let logLevel: Int32

    init(logLevel: Int32) {
        this.logLevel = logLevel
    }
}

@C
struct RuntimeConcurrencyParamC {
    let thStackSize: UIntNative
    let coStackSize: UIntNative
    let processorNum: UInt32

    init(thStackSize: UIntNative, coStackSize: UIntNative, processorNum: UInt32) {
        this.thStackSize = thStackSize
        this.coStackSize = coStackSize
        this.processorNum = processorNum
    }
}

@C
struct RuntimeConfigParamC {
    let heapParam: RuntimeHeapParamC
    let gcParam: RuntimeGCParamC
    let logParam: RuntimeLogParamC
    let coroutineParam: RuntimeConcurrencyParamC

    init(heapParam: RuntimeHeapParamC, gcParam: RuntimeGCParamC, logParam: RuntimeLogParamC,
        coroutineParam: RuntimeConcurrencyParamC) {
        this.heapParam = heapParam
        this.gcParam = gcParam
        this.logParam = logParam
        this.coroutineParam = coroutineParam
    }
}

private type RuntimeInitFunc = CFunc<(CPointer<RuntimeConfigParamC>) -> Int64>
private type RuntimeFiniFunc = CFunc<() -> Int64>

private let CJ_RUNTIME_INIT: String = "InitCJRuntime"
private let CJ_RUNTIME_FINI: String = "FiniCJRuntime"
private let CJ_NEW_TASK_FROM_C: String = "RunCJTask"
private let CJ_RELEASE_HANDLE_FROM_C: String = "ReleaseHandle"
@When[os == "Windows"]
private let CJ_HEAP_SIZE: String = "CJHEAPSIZE"
@When[os != "Windows"]
private let CJ_HEAP_SIZE: String = "cjHeapSize"
@When[os == "Windows"]
private let CJ_STACK_SIZE: String = "CJSTACKSIZE"
@When[os != "Windows"]
private let CJ_STACK_SIZE: String = "cjStackSize"
private let UNIT_LEN: Int64 = 2
private let KB_SIZE: UIntNative = 1024
private let MB_SIZE: UIntNative = 1024 * 1024
private let MIN_HEAP_SIZE: UIntNative = 4 * 1024
private let MIN_STACK_SIZE: UIntNative = 64
private let MAX_STACK_SIZE: UIntNative = 1024 * 1024

public let REGION_SIZE: UIntNative = 64
public let HEAP_SIZE: UIntNative = 1024 * 1024
public let EXEMPTION_THRESHOLD: Float64 = 0.8
public let HEAP_UTILIZATION: Float64 = 0.6
public let HEAP_GROWTH: Float64 = 0.15
public let ALLOCATION_RATE: Float64 = 10240.0
public let ALLOCATION_WAIT_TIME: UIntNative = 1000
public let GC_THRESHOLD: UIntNative = 20
public let GARBAGE_THRESHOLD: Float64 = 0.5
public let GC_INTERVAL: UInt64 = 150
public let BACKUP_GC_INTERNAL: UInt64 = 240
public let GC_THREADS: Int32 = 8
public let STACK_SIZE: UIntNative = 64 * 1024
public let CO_STACK_SIZE: UIntNative = 4 * 1024
public let PROCESSOR_NUM: UInt32 = 24u32
public let HEAP_INITIAL_SIZE: UIntNative = 64 * 1024

public class RuntimeHandle {
    public var path: String = ""
    public var symbol: String = ""
    public var opened: Bool = false
    public var raw: CPointer<Unit> = CPointer<Unit>()
    public var symbolRaw: CPointer<Unit> = CPointer<Unit>()

    public init() {}

    public init(path: String, raw!: CPointer<Unit> = CPointer<Unit>()) {
        this.path = path
        this.raw = raw
        opened = !raw.isNull()
    }
}

private let openedLibHandles: ArrayList<RuntimeHandle> = ArrayList<RuntimeHandle>()

@When[os != "Windows"]
private func openNativeLibrary(path: CString): CPointer<Unit> {
    return unsafe { dlopen(path, DLOPEN_MODE) }
}

@When[os == "Windows"]
private func openNativeLibrary(path: CString): CPointer<Unit> {
    return unsafe { LoadLibraryA(path) }
}

@When[os != "Windows"]
private func getNativeSymbol(handle: CPointer<Unit>, name: CString): CPointer<Unit> {
    return unsafe { dlsym(handle, name) }
}

@When[os == "Windows"]
private func getNativeSymbol(handle: CPointer<Unit>, name: CString): CPointer<Unit> {
    return unsafe { GetProcAddress(handle, name) }
}

@When[os != "Windows"]
private func closeNativeLibrary(handle: CPointer<Unit>): Int64 {
    return Int64(unsafe { dlclose(handle) })
}

@When[os == "Windows"]
private func closeNativeLibrary(handle: CPointer<Unit>): Int64 {
    return Int64(unsafe { FreeLibrary(handle) })
}

private func getRuntimeEnv(envs: ArrayList<(String, String)>, key: String): Option<String> {
    for ((name, value) in envs) {
        if (name == key) {
            return Some(value)
        }
    }
    return None
}

private func lowerAscii(value: String): String {
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

private func sizeFromEnv(raw: String): Option<UIntNative> {
    let value = lowerAscii(raw.replace(" ", ""))
    if (value.size <= UNIT_LEN) {
        return None
    }
    let unit = value[(value.size - UNIT_LEN)..]
    if (unit != "kb" && unit != "mb" && unit != "gb") {
        return None
    }
    let numberPart = value[0..(value.size - UNIT_LEN)]
    let parsed = try {
        Int64.parse(numberPart)
    } catch (e: Exception) {
        return None
    }
    if (parsed <= 0) {
        return Some(0)
    }
    let base = UIntNative(parsed)
    if (unit == "kb") {
        return Some(base)
    }
    if (unit == "mb") {
        return Some(base * KB_SIZE)
    }
    return Some(base * MB_SIZE)
}

private func heapSizeFromEnv(envs: ArrayList<(String, String)>): UIntNative {
    if (let Some(raw) <- getRuntimeEnv(envs, CJ_HEAP_SIZE)) {
        if (let Some(size) <- sizeFromEnv(raw)) {
            if (size >= MIN_HEAP_SIZE) {
                return size
            }
        }
    }
    return HEAP_SIZE
}

private func stackSizeFromEnv(envs: ArrayList<(String, String)>): UIntNative {
    if (let Some(raw) <- getRuntimeEnv(envs, CJ_STACK_SIZE)) {
        if (let Some(size) <- sizeFromEnv(raw)) {
            if (size >= MIN_STACK_SIZE && size <= MAX_STACK_SIZE) {
                return size
            }
        }
    }
    return CO_STACK_SIZE
}

private func makeRuntimeConfig(envs: ArrayList<(String, String)>): RuntimeConfigParamC {
    return RuntimeConfigParamC(
        RuntimeHeapParamC(REGION_SIZE, heapSizeFromEnv(envs), EXEMPTION_THRESHOLD, HEAP_UTILIZATION, HEAP_GROWTH,
            ALLOCATION_RATE, ALLOCATION_WAIT_TIME),
        RuntimeGCParamC(GC_THRESHOLD, GARBAGE_THRESHOLD, GC_INTERVAL, BACKUP_GC_INTERNAL, GC_THREADS),
        RuntimeLogParamC(6),
        RuntimeConcurrencyParamC(STACK_SIZE, stackSizeFromEnv(envs), PROCESSOR_NUM))
}

public func OpenSymbolTable(libPath: String): RuntimeHandle {
    var result = RuntimeHandle()
    try (path = unsafe { LibC.mallocCString(libPath) }.asResource()) {
        let rawHandle = openNativeLibrary(path.value)
        let handle = RuntimeHandle(libPath, raw: rawHandle)
        if (handle.opened) {
            openedLibHandles.add(handle)
        }
        result = handle
    } catch (e: Exception) {
        result = RuntimeHandle()
    }
    return result
}

public func GetMethod(handle: RuntimeHandle, name: String): Option<String> {
    let pointer = GetMethodPointer(handle, name)
    if (pointer.isNull()) {
        return None
    }
    handle.symbolRaw = pointer
    return Some(name)
}

public func GetMethodPointer(handle: RuntimeHandle, name: String): CPointer<Unit> {
    if (!handle.opened || handle.raw.isNull() || name.isEmpty()) {
        return CPointer<Unit>()
    }
    var result = CPointer<Unit>()
    try (symbolName = unsafe { LibC.mallocCString(name) }.asResource()) {
        let symbol = getNativeSymbol(handle.raw, symbolName.value)
        if (!symbol.isNull()) {
            handle.symbol = name
            handle.symbolRaw = symbol
        }
        result = symbol
    } catch (e: Exception) {
        result = CPointer<Unit>()
    }
    return result
}

public func CloseSymbolTable(handle: RuntimeHandle): Int64 {
    if (!handle.opened || handle.raw.isNull()) {
        handle.opened = false
        return 0
    }
    let ret = closeNativeLibrary(handle.raw)
    handle.opened = false
    handle.raw = CPointer<Unit>()
    handle.symbolRaw = CPointer<Unit>()
    return ret
}

public func PrepareRuntime(handle: RuntimeHandle, initArgs: ArrayList<(String, String)>): Bool {
    return CallRuntime(handle, CJ_RUNTIME_INIT, initArgs) == 0
}

public func FinishRuntime(handle: RuntimeHandle): Unit {
    let method = GetMethodPointer(handle, CJ_RUNTIME_FINI)
    if (method.isNull()) {
        return
    }
    let fini = RuntimeFiniFunc(method)
    unsafe {
        let _ = fini()
    }
}

public func CallRuntime(handle: RuntimeHandle, method: String, envs: ArrayList<(String, String)>): Int64 {
    let methodPtr = GetMethodPointer(handle, method)
    if (methodPtr.isNull()) {
        return 1
    }
    let initFunc = RuntimeInitFunc(methodPtr)
    var result: Int64 = 1
    try (param = LibC.malloc<RuntimeConfigParamC>().asResource()) {
        if (param.value.isNull()) {
            result = 1
        } else {
            unsafe {
                param.value.write(makeRuntimeConfig(envs))
                result = initFunc(param.value)
            }
        }
    } catch (e: Exception) {
        result = 1
    }
    return result
}

public func FreeNativeBuffer(buffer: CPointer<UInt8>): Unit {
    if (!buffer.isNull()) {
        unsafe { free(CPointer<Unit>(buffer)) }
    }
}

public func GetOpenedLibHandles(): ArrayList<RuntimeHandle> {
    return openedLibHandles
}

public func SetOpenedLibHandles(handle: RuntimeHandle): Unit {
    var found = false
    for (item in openedLibHandles) {
        if (item.path == handle.path) {
            found = true
            break
        }
    }
    if (!found) {
        openedLibHandles.add(handle)
    }
}

public func ClearOpenedLibHandles(): Unit {
    openedLibHandles.clear()
}

public class RuntimeInit {
    private static let instance: RuntimeInit = RuntimeInit(true)
    private var initRuntime: Bool = false
    private var handle: Option<RuntimeHandle> = None
    public var runtimeMethodFunc: CPointer<Unit> = CPointer<Unit>()
    public var runtimeReleaseFunc: CPointer<Unit> = CPointer<Unit>()

    public init() {}

    private init(_: Bool) {}

    public static func GetInstance(): RuntimeInit {
        return RuntimeInit.instance
    }

    public func InitRuntime(runtimeLibPath: String, initArgs!: ArrayList<(String, String)> = ArrayList<(String, String)>()): Bool {
        if (!initRuntime) {
            let opened = OpenSymbolTable(runtimeLibPath)
            if (!opened.opened) {
                return false
            }
            // GAP_TODO(self-host runtime reuse): C++ initializes the Cangjie runtime here because
            // the C++ compiler process has no live runtime. The self-host cjc is already running
            // inside that runtime, so reuse it by taking RunCJTask/ReleaseHandle from the runtime
            // library handle instead of calling InitCJRuntime again.
            runtimeMethodFunc = GetMethodPointer(opened, CJ_NEW_TASK_FROM_C)
            runtimeReleaseFunc = GetMethodPointer(opened, CJ_RELEASE_HANDLE_FROM_C)
            if (runtimeMethodFunc.isNull() || runtimeReleaseFunc.isNull()) {
                return false
            }
            handle = Some(opened)
            initRuntime = false
        }
        return true
    }

    public func CloseRuntime(): Unit {
        if (let Some(opened) <- handle) {
            if (initRuntime) {
                FinishRuntime(opened)
                initRuntime = false
            }
            let _ = CloseSymbolTable(opened)
        }
        handle = None
        runtimeMethodFunc = CPointer<Unit>()
        runtimeReleaseFunc = CPointer<Unit>()
        CloseMacroDynamicLibrary()
    }

    public func GetHandle(): Option<RuntimeHandle> {
        return handle
    }

    private func CloseMacroDynamicLibrary(): Unit {
        for (opened in openedLibHandles) {
            let _ = CloseSymbolTable(opened)
        }
        ClearOpenedLibHandles()
    }
}

public class MacroProcMsger {
    private static let instance: MacroProcMsger = MacroProcMsger(true)
    public var macroSrvRun: Bool = false
    public var pipeError: Bool = false
    private let clientInbox: ArrayList<ArrayList<UInt8>> = ArrayList<ArrayList<UInt8>>()
    private let serverInbox: ArrayList<ArrayList<UInt8>> = ArrayList<ArrayList<UInt8>>()

    public init() {}

    private init(_: Bool) {}

    public static func GetInstance(): MacroProcMsger {
        return MacroProcMsger.instance
    }

    public func CloseMacroSrv(): Unit {
        macroSrvRun = false
        clientInbox.clear()
        serverInbox.clear()
    }

    public func SendMsgToSrv(msg: ArrayList<UInt8>): Bool {
        if (msg.isEmpty() || pipeError) {
            return false
        }
        serverInbox.add(msg)
        return true
    }

    public func ReadMsgFromSrv(msg: ArrayList<UInt8>): Bool {
        msg.clear()
        if (clientInbox.isEmpty() || pipeError) {
            return false
        }
        for (byte in clientInbox[0]) {
            msg.add(byte)
        }
        clientInbox.remove(at: 0)
        return true
    }

    public func ReadAllMsgFromSrv(msgVec: ArrayList<ArrayList<UInt8>>): Bool {
        msgVec.clear()
        while (!clientInbox.isEmpty()) {
            let msg = ArrayList<UInt8>()
            for (byte in clientInbox[0]) {
                msg.add(byte)
            }
            msgVec.add(msg)
            clientInbox.remove(at: 0)
        }
        return !pipeError
    }

    public func CloseClientResource(): Unit {
        clientInbox.clear()
    }

    public func SendMsgToClient(msg: ArrayList<UInt8>): Bool {
        if (msg.isEmpty()) {
            return false
        }
        clientInbox.add(msg)
        return true
    }

    public func ReadMsgFromClient(msg: ArrayList<UInt8>): Bool {
        msg.clear()
        if (serverInbox.isEmpty()) {
            return false
        }
        for (byte in serverInbox[0]) {
            msg.add(byte)
        }
        serverInbox.remove(at: 0)
        return true
    }
}
