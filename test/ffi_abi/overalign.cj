@C[align: 16]
struct A { var x: UInt8 = 7u8 }
@C
struct Box { var a: A = A() }
@C[align: 16]
struct AF { var x: Float32 = 1.5f32 }
@C
struct FBox { var a: AF = AF() }
foreign {
    func c_take(a: UInt64, b: UInt64, c: UInt64, d: UInt64, e: UInt64, p: Box, tail: UInt64): UInt64
    func c_stack(a: UInt64, b: UInt64, c: UInt64, d: UInt64, e: UInt64, f: UInt64, p: Box, tail: UInt64): UInt64
    func c_box(p: Box): Box
    func c_fbox(p: FBox): FBox
    func c_variadic(a: UInt64, b: UInt64, c: UInt64, d: UInt64, e: UInt64, ...): Int32
    func c_varstack(a: UInt64, b: UInt64, c: UInt64, d: UInt64, e: UInt64, f: UInt64, ...): Int32
    func c_over_callbacks(): Int32
    func c_get_take(): CFunc<(UInt64, UInt64, UInt64, UInt64, UInt64, Box, UInt64) -> UInt64>
    func c_get_stack(): CFunc<(UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, Box, UInt64) -> UInt64>
    func c_get_box(): CFunc<(Box) -> Box>
    func c_get_fbox(): CFunc<(FBox) -> FBox>
}
@C
func cj_take(a: UInt64, b: UInt64, c: UInt64, d: UInt64, e: UInt64, p: Box, tail: UInt64): UInt64 {
    return a + b + c + d + e + UInt64(p.a.x) + tail
}
@C
func cj_stack(a: UInt64, b: UInt64, c: UInt64, d: UInt64, e: UInt64, f: UInt64, p: Box, tail: UInt64): UInt64 {
    return a + b + c + d + e + f + UInt64(p.a.x) + tail
}
@C
func cj_box(p: Box): Box { var r = p; r.a.x = p.a.x + 1u8; return r }
@C
func cj_fbox(p: FBox): FBox { var r = p; r.a.x = p.a.x + 2.0f32; return r }
main(): Int64 {
    unsafe {
        if (c_take(1u64,2u64,3u64,4u64,5u64,Box(),99u64) != 121u64) { println("FAIL overalign register"); return 1 }
        if (c_stack(1u64,2u64,3u64,4u64,5u64,6u64,Box(),99u64) != 127u64) { println("FAIL overalign stack"); return 2 }
        if (c_box(Box()).a.x != 8u8) { println("FAIL overalign return"); return 3 }
        if (c_fbox(FBox()).a.x != 3.5f32) { println("FAIL overalign SSE return"); return 4 }
        if (c_variadic(1u64,2u64,3u64,4u64,5u64,Box(),99u64) != 1i32) { println("FAIL overalign vararg register"); return 5 }
        if (c_varstack(1u64,2u64,3u64,4u64,5u64,6u64,Box(),99u64) != 1i32) { println("FAIL overalign vararg stack"); return 6 }
        let r = c_over_callbacks()
        if (r != 0i32) { println("FAIL overalign callbacks ${r}"); return 10 + Int64(r) }
        if (c_get_take()(1u64,2u64,3u64,4u64,5u64,Box(),99u64) != 121u64) { println("FAIL indirect overalign register"); return 21 }
        if (c_get_stack()(1u64,2u64,3u64,4u64,5u64,6u64,Box(),99u64) != 127u64) { println("FAIL indirect overalign stack"); return 22 }
        if (c_get_box()(Box()).a.x != 8u8) { println("FAIL indirect overalign return"); return 23 }
        if (c_get_fbox()(FBox()).a.x != 3.5f32) { println("FAIL indirect overalign SSE return"); return 24 }
    }
    println("PASS overalign args return varargs callbacks")
    return 0
}
