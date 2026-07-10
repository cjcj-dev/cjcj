package cjcj::driver

public open class ToolFuture {
    public var spawnErrorMessage: String = ""
    public var exitCode: Int64 = 0

    public init() {}

    public open func GetState(): ToolFutureState {
        return if (exitCode == 0) { ToolFutureState.SUCCESS } else { ToolFutureState.FAILED }
    }
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
    private let result: Bool

    public init(result: Bool) {
        super()
        this.result = result
        exitCode = if (result) { 0 } else { 1 }
    }

    public override func GetState(): ToolFutureState {
        return if (result) { ToolFutureState.SUCCESS } else { ToolFutureState.FAILED }
    }
}

public class ProcessFuture <: ToolFuture {
    public init(code: Int64) {
        super()
        exitCode = code
    }

    public override func GetState(): ToolFutureState {
        return if (exitCode == 0) { ToolFutureState.SUCCESS } else { ToolFutureState.FAILED }
    }
}
