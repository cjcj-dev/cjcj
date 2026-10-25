package signed_min_dynamic_mod

main(args: Array<String>): Int64 {
    if (args.size != 3) { return 2 }
    let width = args[0]
    let x = Int64.parse(args[1])
    let y = Int64.parse(args[2])
    if (width == "Int8") {
        try {
            let result = Int8(x) % Int8(y)
            println("ASSERT dynamic_mod.Int8=${result}")
        } catch (_: ArithmeticException) {
            println("ASSERT dynamic_mod.Int8=overflow")
        }
        return 0
    }
    if (width == "Int16") {
        try {
            let result = Int16(x) % Int16(y)
            println("ASSERT dynamic_mod.Int16=${result}")
        } catch (_: ArithmeticException) {
            println("ASSERT dynamic_mod.Int16=overflow")
        }
        return 0
    }
    if (width == "Int32") {
        try {
            let result = Int32(x) % Int32(y)
            println("ASSERT dynamic_mod.Int32=${result}")
        } catch (_: ArithmeticException) {
            println("ASSERT dynamic_mod.Int32=overflow")
        }
        return 0
    }
    if (width == "Int64") {
        try {
            let result = Int64(x) % Int64(y)
            println("ASSERT dynamic_mod.Int64=${result}")
        } catch (_: ArithmeticException) {
            println("ASSERT dynamic_mod.Int64=overflow")
        }
        return 0
    }
    if (width == "IntNative") {
        try {
            let result = IntNative(x) % IntNative(y)
            println("ASSERT dynamic_mod.IntNative=${result}")
        } catch (_: ArithmeticException) {
            println("ASSERT dynamic_mod.IntNative=overflow")
        }
        return 0
    }
    return 3
}
