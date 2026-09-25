public func ops(a: Float64, b: Float64, x: Int64, y: Int64): Float64 {
    let added = a + b
    let subtracted = a - b
    let multiplied = a * b
    let divided = a / b
    let negated = -a
    let compared = a < b
    let integerAdded = x + y
    if (compared) {
        return added + subtracted + multiplied + divided + negated + Float64(integerAdded)
    }
    return subtracted
}

main(): Int64 {
    if (ops(1.25, 2.5, 3, 4) == 0.0) {
        return 1
    }
    return 0
}
