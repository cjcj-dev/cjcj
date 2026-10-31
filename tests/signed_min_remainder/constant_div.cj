package signed_min_constant_div

main(): Int64 {
    let xInt8: Int8 = -128
    let yInt8: Int8 = -1
    let rInt8 = xInt8 / yInt8
    println("ASSERT constant_div.Int8=${rInt8}")
    let xInt16: Int16 = -32768
    let yInt16: Int16 = -1
    let rInt16 = xInt16 / yInt16
    println("ASSERT constant_div.Int16=${rInt16}")
    let xInt32: Int32 = -2147483648
    let yInt32: Int32 = -1
    let rInt32 = xInt32 / yInt32
    println("ASSERT constant_div.Int32=${rInt32}")
    let xInt64: Int64 = -9223372036854775808
    let yInt64: Int64 = -1
    let rInt64 = xInt64 / yInt64
    println("ASSERT constant_div.Int64=${rInt64}")
    let xIntNative: IntNative = -9223372036854775808
    let yIntNative: IntNative = -1
    let rIntNative = xIntNative / yIntNative
    println("ASSERT constant_div.IntNative=${rIntNative}")
    return 0
}
