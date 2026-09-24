import std.concurrent.threadScope

main(): Int64 {
    let result = threadScope<Int64, Int64>({ _ => 42 })
    println("concurrent-result=${result}")
    return if (result == 42) { 0 } else { 1 }
}
