foreign { func c_control(a: UInt64, b: UInt64): UInt64 }
main(): Int64 {
    unsafe {
        if (c_control(17u64, 23u64) != 40u64) { println("FAIL scalar control"); return 1 }
    }
    println("PASS scalar control")
    return 0
}
