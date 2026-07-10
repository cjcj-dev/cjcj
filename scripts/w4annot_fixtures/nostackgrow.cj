func callee(value: Int64): Int64 {
    return value + 1
}

@NoStackGrow
func noGrow(value: Int64): Int64 {
    return callee(value)
}
