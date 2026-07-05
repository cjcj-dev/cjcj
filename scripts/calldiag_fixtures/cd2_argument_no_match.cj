interface Nums {}
func need<T>(x: T): Int64 where T <: Nums {
    let _ = x
    return 1
}
main(): Int64 {
    return need<Int64>(42)
}
