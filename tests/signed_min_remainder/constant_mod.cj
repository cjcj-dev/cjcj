package signed_min_constant_mod

main(): Int64 {
    let xInt8: Int8 = -128
    let yInt8: Int8 = -1
    let rInt8 = xInt8 % yInt8
    println("ASSERT constant_mod.Int8=${rInt8}")
    if (rInt8 != 0) { return 1 }
    let xInt16: Int16 = -32768
    let yInt16: Int16 = -1
    let rInt16 = xInt16 % yInt16
    println("ASSERT constant_mod.Int16=${rInt16}")
    if (rInt16 != 0) { return 1 }
    let xInt32: Int32 = -2147483648
    let yInt32: Int32 = -1
    let rInt32 = xInt32 % yInt32
    println("ASSERT constant_mod.Int32=${rInt32}")
    if (rInt32 != 0) { return 1 }
    let xInt64: Int64 = -9223372036854775808
    let yInt64: Int64 = -1
    let rInt64 = xInt64 % yInt64
    println("ASSERT constant_mod.Int64=${rInt64}")
    if (rInt64 != 0) { return 1 }
    let xIntNative: IntNative = -9223372036854775808
    let yIntNative: IntNative = -1
    let rIntNative = xIntNative % yIntNative
    println("ASSERT constant_mod.IntNative=${rIntNative}")
    if (rIntNative != 0) { return 1 }
    return 0
}
