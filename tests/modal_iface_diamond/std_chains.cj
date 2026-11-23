// Other std chains whose super declares modal defaults: IOStream <: InputStream (`read(this @local!)`) and
// EquatableCollection<T> <: Collection<T> (`isEmpty(this @local?)`, `toArray(this @local?/@local!)`).
import std.io.*
import std.collection.*

class IO <: IOStream & InputStream {
    public func read(buffer: Array<Byte>): Int64 { buffer.size }
    public func write(buffer: Array<Byte>): Unit {}
}

class EC <: EquatableCollection<Int64> & Collection<Int64> {
    let a: Array<Int64> = [1, 2, 3]
    public prop size: Int64 { get() { a.size } }
    public func iterator(): Iterator<Int64> { a.iterator() }
    public func isEmpty(): Bool { a.isEmpty() }
    public func toArray(): Array<Int64> { a.clone() }
    public func contains(element: Int64): Bool { a.contains(element) }
    public func contains(all!: Collection<Int64>): Bool { all.iterator().all({ e => a.contains(e) }) }
}

main(): Int64 {
    let r = "${IO().read(Array<Byte>(4, repeat: 0))} ${EC().contains(2)} ${EC().size}"
    println(r)
    if (r == "4 true 3") { 0 } else { 4 }
}
