package cangjie_compiler::utils

import std.runtime.*
import std.sync.AtomicBool

public let SIGNAL_MSG_PART_ONE: String = "Interrupt signal ("
public let SIGNAL_MSG_PART_TWO: String = ") received."

private let SIGNAL_STACK_SIZE: Int64 = 8192
private let processingSignalOrException = AtomicBool(false)

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

@When[os != "Windows"]
private let altStackMemory = LibC.malloc<UInt8>(count: SIGNAL_STACK_SIZE)

@When[os != "Windows"]
private let altStackRecord = LibC.malloc<SignalStack>(count: 1)

@When[os != "Windows"]
private var altStackInstalled = false

private func writeICEMessage(errorCode: Int64): Unit {
    ICE.PrintVersionFromError()
    eprintln(ICE.MSG_PART_ONE + SIGNAL_MSG_PART_ONE + errorCode.toString() + SIGNAL_MSG_PART_TWO +
        ICE.MSG_PART_TWO + ICE.GetTriggerPoint().toString())
}

private func threadDelaySynchronizer(): Unit {
    if (processingSignalOrException.swap(true)) {
        var count: Int64 = 100000
        while (count > 0) {
            count--
        }
    }
}

@When[os != "Windows"]
private func crashSignalHandler(signum: Int32): Bool {
    threadDelaySynchronizer()
    writeICEMessage(Int64(signum))
    ICE.RemoveTempFile()
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
    ()
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
    ()
}

@When[os != "Windows"]
public func CreateAltSignalStack(): Unit {
    if (altStackInstalled) {
        return
    }
    if (altStackMemory.isNull() || altStackRecord.isNull()) {
        InternalError("Failed to create a backup stack for the thread.")
        return
    }
    unsafe {
        altStackRecord.write(SignalStack(CPointer<Unit>(altStackMemory), 0, UIntNative(SIGNAL_STACK_SIZE)))
        if (sigaltstack(altStackRecord, CPointer<SignalStack>()) != 0) {
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
