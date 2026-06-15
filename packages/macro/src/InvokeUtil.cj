package cangjie_compiler::macro_pkg

import std.collection.*

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

    public init() {}

    public init(path: String) {
        this.path = path
        opened = true
    }
}

private let openedLibHandles: ArrayList<RuntimeHandle> = ArrayList<RuntimeHandle>()

public func OpenSymbolTable(libPath: String): RuntimeHandle {
    // TODO(selfhost:Macro): bind dlopen/LoadLibrary through C FFI and preserve native error reporting.
    let handle = RuntimeHandle(libPath)
    openedLibHandles.add(handle)
    return handle
}

public func GetMethod(handle: RuntimeHandle, name: String): Option<String> {
    if (!handle.opened || name.isEmpty()) {
        return None
    }
    return Some(name)
}

public func CloseSymbolTable(handle: RuntimeHandle): Int64 {
    handle.opened = false
    return 0
}

public func PrepareRuntime(handle: RuntimeHandle, initArgs: ArrayList<(String, String)>): Bool {
    let _ = initArgs
    return handle.opened
}

public func FinishRuntime(handle: RuntimeHandle): Unit {
    let _ = handle
}

public func CallRuntime(handle: RuntimeHandle, method: String, envs: ArrayList<(String, String)>): Int64 {
    let _ = envs
    if (!handle.opened || method.isEmpty()) {
        return 1
    }
    return 0
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
    public var runtimeMethodFunc: String = ""
    public var runtimeReleaseFunc: String = ""

    public init() {}

    private init(_: Bool) {}

    public static func GetInstance(): RuntimeInit {
        return RuntimeInit.instance
    }

    public func InitRuntime(runtimeLibPath: String, initArgs!: ArrayList<(String, String)> = ArrayList<(String, String)>()): Bool {
        if (!initRuntime) {
            let opened = OpenSymbolTable(runtimeLibPath)
            if (!PrepareRuntime(opened, initArgs)) {
                return false
            }
            handle = Some(opened)
            runtimeMethodFunc = "RunCJTask"
            runtimeReleaseFunc = "ReleaseHandle"
            initRuntime = true
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
