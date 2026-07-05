func cast2<T, R>(x: T, r: R): R { let _ = x; return r }
main(): Int64 {
    let y: Int64 = cast2("a", 3)
    println(y)
    return 0
}
