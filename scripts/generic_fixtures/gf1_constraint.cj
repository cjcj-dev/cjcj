interface Shape { func area(): Int64 }
class Sq <: Shape { public func area(): Int64 { return 4 } }
func totalArea<T>(xs: Array<T>): Int64 where T <: Shape {
    var s = 0
    for (x in xs) { s += x.area() }
    return s
}
main(): Int64 {
    println(totalArea([Sq(), Sq()]))
    return 0
}
