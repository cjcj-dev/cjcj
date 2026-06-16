package cangjie_compiler::utils

import std.runtime.*

@When[os != "Windows"]
public let SIGNAL_MSG_PART_ONE: String = "Interrupt signal ("

@When[os == "Windows"]
public let SIGNAL_MSG_PART_ONE: String = "Windows unexpected exception code ("

public let SIGNAL_MSG_PART_TWO: String = ") received."

private let SIGNAL_STACK_SIZE: Int64 = 8192

@When[os != "Windows"]
private let SS_ONSTACK: Int32 = 1

@When[os == "Windows"]
private let EXCEPTION_EXECUTE_HANDLER: Int32 = 1

@When[os == "Windows"]
private let TRUE: Int32 = 1

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

@When[os == "Windows"]
private type WindowsConsoleHandler = CFunc<(UInt32) -> Bool>

@When[os == "Windows"]
@C
struct WindowsExceptionRecord {
    let exceptionCode: UInt32

    init(exceptionCode: UInt32) {
        this.exceptionCode = exceptionCode
    }
}

@When[os == "Windows"]
@C
struct WindowsExceptionPointers {
    let exceptionRecord: CPointer<WindowsExceptionRecord>
    let contextRecord: CPointer<Unit>

    init(exceptionRecord: CPointer<WindowsExceptionRecord>, contextRecord: CPointer<Unit>) {
        this.exceptionRecord = exceptionRecord
        this.contextRecord = contextRecord
    }
}

@When[os == "Windows"]
private type WindowsExceptionHandler = CFunc<(CPointer<WindowsExceptionPointers>) -> Int32>

@When[os != "Windows"]
@C
struct SignalStack {
    let ss_sp: CPointer<Unit>
    let ss_flags: Int32
    let ss_size: UIntNative

    init(sp: CPointer<Unit>, flags: Int32, size: UIntNative) {
        ss_sp = sp
        ss_flags = flags
        ss_size = size
    }
}

@When[os != "Windows"]
foreign {
    func _exit(status: Int32): Unit
    func sigaltstack(stack: CPointer<SignalStack>, oldStack: CPointer<SignalStack>): Int32
}

@When[os == "Windows"]
foreign {
    func _exit(status: Int32): Unit
    func signal(sig: Int32, handler: WindowsSignalHandler): WindowsSignalHandler
    func SetConsoleCtrlHandler(handler: WindowsConsoleHandler, add: Int32): Int32
    func SetUnhandledExceptionFilter(handler: WindowsExceptionHandler): CPointer<Unit>
}

@When[os != "Windows"]
private let altStackMemory = LibC.malloc<UInt8>(count: SIGNAL_STACK_SIZE)

@When[os != "Windows"]
private let altStackRecord = LibC.malloc<SignalStack>(count: 1)

@When[os != "Windows"]
private let oldAltStackRecord = LibC.malloc<SignalStack>(count: 1)

@When[os != "Windows"]
private var altStackInstalled = false

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
private func windowsConsoleCtrlHandler(ctrlType: UInt32): Bool {
    let _ = ctrlType
    ICE.RemoveTempFile()
    return false
}

@When[os == "Windows"]
private func windowsUnhandledExceptionHandler(ep: CPointer<WindowsExceptionPointers>): Int32 {
    threadDelaySynchronizer()
    var exitCode = EXCEPTION_EXECUTE_HANDLER
    unsafe {
        if (!ep.isNull()) {
            let exceptionPointers = ep.read()
            if (!exceptionPointers.exceptionRecord.isNull()) {
                exitCode = Int32(exceptionPointers.exceptionRecord.read().exceptionCode)
            }
        }
    }
    writeICEMessage(Int64(exitCode))
    ICE.RemoveTempFile()
    return exitCode
}

@When[os == "Windows"]
private let windowsSignalHandlerC: WindowsSignalHandler = { signum: Int32 =>
    windowsSignalHandler(signum)
}

@When[os == "Windows"]
private let windowsConsoleCtrlHandlerC: WindowsConsoleHandler = { ctrlType: UInt32 =>
    windowsConsoleCtrlHandler(ctrlType)
}

@When[os == "Windows"]
private let windowsUnhandledExceptionHandlerC: WindowsExceptionHandler = {
    ep: CPointer<WindowsExceptionPointers> => windowsUnhandledExceptionHandler(ep)
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
private func ctrlCSignalHandler(signum: Int32): Bool {
    ICE.RemoveTempFile()
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
        let _ = SetUnhandledExceptionFilter(windowsUnhandledExceptionHandlerC)
        let _ = signal(SIGABRT_WINDOWS, windowsSignalHandlerC)
        let _ = signal(SIGFPE_WINDOWS, windowsSignalHandlerC)
        let _ = signal(SIGILL_WINDOWS, windowsSignalHandlerC)
        let _ = signal(SIGSEGV_WINDOWS, windowsSignalHandlerC)
    }
}

@When[os != "Windows"]
public func RegisterCrtlCSignalHandler(): Unit {
    try {
        registerSignalHandler(Signal.SIGINT, ctrlCSignalHandler)
    } catch (e: Exception) {
        ()
    }
}

@When[os == "Windows"]
public func RegisterCrtlCSignalHandler(): Unit {
    unsafe {
        let _ = SetConsoleCtrlHandler(windowsConsoleCtrlHandlerC, TRUE)
    }
}

@When[os != "Windows"]
public func CreateAltSignalStack(): Unit {
    if (altStackInstalled) {
        return
    }
    if (altStackMemory.isNull() || altStackRecord.isNull() || oldAltStackRecord.isNull()) {
        InternalError("Failed to create a backup stack for the thread.")
        return
    }
    unsafe {
        if (sigaltstack(CPointer<SignalStack>(), oldAltStackRecord) != 0) {
            return
        }
        let oldStack = oldAltStackRecord.read()
        if ((oldStack.ss_flags & SS_ONSTACK) != 0 ||
            (!oldStack.ss_sp.isNull() && oldStack.ss_size >= UIntNative(SIGNAL_STACK_SIZE))) {
            altStackInstalled = true
            return
        }
        altStackRecord.write(SignalStack(CPointer<Unit>(altStackMemory), 0, UIntNative(SIGNAL_STACK_SIZE)))
        if (sigaltstack(altStackRecord, oldAltStackRecord) != 0) {
            InternalError("Failed to create a backup stack for the thread.")
            return
        }
    }
    altStackInstalled = true
}

@When[os == "Windows"]
public func CreateAltSignalStack(): Unit {
    ()
}
