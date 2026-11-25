func nested(input: Int64): Int64 {
    let outer = { value: Int64 =>
        let inner = { flag: Bool =>
            var total = 0
            for (i in 0..4) { if (flag) { total += i } else { total += 1 } }
            total
        }
        try { inner(value > 0) } catch (e: Exception) { -1 }
    }
    outer(input)
}
main(): Int64 {
    if (nested(1) != 6 || nested(0) != 4) { return 1 }
    println("NESTED_CFG_OK")
    return 0
}
