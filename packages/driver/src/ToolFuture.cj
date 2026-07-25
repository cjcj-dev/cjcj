package cjcj::driver

@When[os != "Windows"]
private let WNOHANG: Int32 = 1

@When[os == "Windows"]
private let WAIT_FAILED: UInt32 = UInt32.Max
@When[os == "Windows"]
private let WAIT_ABANDONED: UInt32 = 0x00000080u32
@When[os == "Windows"]
private let WAIT_TIMEOUT: UInt32 = 0x00000102u32

@When[os != "Windows"]
foreign {
    func waitpid(pid: Int32, status: CPointer<Int32>, options: Int32): Int32
}

@When[os == "Windows"]
foreign {
    func WaitForSingleObject(handle: CPointer<Unit>, milliseconds: UInt32): UInt32
    func GetExitCodeProcess(process: CPointer<Unit>, exitCode: CPointer<UInt32>): Int32
    func CloseHandle(handle: CPointer<Unit>): Int32
}

public abstract class ToolFuture {
    public var spawnErrorMessage: String = ""
    public var exitCode: Int64 = 0

    public init() {}

    public func GetState(): ToolFutureState
}

public class ErrorFuture <: ToolFuture {
    public init(message: String) {
        super()
        spawnErrorMessage = message
        exitCode = 1
    }

    public override func GetState(): ToolFutureState {
        return ToolFutureState.FAILED
    }
}

public class ThreadFuture <: ToolFuture {
    private let future: Future<Bool>
    private var result: Option<Bool> = None

    public init(future: Future<Bool>) {
        super()
        this.future = future
    }

    public override func GetState(): ToolFutureState {
        if (let None <- result) {
            result = future.get()
        }
        let succeeded = result.getOrThrow()
        exitCode = if (succeeded) { 0 } else { 1 }
        return if (succeeded) { ToolFutureState.SUCCESS } else { ToolFutureState.FAILED }
    }
}

@When[os == "Windows"]
public class WindowsProcessFuture <: ToolFuture {
    private let process: CPointer<Unit>
    private let thread: CPointer<Unit>

    public init(process: CPointer<Unit>, thread: CPointer<Unit>) {
        super()
        this.process = process
        this.thread = thread
    }

    public override func GetState(): ToolFutureState {
        let state = unsafe { WaitForSingleObject(process, 0u32) }
        if (state == WAIT_FAILED || state == WAIT_ABANDONED) {
            return ToolFutureState.FAILED
        }
        if (state == WAIT_TIMEOUT) {
            return ToolFutureState.RUNNING
        }
        try (exitCodePtr = LibC.malloc<UInt32>().asResource()) {
            if (exitCodePtr.value.isNull() || unsafe { GetExitCodeProcess(process, exitCodePtr.value) } == 0) {
                return ToolFutureState.FAILED
            }
            exitCode = Int64(unsafe { exitCodePtr.value.read() })
        }
        let _ = unsafe { CloseHandle(process) }
        let _ = unsafe { CloseHandle(thread) }
        return if (exitCode == 0) { ToolFutureState.SUCCESS } else { ToolFutureState.FAILED }
    }
}

@When[os != "Windows"]
public class LinuxProcessFuture <: ToolFuture {
    private let pid: Int32

    public init(pid: Int32) {
        super()
        this.pid = pid
    }

    public override func GetState(): ToolFutureState {
        var status: Int32 = 0
        let waitResult = try (statusPtr = LibC.malloc<Int32>().asResource()) {
            if (statusPtr.value.isNull()) {
                exitCode = -1
                return ToolFutureState.FAILED
            }
            unsafe { statusPtr.value.write(0) }
            let result = unsafe { waitpid(pid, statusPtr.value, WNOHANG) }
            status = unsafe { statusPtr.value.read() }
            result
        }
        let signalBits = status & 0x7f
        if (signalBits == 0) {
            exitCode = Int64((status >> 8) & 0xff)
        } else if (signalBits != 0x7f) {
            exitCode = Int64(128 + signalBits)
        }
        if (waitResult < 0) {
            exitCode = -1
        }
        if (waitResult < 0 || status != 0) {
            return ToolFutureState.FAILED
        }
        if (waitResult > 0) {
            return ToolFutureState.SUCCESS
        }
        return ToolFutureState.RUNNING
    }
}
