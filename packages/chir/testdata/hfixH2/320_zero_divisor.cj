package hfixh2_320

public func divideAfterGuard(divisor: Int64): Int64 {
    if (divisor == 0) {
        return 42 / divisor
    }
    return 0
}

public func remainderAfterGuard(divisor: Int64): Int64 {
    if (divisor == 0) {
        return 42 % divisor
    }
    return 0
}

public func divideAfterRangeGuard(divisor: Int64): Int64 {
    if (divisor >= 0 && divisor <= 0) {
        return 42 / divisor
    }
    return 0
}
