package cjcj::macro_pkg

import cjcj::basic.{Errorln, Warningln}
import cjcj::utils.FileUtil
import std.collection.*
import std.convert.*
import std.sync.*
import std.time.*

foreign {
    func perror(message: CString): Unit
}

@When[os == "Linux"]
@C
struct FdSet {
    var bits: VArray<UIntNative, $16>

    init() {
        bits = VArray<UIntNative, $16>({ _: Int64 => UIntNative(0) })
    }
}

@When[os == "macOS" || os == "iOS"]
@C
struct FdSet {
    var bits: VArray<UInt32, $32>

    init() {
        bits = VArray<UInt32, $32>({ _: Int64 => 0u32 })
    }
}

@When[os == "Linux" || os == "macOS" || os == "iOS"]
@C
struct Timeval {
    var tvSec: IntNative
    var tvUsec: IntNative

    init(tvSec: IntNative, tvUsec: IntNative) {
        this.tvSec = tvSec
        this.tvUsec = tvUsec
    }
}

@When[os == "Linux" || os == "macOS" || os == "iOS"]
foreign {
    func close(fd: Int32): Int32
    func read(fd: Int32, buf: CPointer<UInt8>, count: UIntNative): IntNative
    func write(fd: Int32, buf: CPointer<UInt8>, count: UIntNative): IntNative
    func select(nfds: Int32, readfds: CPointer<FdSet>, writefds: CPointer<FdSet>,
        exceptfds: CPointer<FdSet>, timeout: CPointer<Timeval>): Int32
}

@When[os == "Windows"]
foreign {
    func CloseHandle(handle: CPointer<Unit>): Int32
    func WriteFile(handle: CPointer<Unit>, buffer: CPointer<UInt8>, bytesToWrite: UInt32,
        bytesWritten: CPointer<UInt32>, overlapped: CPointer<Unit>): Int32
    func ReadFile(handle: CPointer<Unit>, buffer: CPointer<UInt8>, bytesToRead: UInt32,
        bytesRead: CPointer<UInt32>, overlapped: CPointer<Unit>): Int32
    func PeekNamedPipe(handle: CPointer<Unit>, buffer: CPointer<UInt8>, bufferSize: UInt32,
        bytesRead: CPointer<UInt32>, totalBytesAvail: CPointer<UInt32>, bytesLeftThisMessage: CPointer<UInt32>): Int32
    func GetLastError(): UInt32
}

@When[os == "Linux"]
private func FD_ZERO(set: CPointer<FdSet>): Unit {
    var idx: Int64 = 0
    unsafe {
        var value = set.read()
        while (idx < 16) {
            value.bits[idx] = UIntNative(0)
            idx++
        }
        set.write(value)
    }
}

@When[os == "Linux"]
private func FD_SET(fd: Int32, set: CPointer<FdSet>): Unit {
    unsafe {
        var value = set.read()
        let word = Int64(fd) / 64
        let bit = UIntNative(Int64(fd) % 64)
        value.bits[word] = value.bits[word] | (UIntNative(1) << bit)
        set.write(value)
    }
}

@When[os == "Linux"]
private func FD_ISSET(fd: Int32, set: CPointer<FdSet>): Bool {
    unsafe {
        let value = set.read()
        let word = Int64(fd) / 64
        let bit = UIntNative(Int64(fd) % 64)
        return (value.bits[word] & (UIntNative(1) << bit)) != UIntNative(0)
    }
}

@When[os == "macOS" || os == "iOS"]
private func FD_ZERO(set: CPointer<FdSet>): Unit {
    var idx: Int64 = 0
    unsafe {
        var value = set.read()
        while (idx < 32) {
            value.bits[idx] = 0u32
            idx++
        }
        set.write(value)
    }
}

@When[os == "macOS" || os == "iOS"]
private func FD_SET(fd: Int32, set: CPointer<FdSet>): Unit {
    unsafe {
        var value = set.read()
        let word = Int64(fd) / 32
        let bit = UInt32(Int64(fd) % 32)
        value.bits[word] = value.bits[word] | (1u32 << bit)
        set.write(value)
    }
}

@When[os == "macOS" || os == "iOS"]
private func FD_ISSET(fd: Int32, set: CPointer<FdSet>): Bool {
    unsafe {
        let value = set.read()
        let word = Int64(fd) / 32
        let bit = UInt32(Int64(fd) % 32)
        return (value.bits[word] & (1u32 << bit)) != 0u32
    }
}

@When[os == "Linux"]
private let DLOPEN_MODE: Int32 = 0x101

@When[os == "macOS" || os == "iOS"]
private let DLOPEN_MODE: Int32 = 0x9

@When[os != "Windows"]
foreign {
    func dlopen(filename: CString, flag: Int32): CPointer<Unit>
    func dlsym(handle: CPointer<Unit>, symbol: CString): CPointer<Unit>
    func dlclose(handle: CPointer<Unit>): Int32
    func realpath(path: CString, resolvedPath: CString): CString
    func dlerror(): CString
    func free(ptr: CString): Unit
}

// glibc: LM_ID_NEWLM=-1, RTLD_NOW=2, RTLD_DI_LMID=1.
// dlmopen rejects RTLD_GLOBAL outside the base namespace (invalid mode).
// A second libcangjie-runtime.so must not be dlopen'd into the base namespace:
// Loader.cpp:18 uses dlopen(RTLD_NOW|RTLD_GLOBAL), and the first SONAME wins.
@When[os == "Linux"]
private let LM_ID_NEWLM: Int64 = -1

@When[os == "Linux"]
private let RTLD_DI_LMID: Int32 = 1

@When[os == "Linux"]
private let RTLD_NOW_LOCAL: Int32 = 0x2

@When[os == "Linux"]
foreign {
    func dlmopen(lmid: IntNative, filename: CString, flag: Int32): CPointer<Unit>
    func dlinfo(handle: CPointer<Unit>, request: Int32, info: CPointer<Int64>): Int32
}

@When[os == "Windows"]
foreign {
    func LoadLibraryA(filename: CString): CPointer<Unit>
    func GetModuleHandleA(filename: CString): CPointer<Unit>
    func GetProcAddress(handle: CPointer<Unit>, symbol: CString): CPointer<Unit>
    func FreeLibrary(handle: CPointer<Unit>): Int32
    func free(ptr: CString): Unit
}

