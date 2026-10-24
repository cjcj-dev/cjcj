@C
struct Pair {
    var x: UInt64 = 17u64
    var y: UInt64 = 23u64
}
@C
struct Ret {
    var x: UInt64 = 0u64
    var y: UInt64 = 0u64
    var z: UInt64 = 0u64
}
@C[packed]
struct Packed {
    var tag: UInt8 = 3u8
    var value: UInt32 = 1000u32
}
@C
struct Nine {
    var a: UInt8 = 1u8
    var b: UInt8 = 0u8
    var c: UInt8 = 0u8
    var d: UInt8 = 0u8
    var e: UInt8 = 0u8
    var f: UInt8 = 0u8
    var g: UInt8 = 0u8
    var h: UInt8 = 0u8
    var i: UInt8 = 9u8
}
@C
struct FloatPair {
    var x: Float32 = 8.0f32
    var y: Float32 = 9.0f32
}
@C
struct FloatFour {
    var x: Float32 = 10.0f32
    var y: Float32 = 11.0f32
    var z: Float32 = 12.0f32
    var w: Float32 = 13.0f32
}
@C
struct Empty {}
foreign {
    func c_sret(a: UInt64, b: UInt64, c: UInt64, d: UInt64, p: Pair): Ret
    func c_pair(p: Pair): UInt64
    func c_packed(p: Packed): UInt64
    func c_packed_ret(): Packed
    func c_nine(p: Nine): UInt64
    func c_sse(a: Float64, b: Float64, c: Float64, d: Float64, e: Float64, f: Float64, g: Float64,
        p: FloatPair, q: FloatFour): Int32
    func c_vararg(e: Empty, tag: Int32, ...): Int32
    func c_callbacks(): Int32
}
@C
func cj_sret(a: UInt64, b: UInt64, c: UInt64, d: UInt64, p: Pair): Ret {
    var r = Ret()
    r.x = p.x
    r.y = p.y
    r.z = a + b + c + d
    return r
}
@C
func cj_packed(p: Packed): UInt64 { return UInt64(p.tag) + UInt64(p.value) }
@C
func cj_nine(p: Nine): UInt64 { return UInt64(p.a) + UInt64(p.i) }
@C
func cj_sse(a: Float64, b: Float64, c: Float64, d: Float64, e: Float64, f: Float64, g: Float64,
    p: FloatPair, q: FloatFour): Int32 {
    return if (a == 1.0 && b == 2.0 && c == 3.0 && d == 4.0 && e == 5.0 && f == 6.0 && g == 7.0 &&
        p.x == 8.0f32 && p.y == 9.0f32 && q.x == 10.0f32 && q.y == 11.0f32 &&
        q.z == 12.0f32 && q.w == 13.0f32) { 1i32 } else { 0i32 }
}
main(): Int64 {
    unsafe {
        let r = c_sret(1u64, 2u64, 3u64, 4u64, Pair())
        if (r.x != 17u64 || r.y != 23u64 || r.z != 10u64) { println("FAIL sret x=${r.x} y=${r.y} z=${r.z}"); return 1 }
        if (c_pair(Pair()) != 40u64) { return 2 }
        if (c_packed(Packed()) != 1003u64) { return 3 }
        let p = c_packed_ret()
        if (p.tag != 3u8 || p.value != 1000u32) { return 4 }
        if (c_nine(Nine()) != 10u64) { return 5 }
        if (c_sse(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, FloatPair(), FloatFour()) != 1i32) { return 6 }
        if (c_vararg(Empty(), 42i32, 1.5f32, -3i8, Empty(), 250u8, 60000u16, true, -30000i16) != 1i32) { return 7 }
        let callbacks = c_callbacks()
        if (callbacks != 0i32) { return 10 + Int64(callbacks) }
    }
    println("PASS sret pair packed nine SSE zero-fixed varargs callbacks")
    return 0
}
