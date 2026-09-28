package dispatch_uses_static

interface Measured {
    static prop size: Int64
}
interface Reader<T> where T <: Measured {
    func readSize(): Int64 { T.size }
}
class Item <: Measured { public static prop size: Int64 { get() { 7 } } }
class ItemReader <: Reader<Item> {}
main(): Int64 { ItemReader().readSize() - 7 }
