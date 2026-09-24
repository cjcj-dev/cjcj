package builder_const_initializer
const func compute(value: Int64): Int64 {
    return value * value + 1
}
const answer: Int64 = compute(10)
main(): Int64 { return answer }
