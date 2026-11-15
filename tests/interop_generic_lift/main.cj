package interop_generic_lift

@C
struct Triple {
    var a: Int64 = 0
    var b: Int64 = 0
    var c: Int64 = 0
}

// The escaped lambda must obtain T's TypeInfo in its new generic scope.
@NeverInline
func makeSize<T>(): () -> UIntNative where T <: CType {
    return { => sizeOf<T>() }
}

@NeverInline
func concreteSize(): () -> UIntNative {
    return { => sizeOf<Int64>() }
}

main(): Int64 {
    let byteSize = makeSize<UInt8>()
    let tripleSize = makeSize<Triple>()
    let concrete = concreteSize()
    if (byteSize() != 1 || tripleSize() != 24 || concrete() != 8) {
        throw Exception("lifted intrinsic selected the wrong TypeInfo")
    }
    println("GENERIC_INTRINSIC_LIFT_OK")
    return 0
}
