package expression_exception_ops

public func negAdd(value: Int64): Int64 {
    try {
        return -value + value
    } catch (_: ArithmeticException) {
        return 0
    }
}
