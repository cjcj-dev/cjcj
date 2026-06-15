package cangjie_compiler::utils

public class ParallelUtil {
    private let threadsNum: Int64

    public init(threadsNum: Int64) {
        this.threadsNum = threadsNum
    }

    public func ThreadsNum(): Int64 {
        return threadsNum
    }

    public func RunAST2CHIRInParallel(): Unit {
        // TODO(selfhost:Utils): restore CHIRBuilder/Translator-based parallel AST2CHIR entrypoint once CHIR public Cangjie types exist.
    }
}

