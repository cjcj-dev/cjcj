import std.collection.*
func rec<T>(x: T): Int64 {
    let _ = x
    return rec<ArrayList<T>>(ArrayList<T>())
}
main(): Int64 {
    return rec(1)
}
