import std.collection.*
func wrap<T>(x: T): ArrayList<T> { let l = ArrayList<T>(); l.add(x); return l }
func unwrap<T>(l: ArrayList<T>): T { return l[0] }
main(): Int64 {
    let v = unwrap(wrap(42))
    println(v)
    return 0
}
