package cjcj::option

import std.runtime.*
@When[os == "Windows"]
import cjcj::utils.{threadDelaySynchronizer, writeICEMessage}

foreign {
    func _exit(status: Int32): Unit
}

@When[os == "Windows"]
foreign {
    func SetConsoleCtrlHandler(handler: WindowsConsoleHandler, add: Int32): Int32
    func SetUnhandledExceptionFilter(handler: WindowsExceptionHandler): CPointer<Unit>
}

// These handlers share the manager's package to avoid utils -> option -> utils.
// C++ fc3fb2b4 src/Utils/SignalUnix.cpp:76-92; SignalWin.cpp:19-29,62-75.
@When[os == "Windows"]
private let EXCEPTION_EXECUTE_HANDLER: Int32 = 1

@When[os == "Windows"]
private let TRUE: Int32 = 1

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

@When[os == "Windows"]
private func windowsConsoleCtrlHandler(ctrlType: UInt32): Bool {
    let _ = ctrlType
    TempFileManager.Instance().DeleteTempFilesSignalSafe()
    return false
}

@When[os == "Windows"]
private func windowsUnhandledExceptionHandler(ep: CPointer<WindowsExceptionPointers>): Int32 {
    threadDelaySynchronizer()
    unsafe {
        if (ep.isNull()) {
            return EXCEPTION_EXECUTE_HANDLER
        }
        let exceptionPointers = ep.read()
        if (exceptionPointers.exceptionRecord.isNull()) {
            return EXCEPTION_EXECUTE_HANDLER
        }
        let exitCode = Int32(exceptionPointers.exceptionRecord.read().exceptionCode)
        writeICEMessage(Int64(exitCode))
        TempFileManager.Instance().DeleteTempFilesSignalSafe()
        return exitCode
    }
}

@When[os == "Windows"]
private let windowsConsoleCtrlHandlerC: WindowsConsoleHandler = { ctrlType: UInt32 =>
    windowsConsoleCtrlHandler(ctrlType)
}

@When[os == "Windows"]
private let windowsUnhandledExceptionHandlerC: WindowsExceptionHandler = {
    ep: CPointer<WindowsExceptionPointers> => windowsUnhandledExceptionHandler(ep)
}

@When[os == "Windows"]
public func RegisterCrashExceptionHandler(): Unit {
    unsafe {
        let _ = SetUnhandledExceptionFilter(windowsUnhandledExceptionHandlerC)
    }
}

@When[os != "Windows"]
private func ctrlCSignalHandler(signum: Int32): Bool {
    TempFileManager.Instance().DeleteTempFilesSignalSafe()
    unsafe {
        _exit(signum + 128)
    }
    return true
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

