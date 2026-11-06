package cjcj::driver

public enum ToolFutureState {
    | SUCCESS
    | RUNNING
    | FAILED
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
            try {
                result = future.get()
            } catch (e: Exception) {
                eprintln("internal backend command failed: ${e.message}")
                result = Some(false)
            }
        }
        let succeeded = result.getOrThrow()
        exitCode = if (succeeded) { 0 } else { 1 }
        return if (succeeded) { ToolFutureState.SUCCESS } else { ToolFutureState.FAILED }
    }
}


main(): Int64 {
    let f = ThreadFuture(spawn { true })
    if (let ToolFutureState.SUCCESS <- f.GetState()) {
        println("THREAD_FUTURE_OK")
        return f.exitCode
    }
    return 1
}
