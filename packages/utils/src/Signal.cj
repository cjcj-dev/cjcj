package cjcj::utils

import std.runtime.*

@When[os != "Windows"]
public let SIGNAL_MSG_PART_ONE: String = "Interrupt signal ("

@When[os == "Windows"]
public let SIGNAL_MSG_PART_ONE: String = "Windows unexpected exception code ("

public let SIGNAL_MSG_PART_TWO: String = ") received."

@When[os == "Windows"]
private let SIGABRT_WINDOWS: Int32 = 6

@When[os == "Windows"]
private let SIGFPE_WINDOWS: Int32 = 8

@When[os == "Windows"]
private let SIGILL_WINDOWS: Int32 = 4

@When[os == "Windows"]
private let SIGSEGV_WINDOWS: Int32 = 11

@When[os == "Windows"]
private type WindowsSignalHandler = CFunc<(Int32) -> Unit>

@When[os != "Windows"]
foreign {
    func _exit(status: Int32): Unit
    func CJCJ_EnsureAltSignalStack(): Int32
}

@When[os == "Windows"]
foreign {
    func _exit(status: Int32): Unit
    func signal(sig: Int32, handler: WindowsSignalHandler): WindowsSignalHandler
}

@When[os == "Windows"]
private func windowsSignalHandler(signum: Int32): Unit {
    threadDelaySynchronizer()
    writeICEMessage(Int64(signum))
    ICE.RemoveTempFileSignalSafe()
    unsafe {
        _exit(signum + 128)
    }
}

@When[os == "Windows"]
private let windowsSignalHandlerC: WindowsSignalHandler = { signum: Int32 =>
    windowsSignalHandler(signum)
}

@When[os != "Windows"]
private func crashSignalHandler(signum: Int32): Bool {
    threadDelaySynchronizer()
    writeICEMessage(Int64(signum))
    ICE.RemoveTempFileSignalSafe()
    unsafe {
        _exit(signum + 128)
    }
    return true
}

@When[os != "Windows"]
public func RegisterCrashSignalHandler(): Unit {
    let signals = [
        Signal(6, "abort"),
        Signal(7, "bus error"),
        Signal(8, "floating point exception"),
        Signal(4, "illegal instruction"),
        Signal(11, "segmentation fault"),
        Signal(5, "trace/breakpoint trap")
    ]
    for (sig in signals) {
        try {
            registerSignalHandler(sig, crashSignalHandler)
        } catch (e: Exception) {
            ()
        }
    }
}

@When[os == "Windows"]
public func RegisterCrashSignalHandler(): Unit {
    unsafe {
        let _ = signal(SIGABRT_WINDOWS, windowsSignalHandlerC)
        let _ = signal(SIGFPE_WINDOWS, windowsSignalHandlerC)
        let _ = signal(SIGILL_WINDOWS, windowsSignalHandlerC)
        let _ = signal(SIGSEGV_WINDOWS, windowsSignalHandlerC)
    }
}

@When[os != "Windows"]
public func CreateAltSignalStack(): Unit {
    // The native helper owns query/install and pthread-exit cleanup in one
    // C2N invocation; Cangjie tasks can migrate between native threads.
    let error = unsafe { CJCJ_EnsureAltSignalStack() }
    if (error != 0) {
        InternalError("Failed to create a backup stack for the thread (native error ${error}).")
    }
}

@When[os == "Windows"]
public func CreateAltSignalStack(): Unit {
    ()
}