@C
struct RuntimeHeapParamC {
    let regionSize: UIntNative
    let heapSize: UIntNative
    let exemptionThreshold: Float64
    let heapUtilization: Float64
    let heapGrowth: Float64
    let heapSizeSet: Bool
    let softHeapSize: UIntNative
    let softHeapSizeSet: Bool

    init(regionSize: UIntNative, heapSize: UIntNative, exemptionThreshold: Float64, heapUtilization: Float64,
        heapGrowth: Float64, heapSizeSet: Bool, softHeapSize: UIntNative, softHeapSizeSet: Bool) {
        this.regionSize = regionSize
        this.heapSize = heapSize
        this.exemptionThreshold = exemptionThreshold
        this.heapUtilization = heapUtilization
        this.heapGrowth = heapGrowth
        this.heapSizeSet = heapSizeSet
        this.softHeapSize = softHeapSize
        this.softHeapSizeSet = softHeapSizeSet
    }
}

@C
struct RuntimeGCParamC {
    let gcThreshold: UIntNative
    let garbageThreshold: Float64
    let gcInterval: UInt64
    let backupGCInterval: UInt64
    let concGCThreads: UInt32
    let youngGCThreads: UInt32
    let oldGCThreads: UInt32
    let staticGCThreads: Bool
    let maxTenuringThreshold: UInt32
    let zTenuringThreshold: Int32
    let maxTenuringThresholdSet: Bool
    let zTenuringThresholdSet: Bool

