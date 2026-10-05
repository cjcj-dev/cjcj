package cpointer_stride

@C
struct Triple {
    var a: Int64 = 0
    var b: Int64 = 0
    var c: Int64 = 0
}

// The operators are non-Frozen std.core functions. Link against std rebuilt
// by the compiler under test; rebuilding only this client cannot test codegen.
func check<T>(name: String, n: Int64): Int64 where T <: CType {
    let p = CPointer<T>()
    let forward = unsafe { p + n }
    let backward = unsafe { forward - n }
    let actual = forward.toUIntNative() - p.toUIntNative()
    let expected = UIntNative(n) * sizeOf<T>()
    let ok = actual == expected && backward.toUIntNative() == p.toUIntNative()
    println("STRIDE ${name} actual=${actual} expected=${expected} restored=${backward.toUIntNative()} ok=${ok}")
    return if (ok) { 0 } else { 1 }
}

main(): Int64 {
    var failures: Int64 = 0
    failures += check<Int64>("Int64", 3)
    failures += check<Triple>("Triple24", 3)
    failures += check<CPointer<Unit>>("CPointer", 3)
    failures += check<UInt8>("UInt8", 3)
    return failures
}
