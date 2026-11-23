// Generic interface, ArrayList and user ToString dispatched through an interface-typed array.
import std.collection.*

interface Shape {
    func area(): Int64
}

class Sq <: Shape & ToString {
    let s: Int64
    init(s: Int64) { this.s = s }
    public func area(): Int64 { s * s }
    public func toString(): String { "Sq(${s})" }
}

interface Holder<T> {
    func get(): T
}

class IntHolder <: Holder<Int64> {
    public func get(): Int64 { 7 }
}

func total<T>(xs: ArrayList<T>): Int64 where T <: Shape {
    var t = 0
    for (x in xs) { t += x.area() }
    t
}

func unhold<T>(h: Holder<T>): T { h.get() }

main(): Int64 {
    let xs = ArrayList<Sq>()
    xs.add(Sq(2))
    xs.add(Sq(3))
    let parts: Array<ToString> = [Sq(2), Sq(3)]
    var names = ""
    for (p in parts) {
        if (names != "") { names = names + "," }
        names = names + p.toString()
    }
    let line = "${total(xs)} ${unhold(IntHolder())} ${names} ${xs.size} ${xs.isEmpty()}"
    println(line)
    if (line == "13 7 Sq(2),Sq(3) 2 false") { 0 } else { 3 }
}
