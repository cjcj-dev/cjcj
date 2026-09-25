package cjcj::utils

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
private let SIGABRT_WINDOWS: Int32 = 6

@When[os == "Windows"]
private let SIGFPE_WINDOWS: Int32 = 8

@When[os == "Windows"]
private let SIGILL_WINDOWS: Int32 = 4

@When[os == "Windows"]
private let SIGSEGV_WINDOWS: Int32 = 11

@When[os == "Windows"]
private type WindowsSignalHandler = CFunc<(Int32) -> Unit>

// Apple XNU bsd/sys/_types/_sigaltstack.h:42-47: ss_sp, ss_size, ss_flags.
@When[os == "macOS" || os == "iOS"]
@C
struct SignalStack {
    let ss_sp: CPointer<Unit>
    let ss_size: UIntNative
    let ss_flags: Int32

    init(sp: CPointer<Unit>, flags: Int32, size: UIntNative) {
        ss_sp = sp
        ss_size = size
        ss_flags = flags
    }
}

// glibc sysdeps/unix/sysv/linux/bits/types/stack_t.h:25-31: ss_sp, ss_flags, ss_size.
@When[os != "Windows" && os != "macOS" && os != "iOS"]
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
}

@When[os != "Windows"]
private let altStackMemory = LibC.malloc<UInt8>(count: SIGNAL_STACK_SIZE)

@When[os != "Windows"]
private let altStackRecord = LibC.malloc<SignalStack>(count: 1)

@When[os != "Windows"]
private let oldAltStackRecord = LibC.malloc<SignalStack>(count: 1)

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
            return
        }
        altStackRecord.write(SignalStack(CPointer<Unit>(altStackMemory), 0, UIntNative(SIGNAL_STACK_SIZE)))
        if (sigaltstack(altStackRecord, oldAltStackRecord) != 0) {
            InternalError("Failed to create a backup stack for the thread.")
            return
        }
    }
}

@When[os == "Windows"]
public func CreateAltSignalStack(): Unit {
    ()
}