    init(gcThreshold: UIntNative, garbageThreshold: Float64, gcInterval: UInt64,
        backupGCInterval: UInt64, concGCThreads: UInt32, youngGCThreads: UInt32, oldGCThreads: UInt32,
        staticGCThreads: Bool, maxTenuringThreshold: UInt32, zTenuringThreshold: Int32,
        maxTenuringThresholdSet: Bool, zTenuringThresholdSet: Bool) {
        this.gcThreshold = gcThreshold
        this.garbageThreshold = garbageThreshold
        this.gcInterval = gcInterval
        this.backupGCInterval = backupGCInterval
        this.concGCThreads = concGCThreads
        this.youngGCThreads = youngGCThreads
        this.oldGCThreads = oldGCThreads
        this.staticGCThreads = staticGCThreads
        this.maxTenuringThreshold = maxTenuringThreshold
        this.zTenuringThreshold = zTenuringThreshold
        this.maxTenuringThresholdSet = maxTenuringThresholdSet
        this.zTenuringThresholdSet = zTenuringThresholdSet
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
    let coParam: RuntimeConcurrencyParamC

    init(heapParam: RuntimeHeapParamC, gcParam: RuntimeGCParamC, logParam: RuntimeLogParamC,
        coParam: RuntimeConcurrencyParamC) {
        this.heapParam = heapParam
        this.gcParam = gcParam
        this.logParam = logParam
        this.coParam = coParam
    }
}

private type RuntimeInitFunc = CFunc<(CPointer<RuntimeConfigParamC>) -> Int32>
private type RuntimeFiniFunc = CFunc<() -> Int64>

private let CJ_RUNTIME_INIT: String = "InitCJRuntime"
private let CJ_RUNTIME_FINI: String = "FiniCJRuntime"
private let CJ_NEW_TASK_FROM_C: String = "RunCJTask"
private let CJ_RELEASE_HANDLE_FROM_C: String = "ReleaseHandle"
private let CJ_PACKAGE_INIT_BEGIN: String = "CJ_MCC_PackageInitBegin"
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

// InitCJRuntime interprets zero sizes/budgets using its platform defaults.
// CangjieRuntimeApi.cpp config initialization is the default-value contract.
public let REGION_SIZE: UIntNative = 64
public let HEAP_SIZE: UIntNative = 0
public let HEAP_SIZE_SET: Bool = false
public let SOFT_HEAP_SIZE: UIntNative = 0
public let SOFT_HEAP_SIZE_SET: Bool = false
public let EXEMPTION_THRESHOLD: Float64 = 0.8
public let HEAP_UTILIZATION: Float64 = 0.8
public let HEAP_GROWTH: Float64 = 0.15
public let GC_THRESHOLD: UIntNative = 0
public let GARBAGE_THRESHOLD: Float64 = 0.5
public let GC_INTERVAL: UInt64 = 150
public let BACKUP_GC_INTERVAL: UInt64 = 0
// Zero worker budgets and unset thresholds select runtime ergonomics.
public let CONC_GC_THREADS: UInt32 = 0
public let YOUNG_GC_THREADS: UInt32 = 0
public let OLD_GC_THREADS: UInt32 = 0
public let STATIC_GC_THREADS: Bool = false
public let MAX_TENURING_THRESHOLD: UInt32 = 15
public let Z_TENURING_THRESHOLD: Int32 = -1
public let MAX_TENURING_THRESHOLD_SET: Bool = false
public let Z_TENURING_THRESHOLD_SET: Bool = false
public let STACK_SIZE: UIntNative = 0
public let CO_STACK_SIZE: UIntNative = 0
public let PROCESSOR_NUM: UInt32 = 0u32
public let HEAP_INITIAL_SIZE: UIntNative = 64 * 1024

public class RuntimeHandle {
    public var path: String = ""
    public var symbol: String = ""
    public var opened: Bool = false
    public var runtimeManaged: Bool = false
    public var retain: Bool = false
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

private func GetSizeFromEnv(raw: String): Option<UIntNative> {
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
        Int32.parse(numberPart)
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

private func GetHeapSizeFromEnv(envs: ArrayList<(String, String)>): UIntNative {
    if (let Some(raw) <- getRuntimeEnv(envs, CJ_HEAP_SIZE)) {
        if (let Some(size) <- GetSizeFromEnv(raw)) {
            if (size >= MIN_HEAP_SIZE) {
                return size
            }
            Warningln("unsupported cjHeapSize for macro, must >= 4MB, using runtime default size")
            return HEAP_SIZE
        }
        Warningln("unsupported cjHeapSize for macro, using runtime default size")
    }
    return HEAP_SIZE
}

private func GetStackSizeFromEnv(envs: ArrayList<(String, String)>): UIntNative {
    if (let Some(raw) <- getRuntimeEnv(envs, CJ_STACK_SIZE)) {
        if (let Some(size) <- GetSizeFromEnv(raw)) {
            if (size >= MIN_STACK_SIZE && size <= MAX_STACK_SIZE) {
                return size
            }
            Warningln("unsupported cjStackSize for macro, the valid range is [64KB, 1GB], using runtime default size")
            return CO_STACK_SIZE
        }
        Warningln("unsupported cjStackSize for macro, using runtime default size")
    }
    return CO_STACK_SIZE
}

private func makeRuntimeConfig(envs: ArrayList<(String, String)>): RuntimeConfigParamC {
    let heapSize = GetHeapSizeFromEnv(envs)
    // Environment soft values are parsed in bytes by GCArguments before the
    // zArguments.cpp:40-52 origin split; do not round them through the KB API.
    return RuntimeConfigParamC(
        RuntimeHeapParamC(REGION_SIZE, heapSize, EXEMPTION_THRESHOLD, HEAP_UTILIZATION, HEAP_GROWTH,
            getRuntimeEnv(envs, CJ_HEAP_SIZE).isSome() || HEAP_SIZE_SET, SOFT_HEAP_SIZE, SOFT_HEAP_SIZE_SET),
        RuntimeGCParamC(GC_THRESHOLD, GARBAGE_THRESHOLD, GC_INTERVAL, BACKUP_GC_INTERVAL,
            CONC_GC_THREADS, YOUNG_GC_THREADS, OLD_GC_THREADS, STATIC_GC_THREADS,
            MAX_TENURING_THRESHOLD, Z_TENURING_THRESHOLD, MAX_TENURING_THRESHOLD_SET, Z_TENURING_THRESHOLD_SET),
        RuntimeLogParamC(5),
        RuntimeConcurrencyParamC(STACK_SIZE, GetStackSizeFromEnv(envs), PROCESSOR_NUM))
}

@When[os == "Linux" || os == "macOS" || os == "iOS"]
public func OpenSymbolTable(libPath: String, dlopenMode!: Int32 = DLOPEN_MODE): RuntimeHandle {
    var result = RuntimeHandle()
    try (path = unsafe { LibC.mallocCString(libPath) }.asResource()) {
        let realpathRes = unsafe { realpath(path.value, CString(CPointer<UInt8>())) }
        if (realpathRes.isNull()) {
            Errorln("could not get realpath of library: " + libPath)
            return result
        }
        let rawHandle = unsafe { dlopen(realpathRes, dlopenMode) }
        unsafe { free(realpathRes) }
        let handle = RuntimeHandle(libPath, raw: rawHandle)
        if (!handle.opened) {
            Errorln("could not load the dynamic library: " + libPath)
            Errorln("error info is: " + unsafe { dlerror() }.toString())
        }
        result = handle
    } catch (e: Exception) {
        result = RuntimeHandle()
    }
    return result
}

@When[os == "Windows"]
public func OpenSymbolTable(libPath: String): RuntimeHandle {
    var result = RuntimeHandle()
    try (path = unsafe { LibC.mallocCString(libPath) }.asResource()) {
        let handle = RuntimeHandle(libPath, raw: unsafe { LoadLibraryA(path.value) })
        if (!handle.opened) {
            Errorln("could not load the dynamic library: " + libPath)
        }
        result = handle
    } catch (e: Exception) {
        result = RuntimeHandle()
    }
    return result
}

@When[os == "Windows"]
public func OpenSymbolTableSafely(path: String): RuntimeHandle {
    let handle = OpenSymbolTable(path)
    if (handle.opened) {
        SetOpenedLibHandles(handle)
    }
    return handle
}

@When[os == "Linux" || os == "macOS" || os == "iOS"]
public func OpenSymbolTableSafely(path: String): RuntimeHandle {
    let handle = OpenSymbolTable(path, dlopenMode: 0x2 | 0x0)
    if (handle.opened) {
        SetOpenedLibHandles(handle)
    }
    return handle
}

// Load into an existing link map. dlmopen does not publish the SONAME into the
// base namespace, so NEEDED libcangjie-runtime.so binds to the copy already in
// that map (PackageInit.cpp:68-92 only sees files registered there).
@When[os == "Linux"]
private func OpenInLinkMap(libPath: String, lmid: Int64): RuntimeHandle {
    var result = RuntimeHandle()
    try (path = unsafe { LibC.mallocCString(libPath) }.asResource()) {
        let realpathRes = unsafe { realpath(path.value, CString(CPointer<UInt8>())) }
        if (realpathRes.isNull()) {
            return result
        }
        let rawHandle = unsafe { dlmopen(IntNative(lmid), realpathRes, RTLD_NOW_LOCAL) }
        unsafe { free(realpathRes) }
        let handle = RuntimeHandle(libPath, raw: rawHandle)
        if (!handle.opened) {
            Errorln("could not load the dynamic library: " + libPath)
            Errorln("error info is: " + unsafe { dlerror() }.toString())
        }
        result = handle
    } catch (e: Exception) {
        result = RuntimeHandle()
    }
    return result
}

@When[os == "Linux"]
private func NativePathExists(libPath: String): Bool {
    var found = false
    try (path = unsafe { LibC.mallocCString(libPath) }.asResource()) {
        let realpathRes = unsafe { realpath(path.value, CString(CPointer<UInt8>())) }
        if (!realpathRes.isNull()) {
            unsafe { free(realpathRes) }
            found = true
        }
    } catch (e: Exception) {
        found = false
    }
    return found
}

@When[os == "Linux"]
private func ReadLinkMapId(raw: CPointer<Unit>): Option<Int64> {
    if (raw.isNull()) {
        return None
    }
    var result = None<Int64>
    try (slot = LibC.malloc<Int64>().asResource()) {
        if (!slot.value.isNull()) {
            unsafe {
                slot.value.write(0)
                if (dlinfo(raw, RTLD_DI_LMID, slot.value) == 0) {
                    result = Some(slot.value.read())
                }
            }
        }
    } catch (e: Exception) {
        result = None<Int64>
    }
    return result
}

// Sibling cangjie libs share the admission image's directory. Load them into
// that link map before the macro so their SONAME is already satisfied there,
// instead of by the process LD_LIBRARY_PATH.
@When[os == "Linux"]
private func PreloadAdmissionSiblings(runtimeLibPath: String, lmid: Int64): Bool {
    let dir = FileUtil.GetDirPath(runtimeLibPath)
    let names = ["libboundscheck.so", "libcangjie-std-core.so", "libcangjie-std-math.so",
        "libcangjie-std-collection.so", "libcangjie-std-sort.so", "libcangjie-std-ast.so"]
    for (name in names) {
        let full = FileUtil.JoinPath(dir, name)
        if (!NativePathExists(full)) {
            continue
        }
        let opened = OpenInLinkMap(full, lmid)
        if (!opened.opened) {
            return false
        }
        opened.retain = true
    }
    return true
}

@When[os == "Linux"]
private func OpenMacroInNamespace(path: String): Option<RuntimeHandle> {
    if (!RuntimeInit.GetInstance().HasLinkMap()) {
        return None<RuntimeHandle>
    }
    let handle = OpenInLinkMap(path, RuntimeInit.GetInstance().LinkMapId())
    if (handle.opened) {
        handle.retain = true
    }
    return Some(handle)
}

@When[os != "Linux"]
private func OpenMacroInNamespace(path: String): Option<RuntimeHandle> {
    return None<RuntimeHandle>
}

// Cangjie images register runtime metadata. Pair the runtime loader's path
// handle with FindCJSymbol/UnloadCJLibrary, rather than bypassing it with dlclose.
public func OpenMacroLibrary(path: String): RuntimeHandle {
    // The runtime owns one entry per image. Repeated calls into the same macro
    // package reuse that entry rather than acquiring unmatched native references.
    for (opened in openedLibHandles) {
        if (opened.opened && opened.path == path && (opened.runtimeManaged || opened.retain)) {
            return opened
        }
    }
    if (let Some(handle) <- OpenMacroInNamespace(path)) {
        return handle
    }
    let handle = RuntimeHandle(path)
    let load = GetTaskRuntimeMethodPointer("LoadCJLibrary")
    if (load.isNull()) {
        return handle
    }
    try (libraryName = unsafe { LibC.mallocCString(path) }.asResource()) {
        handle.opened = unsafe { CFunc<(CString) -> Int32>(load)(libraryName.value) } == 0
        handle.runtimeManaged = handle.opened
    } catch (e: Exception) {
        handle.opened = false
    }
    return handle
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
    if (!handle.opened || (!handle.runtimeManaged && handle.raw.isNull()) || name.isEmpty()) {
        return CPointer<Unit>()
    }
    var result = CPointer<Unit>()
    try (symbolName = unsafe { LibC.mallocCString(name) }.asResource()) {
        var symbol = CPointer<Unit>()
        if (handle.runtimeManaged) {
            let find = GetTaskRuntimeMethodPointer("FindCJSymbol")
            if (!find.isNull()) {
                try (libraryName = unsafe { LibC.mallocCString(handle.path) }.asResource()) {
                    symbol = unsafe {
                        CFunc<(CString, CString) -> CPointer<Unit>>(find)(libraryName.value, symbolName.value)
                    }
                }
            }
        } else {
            symbol = getNativeSymbol(handle.raw, symbolName.value)
        }
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

// PackageInitBegin consults the image that resolved the call
// (PackageInit.cpp:242-252). LoadCJLibrary must register in that same image,
// and RunCJTask must attach the thread there. Upstream resolves both from the
// single opened handle (InvokeUtilCJNative.cpp:192-194).
private func GetTaskRuntimeMethodPointer(name: String): CPointer<Unit> {
    let runtime = RuntimeInit.GetInstance()
    if (runtime.taskOnOpenedRuntime) {
        if (let Some(opened) <- runtime.GetHandle()) {
            let method = GetMethodPointer(opened, name)
            if (!method.isNull()) {
                return method
            }
        }
    }
    return GetHostRuntimeMethodPointer(name)
}

// The Cangjie host has already initialized its runtime before main. Resolve
// fallback tasks against that mapping, not a second runtime beside the compiler.
@When[os != "Windows"]
private func GetHostRuntimeMethodPointer(name: String): CPointer<Unit> {
    let host = RuntimeHandle("", raw: unsafe { dlopen(CString(CPointer<UInt8>()), 0x1) })
    let method = GetMethodPointer(host, name)
    let _ = CloseSymbolTable(host)
    return method
}

// hostHasAdmission must be sampled before OpenSymbolTable. dlopen(NULL) after a
// RTLD_GLOBAL open sees the pin and would treat it as the process image.
private func AdmissionOnlyInOpenedImage(hostHasAdmission: Bool, opened: RuntimeHandle): Bool {
    if (hostHasAdmission) {
        return false
    }
    return !GetMethodPointer(opened, CJ_PACKAGE_INIT_BEGIN).isNull()
}

@When[os == "Windows"]
private func GetHostRuntimeMethodPointer(name: String): CPointer<Unit> {
    try (moduleName = unsafe { LibC.mallocCString("libcangjie-runtime.dll") }.asResource()) {
        // GetModuleHandle borrows the startup module; do not FreeLibrary it.
        let host = RuntimeHandle("", raw: unsafe { GetModuleHandleA(moduleName.value) })
        return GetMethodPointer(host, name)
    } catch (e: Exception) {
        return CPointer<Unit>()
    }
}

public func CloseSymbolTable(handle: RuntimeHandle): Int64 {
    if (!handle.opened) {
        return 0
    }
    // A live admission image and the libraries mapped into its link namespace
    // stay mapped until process exit. dlclose would run their fini against a
    // still-initialized runtime.
    if (handle.retain) {
        return 0
    }
    var ret: Int64 = 0
    if (handle.runtimeManaged) {
        let unload = GetTaskRuntimeMethodPointer("UnloadCJLibrary")
        if (unload.isNull()) {
            return -1
        }
        try (libraryName = unsafe { LibC.mallocCString(handle.path) }.asResource()) {
            ret = Int64(unsafe { CFunc<(CString) -> Int32>(unload)(libraryName.value) })
        } catch (e: Exception) {
            return -1
        }
    } else if (!handle.raw.isNull()) {
        ret = closeNativeLibrary(handle.raw)
    }
    if (ret != 0) {
        return ret
    }
    handle.opened = false
    handle.raw = CPointer<Unit>()
    handle.symbolRaw = CPointer<Unit>()
    return ret
}

public func PrepareRuntime(handle: RuntimeHandle, initArgs: ArrayList<(String, String)>): Bool {
    let callInit = CallRuntime(handle, CJ_RUNTIME_INIT, initArgs)
    if (callInit != 0) {
        Errorln("macro expansion failed because of runtime initiate failed. ")
        return false
    }
    return true
}

public func FinishRuntime(handle: RuntimeHandle): Unit {
    let fini = RuntimeFiniFunc(GetMethodPointer(handle, CJ_RUNTIME_FINI))
    let finiInit = unsafe { fini() }
    if (finiInit != 0) {
        Errorln("runtime finish failed: ")
        return
    }
}

public func CallRuntime(handle: RuntimeHandle, method: String, envs: ArrayList<(String, String)>): Int64 {
    let methodPtr = GetMethodPointer(handle, method)
    if (methodPtr.isNull()) {
        Errorln("could not find runtime method: " + method)
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
                result = Int64(initFunc(param.value))
            }
        }
    } catch (e: Exception) {
        result = 1
    }
    return result
}

public func FreeNativeBuffer(buffer: CPointer<UInt8>): Unit {
    if (!buffer.isNull()) {
        unsafe { free(CString(buffer)) }
    }
}

public func GetOpenedLibHandles(): ArrayList<RuntimeHandle> {
    return openedLibHandles
}

public func SetOpenedLibHandles(handle: RuntimeHandle): Unit {
    openedLibHandles.add(handle)
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
    public var taskOnOpenedRuntime: Bool = false
    private var hasLinkMap: Bool = false
    private var linkMapId: Int64 = 0

    public init() {}

    private init(_: Bool) {}

    public static func GetInstance(): RuntimeInit {
        return RuntimeInit.instance
    }

    public func HasLinkMap(): Bool {
        return hasLinkMap
    }

    public func LinkMapId(): Int64 {
        return linkMapId
    }

    // Process image has no CJ_MCC_PackageInitBegin. Open that image in a new
    // link map so the macro's MRT_LibraryOnLoad and N2C bind there
    // (Cjstart.S .init_array, PackageInit.cpp:241-252). LoadCJLibrary cannot
    // do this: Loader.cpp:18 dlopens into the base namespace.
    @When[os == "Linux"]
    private func BindAdmissionNamespace(runtimeLibPath: String, initArgs: ArrayList<(String, String)>): Bool {
        let opened = OpenInLinkMap(runtimeLibPath, LM_ID_NEWLM)
        if (!opened.opened) {
            return false
        }
        handle = Some(opened)
        if (GetMethodPointer(opened, CJ_PACKAGE_INIT_BEGIN).isNull()) {
            let _ = CloseSymbolTable(opened)
            handle = None
            return false
        }
        if (!PrepareRuntime(opened, initArgs)) {
            return false
        }
        let mapId = ReadLinkMapId(opened.raw)
        if (let None <- mapId) {
            return false
        }
        let lmid = mapId.getOrThrow()
        if (!PreloadAdmissionSiblings(runtimeLibPath, lmid)) {
            return false
        }
        runtimeMethodFunc = GetMethodPointer(opened, CJ_NEW_TASK_FROM_C)
        runtimeReleaseFunc = GetMethodPointer(opened, CJ_RELEASE_HANDLE_FROM_C)
        if (runtimeMethodFunc.isNull() || runtimeReleaseFunc.isNull()) {
            var errorInfo = CJ_RELEASE_HANDLE_FROM_C
            if (runtimeMethodFunc.isNull()) {
                errorInfo = CJ_NEW_TASK_FROM_C
            }
            Errorln("could not find the create task method: " + errorInfo)
            return false
        }
        opened.retain = true
        hasLinkMap = true
        linkMapId = lmid
        taskOnOpenedRuntime = true
        initRuntime = true
        return true
    }

    @When[os == "Linux"]
    private func MaybeBindAdmissionNamespace(hostHasAdmission: Bool, runtimeLibPath: String,
        initArgs: ArrayList<(String, String)>): Option<Bool> {
        if (hostHasAdmission) {
            return None<Bool>
        }
        return Some(BindAdmissionNamespace(runtimeLibPath, initArgs))
    }

    @When[os != "Linux"]
    private func MaybeBindAdmissionNamespace(hostHasAdmission: Bool, runtimeLibPath: String,
        initArgs: ArrayList<(String, String)>): Option<Bool> {
        return None<Bool>
    }

    public func InitRuntime(runtimeLibPath: String, initArgs!: ArrayList<(String, String)> = ArrayList<(String, String)>()): Bool {
        if (!initRuntime) {
            // Sample the process image before any second runtime is opened.
            let hostHasAdmission = !GetHostRuntimeMethodPointer(CJ_PACKAGE_INIT_BEGIN).isNull()
            if (let Some(bound) <- MaybeBindAdmissionNamespace(hostHasAdmission, runtimeLibPath, initArgs)) {
                return bound
            }
            let opened = OpenSymbolTable(runtimeLibPath)
            if (!opened.opened) {
                return false
            }
            handle = Some(opened)
            if (AdmissionOnlyInOpenedImage(hostHasAdmission, opened)) {
                // Process image does not export CJ_MCC_PackageInitBegin; the opened
                // image does. Generated code binds the admission entry there
                // (InvokeUtil.h:80 RTLD_GLOBAL). That image must be the one
                // InitCJRuntime / RunCJTask / LoadCJLibrary use
                // (InvokeUtilCJNative.cpp:171-194). The process host stays for the
                // compiler itself; it is not the admission image.
                if (!PrepareRuntime(opened, initArgs)) {
                    return false
                }
                runtimeMethodFunc = GetMethodPointer(opened, CJ_NEW_TASK_FROM_C)
                runtimeReleaseFunc = GetMethodPointer(opened, CJ_RELEASE_HANDLE_FROM_C)
                if (runtimeMethodFunc.isNull() || runtimeReleaseFunc.isNull()) {
                    var errorInfo = CJ_RELEASE_HANDLE_FROM_C
                    if (runtimeMethodFunc.isNull()) {
                        errorInfo = CJ_NEW_TASK_FROM_C
                    }
                    Errorln("could not find the create task method: " + errorInfo)
                    return false
                }
                taskOnOpenedRuntime = true
                initRuntime = true
            } else {
                // Same image as the process host, or the host already exports the
                // admission entry. Do not init a second copy
                // (CangjieRuntimeApi.cpp:181-184) and do not leave a different
                // image in the global scope.
                let _ = CloseSymbolTable(opened)
                handle = None
                runtimeMethodFunc = GetHostRuntimeMethodPointer(CJ_NEW_TASK_FROM_C)
                runtimeReleaseFunc = GetHostRuntimeMethodPointer(CJ_RELEASE_HANDLE_FROM_C)
                if (runtimeMethodFunc.isNull() || runtimeReleaseFunc.isNull()) {
                    var errorInfo = CJ_RELEASE_HANDLE_FROM_C
                    if (runtimeMethodFunc.isNull()) {
                        errorInfo = CJ_NEW_TASK_FROM_C
                    }
                    Errorln("could not find the create task method: " + errorInfo)
                    return false
                }
                taskOnOpenedRuntime = false
                initRuntime = true
            }
        }
        return true
    }

    public func CloseRuntime(): Unit {
        if (let Some(opened) <- handle) {
            if (initRuntime) {
                initRuntime = false
            }
            if (!taskOnOpenedRuntime) {
                @When[backend == "cjnative" && env != "ohos"]
                let _ = CloseSymbolTable(opened)
            }
        }
        handle = None
        runtimeMethodFunc = CPointer<Unit>()
        runtimeReleaseFunc = CPointer<Unit>()
        taskOnOpenedRuntime = false
        hasLinkMap = false
        linkMapId = 0
        // C++ InvokeUtil.cpp:113-129 finishes its runtime before unloading images.
        // This Cangjie host still needs its runtime and registered image metadata.
        // Keep macro images alive until the host process shuts down naturally.
    }

    public func GetHandle(): Option<RuntimeHandle> {
        return handle
    }

    private func CloseMacroDynamicLibrary(): Unit {
        // Reverse load order: dependencies remain available until their users close.
        while (!openedLibHandles.isEmpty()) {
            let opened = openedLibHandles[openedLibHandles.size - 1]
            if (CloseSymbolTable(opened) != 0) {
                Errorln("close macro related dynamic library failed: ")
                return
            }
            openedLibHandles.remove(at: openedLibHandles.size - 1)
        }
    }
}

public class MacroProcMsger {
    private static let instance: MacroProcMsger = MacroProcMsger(true)
    public let macroSrvRun: AtomicBool = AtomicBool(false)
    public let pipeError: AtomicBool = AtomicBool(false)
    public let mutex: Mutex = Mutex()
    @When[os == "Windows"]
    public var hParentRead: CPointer<Unit> = CPointer<Unit>()
    @When[os == "Windows"]
    public var hParentWrite: CPointer<Unit> = CPointer<Unit>()
    @When[os == "Windows"]
    public var hChildRead: CPointer<Unit> = CPointer<Unit>()
    @When[os == "Windows"]
    public var hChildWrite: CPointer<Unit> = CPointer<Unit>()
    @When[os == "Windows"]
    public var hProcess: CPointer<Unit> = CPointer<Unit>()
    @When[os == "Windows"]
    public var hThread: CPointer<Unit> = CPointer<Unit>()
    @When[os != "Windows"]
    public let pipefdP2C: CPointer<Int32> = LibC.malloc<Int32>(count: 2)
    @When[os != "Windows"]
    public let pipefdC2P: CPointer<Int32> = LibC.malloc<Int32>(count: 2)
    private let msgSliceLen: Int64 = 4096

    @When[os == "Windows"]
    public init() {}

    @When[os != "Windows"]
    public init() {
        unsafe {
            pipefdP2C.write(-1)
            (pipefdP2C + 1).write(-1)
            pipefdC2P.write(-1)
            (pipefdC2P + 1).write(-1)
        }
    }

    @When[os == "Windows"]
    private init(_: Bool) {}

    @When[os != "Windows"]
    private init(_: Bool) {
        unsafe {
            pipefdP2C.write(-1)
            (pipefdP2C + 1).write(-1)
            pipefdC2P.write(-1)
            (pipefdC2P + 1).write(-1)
        }
    }

    public static func GetInstance(): MacroProcMsger {
        return MacroProcMsger.instance
    }

    @When[os == "Windows"]
    public func SetSrvPipeHandle(hRead: CPointer<Unit>, hWrite: CPointer<Unit>): Unit {
        hChildRead = hRead
        hChildWrite = hWrite
    }

    @When[os != "Windows"]
    public func SetSrvPipeHandle(hRead: Int32, hWrite: Int32): Unit {
        unsafe {
            pipefdP2C.write(hRead)
            (pipefdC2P + 1).write(hWrite)
        }
    }

    public func CloseMacroSrv(): Unit {
        if (macroSrvRun.load()) {
            let msg = ArrayList<UInt8>()
            MacroEvalMsgSerializer().SerializeExitMsg(msg)
            if (SendMsgToSrv(msg)) {
                let start = MonoTime.now()
                var elapsedSeconds: Int64 = 0
                let waitTime: Int64 = 5
                while (macroSrvRun.load() && elapsedSeconds < waitTime) {
                    elapsedSeconds = (MonoTime.now() - start).toSeconds()
                }
                if (elapsedSeconds >= waitTime) {
                    Errorln("wait macro srv exit time out 5")
                }
            } else {
                Errorln("error Send Exit Task")
            }
        }
        CloseClientResource()
    }

    public func SendMsgToSrv(msg: ArrayList<UInt8>): Bool {
        if (msg.isEmpty()) {
            return false
        }
        if (pipeError.load()) {
            return false
        }
        let sumSize = UIntNative(msg.size)
        let rest = msg.size % msgSliceLen
        let msgNum = if (rest == 0) { msg.size / msgSliceLen } else { msg.size / msgSliceLen + 1 }
        let lastSize = if (rest == 0) { msgSliceLen } else { rest }
        try (sizePtr = LibC.malloc<UIntNative>().asResource()) {
            unsafe { sizePtr.value.write(sumSize) }
            if (!WriteToSrvPipe(CPointer<UInt8>(sizePtr.value), UIntNative(sizeOf<UIntNative>()))) {
                try (message = unsafe { LibC.mallocCString("WriteToSrvPipe") }.asResource()) {
                    unsafe { perror(message.value) }
                }
                pipeError.store(true)
                return false
            }
        }
        try (msgPtr = LibC.malloc<UInt8>(count: msg.size).asResource()) {
            var idx: Int64 = 0
            unsafe {
                while (idx < msg.size) {
                    (msgPtr.value + idx).write(msg[idx])
                    idx++
                }
            }
            var slice: Int64 = 0
            while (slice < msgNum) {
                let curNum = if (slice == msgNum - 1) { lastSize } else { msgSliceLen }
                let slicePtr = unsafe { msgPtr.value + slice * msgSliceLen }
                if (!WriteToSrvPipe(slicePtr, UIntNative(curNum))) {
                    try (message = unsafe { LibC.mallocCString("WriteToSrvPipe") }.asResource()) {
                        unsafe { perror(message.value) }
                    }
                    pipeError.store(true)
                    return false
                }
                slice++
            }
        }
        return true
    }

    public func ReadMsgFromSrv(msg: ArrayList<UInt8>): Bool {
        msg.clear()
        if (pipeError.load()) {
            return false
        }
        var msgSize: UIntNative = 0
        try (sizePtr = LibC.malloc<UIntNative>().asResource()) {
            if (!ReadFromSrvPipe(CPointer<UInt8>(sizePtr.value), UIntNative(sizeOf<UIntNative>()))) {
                try (message = unsafe { LibC.mallocCString("ReadFromSrvPipe") }.asResource()) {
                    unsafe { perror(message.value) }
                }
                pipeError.store(true)
                return false
            }
            msgSize = unsafe { sizePtr.value.read() }
        }
        if (msgSize == 0) {
            try (message = unsafe { LibC.mallocCString("ReadFromSrvPipe size err") }.asResource()) {
                unsafe { perror(message.value) }
            }
            pipeError.store(true)
            return false
        }
        let size = Int64(msgSize)
        let rest = size % msgSliceLen
        let msgNum = if (rest == 0) { size / msgSliceLen } else { size / msgSliceLen + 1 }
        let lastSize = if (rest == 0) { msgSliceLen } else { rest }
        try (msgPtr = LibC.malloc<UInt8>(count: size).asResource()) {
            var slice: Int64 = 0
            while (slice < msgNum) {
                let curNum = if (slice == msgNum - 1) { lastSize } else { msgSliceLen }
                let slicePtr = unsafe { msgPtr.value + slice * msgSliceLen }
                if (!ReadFromSrvPipe(slicePtr, UIntNative(curNum))) {
                    try (message = unsafe { LibC.mallocCString("ReadFromSrvPipe") }.asResource()) {
                        unsafe { perror(message.value) }
                    }
                    pipeError.store(true)
                    return false
                }
                slice++
            }
            var idx: Int64 = 0
            unsafe {
                while (idx < size) {
                    msg.add((msgPtr.value + idx).read())
                    idx++
                }
            }
        }
        return true
    }

    @When[os == "Windows"]
    public func ReadAllMsgFromSrv(msgVec: ArrayList<ArrayList<UInt8>>): Bool {
        msgVec.clear()
        let msg = ArrayList<UInt8>()
        var errFlag = true
        while (ReadMsgFromSrv(msg)) {
            let value = ArrayList<UInt8>()
            for (byte in msg) {
                value.add(byte)
            }
            msgVec.add(value)
            try (totalBytesAvail = LibC.malloc<UInt32>().asResource()) {
                if (unsafe { PeekNamedPipe(hParentRead, CPointer<UInt8>(), 0u32, CPointer<UInt32>(),
                    totalBytesAvail.value, CPointer<UInt32>()) } == 0) {
                    Errorln("PeekNamedPipe failed with error " + unsafe { GetLastError() }.toString())
                    return false
                }
                if (unsafe { totalBytesAvail.value.read() } == 0u32) {
                    return true
                }
            }
        }
        return !errFlag
    }

    @When[os != "Windows"]
    public func ReadAllMsgFromSrv(msgVec: ArrayList<ArrayList<UInt8>>): Bool {
        msgVec.clear()
        let msg = ArrayList<UInt8>()
        var errFlag = true
        while (ReadMsgFromSrv(msg)) {
            let value = ArrayList<UInt8>()
            for (byte in msg) {
                value.add(byte)
            }
            msgVec.add(value)
            try (readset = LibC.malloc<FdSet>().asResource(), timeout = LibC.malloc<Timeval>().asResource()) {
                FD_ZERO(readset.value)
                let readFd = unsafe { pipefdC2P.read() }
                FD_SET(readFd, readset.value)
                unsafe { timeout.value.write(Timeval(0, 0)) }
                let ret = unsafe { select(readFd + 1, readset.value, CPointer<FdSet>(), CPointer<FdSet>(),
                    timeout.value) }
                if (ret == -1) {
                    try (message = unsafe { LibC.mallocCString("srv proc select pipe fail, stop read.") }.asResource()) {
                        unsafe { perror(message.value) }
                    }
                    return false
                } else if (ret == 0) {
                    return true
                } else if (FD_ISSET(readFd, readset.value)) {
                    continue
                } else {
                    try (message = unsafe { LibC.mallocCString("srv proc FD_ISSET fail, stop read.") }.asResource()) {
                        unsafe { perror(message.value) }
                    }
                    return false
                }
            }
        }
        return !errFlag
    }

    @When[os == "Windows"]
    public func CloseClientResource(): Unit {
        if (!hParentRead.isNull()) {
            if (unsafe { CloseHandle(hParentRead) } != 0) {
                hParentRead = CPointer<Unit>()
            } else {
                Errorln("CloseHandle hParentRead error")
            }
        }
        if (!hParentWrite.isNull()) {
            if (unsafe { CloseHandle(hParentWrite) } != 0) {
                hParentWrite = CPointer<Unit>()
            } else {
                Errorln("CloseHandle hParentWrite error")
            }
        }
        if (!hProcess.isNull()) {
            if (unsafe { CloseHandle(hProcess) } != 0) {
                hProcess = CPointer<Unit>()
            } else {
                Errorln("CloseHandle hProcess error")
            }
        }
        if (!hThread.isNull()) {
            if (unsafe { CloseHandle(hThread) } != 0) {
                hThread = CPointer<Unit>()
            } else {
                Errorln("CloseHandle hThread error")
            }
        }
    }

    @When[os != "Windows"]
    public func CloseClientResource(): Unit {
        unsafe {
            if ((pipefdP2C + 1).read() != -1) {
                let _ = close((pipefdP2C + 1).read())
                (pipefdP2C + 1).write(-1)
            }
            if (pipefdC2P.read() != -1) {
                let _ = close(pipefdC2P.read())
                pipefdC2P.write(-1)
            }
        }
    }

    public func SendMsgToClient(msg: ArrayList<UInt8>): Bool {
        if (msg.isEmpty()) {
            return false
        }
        let sumSize = UIntNative(msg.size)
        let rest = msg.size % msgSliceLen
        let msgNum = if (rest == 0) { msg.size / msgSliceLen } else { msg.size / msgSliceLen + 1 }
        let lastSize = if (rest == 0) { msgSliceLen } else { rest }
        try (sizePtr = LibC.malloc<UIntNative>().asResource()) {
            unsafe { sizePtr.value.write(sumSize) }
            if (!WriteToClientPipe(CPointer<UInt8>(sizePtr.value), UIntNative(sizeOf<UIntNative>()))) {
                try (message = unsafe { LibC.mallocCString("WriteToClientPipe") }.asResource()) {
                    unsafe { perror(message.value) }
                }
                return false
            }
        }
        try (msgPtr = LibC.malloc<UInt8>(count: msg.size).asResource()) {
            var idx: Int64 = 0
            unsafe {
                while (idx < msg.size) {
                    (msgPtr.value + idx).write(msg[idx])
                    idx++
                }
            }
            var slice: Int64 = 0
            while (slice < msgNum) {
                let curNum = if (slice == msgNum - 1) { lastSize } else { msgSliceLen }
                let slicePtr = unsafe { msgPtr.value + slice * msgSliceLen }
                if (!WriteToClientPipe(slicePtr, UIntNative(curNum))) {
                    try (message = unsafe { LibC.mallocCString("WriteToClientPipe") }.asResource()) {
                        unsafe { perror(message.value) }
                    }
                    return false
                }
                slice++
            }
        }
        return true
    }

    public func ReadMsgFromClient(msg: ArrayList<UInt8>): Bool {
        msg.clear()
        var msgSize: UIntNative = 0
        try (sizePtr = LibC.malloc<UIntNative>().asResource()) {
            if (!ReadFromClientPipe(CPointer<UInt8>(sizePtr.value), UIntNative(sizeOf<UIntNative>()))) {
                try (message = unsafe { LibC.mallocCString("ReadFromClientPipe") }.asResource()) {
                    unsafe { perror(message.value) }
                }
                return false
            }
            msgSize = unsafe { sizePtr.value.read() }
        }
        if (msgSize == 0) {
            Errorln("Msg size error, size: 0")
            return false
        }
        let size = Int64(msgSize)
        let rest = size % msgSliceLen
        let msgNum = if (rest == 0) { size / msgSliceLen } else { size / msgSliceLen + 1 }
        let lastSize = if (rest == 0) { msgSliceLen } else { rest }
        try (msgPtr = LibC.malloc<UInt8>(count: size).asResource()) {
            var slice: Int64 = 0
            while (slice < msgNum) {
                let curNum = if (slice == msgNum - 1) { lastSize } else { msgSliceLen }
                let slicePtr = unsafe { msgPtr.value + slice * msgSliceLen }
                if (!ReadFromClientPipe(slicePtr, UIntNative(curNum))) {
                    try (message = unsafe { LibC.mallocCString("ReadFromClientPipe") }.asResource()) {
                        unsafe { perror(message.value) }
                    }
                    return false
                }
                slice++
            }
            var idx: Int64 = 0
            unsafe {
                while (idx < size) {
                    msg.add((msgPtr.value + idx).read())
                    idx++
                }
            }
        }
        return true
    }

    @When[os == "Windows"]
    private func WriteToSrvPipe(buf: CPointer<UInt8>, size: UIntNative): Bool {
        return unsafe { WriteFile(hParentWrite, buf, UInt32(size), CPointer<UInt32>(), CPointer<Unit>()) != 0 }
    }

    @When[os != "Windows"]
    private func WriteToSrvPipe(buf: CPointer<UInt8>, size: UIntNative): Bool {
        var writeBuf = buf
        var writeSize = size
        var res = unsafe { write((pipefdP2C + 1).read(), writeBuf, writeSize) }
        while (res >= 0 && res < IntNative(writeSize)) {
            writeSize -= UIntNative(res)
            writeBuf = unsafe { writeBuf + Int64(res) }
            res = unsafe { write((pipefdP2C + 1).read(), writeBuf, writeSize) }
        }
        return res >= 0
    }

    @When[os == "Windows"]
    private func ReadFromSrvPipe(buf: CPointer<UInt8>, size: UIntNative): Bool {
        return unsafe { ReadFile(hParentRead, buf, UInt32(size), CPointer<UInt32>(), CPointer<Unit>()) != 0 }
    }

    @When[os != "Windows"]
    private func ReadFromSrvPipe(buf: CPointer<UInt8>, size: UIntNative): Bool {
        var readBuf = buf
        var readSize = size
        var res = unsafe { read(pipefdC2P.read(), readBuf, readSize) }
        while (res > 0 && res < IntNative(readSize)) {
            readSize -= UIntNative(res)
            readBuf = unsafe { readBuf + Int64(res) }
            res = unsafe { read(pipefdC2P.read(), readBuf, readSize) }
        }
        return res > 0
    }

    @When[os == "Windows"]
    private func WriteToClientPipe(buf: CPointer<UInt8>, size: UIntNative): Bool {
        return unsafe { WriteFile(hChildWrite, buf, UInt32(size), CPointer<UInt32>(), CPointer<Unit>()) != 0 }
    }

    @When[os != "Windows"]
    private func WriteToClientPipe(buf: CPointer<UInt8>, size: UIntNative): Bool {
        var writeBuf = buf
        var writeSize = size
        var res = unsafe { write((pipefdC2P + 1).read(), writeBuf, writeSize) }
        while (res >= 0 && res < IntNative(writeSize)) {
            writeSize -= UIntNative(res)
            writeBuf = unsafe { writeBuf + Int64(res) }
            res = unsafe { write((pipefdC2P + 1).read(), writeBuf, writeSize) }
        }
        return res >= 0
    }

    @When[os == "Windows"]
    private func ReadFromClientPipe(buf: CPointer<UInt8>, size: UIntNative): Bool {
        return unsafe { ReadFile(hChildRead, buf, UInt32(size), CPointer<UInt32>(), CPointer<Unit>()) != 0 }
    }

    @When[os != "Windows"]
    private func ReadFromClientPipe(buf: CPointer<UInt8>, size: UIntNative): Bool {
        var readBuf = buf
        var readSize = size
        var res = unsafe { read(pipefdP2C.read(), readBuf, readSize) }
        while (res > 0 && res < IntNative(readSize)) {
            readSize -= UIntNative(res)
            readBuf = unsafe { readBuf + Int64(res) }
            res = unsafe { read(pipefdP2C.read(), readBuf, readSize) }
        }
        return res > 0
    }

}
