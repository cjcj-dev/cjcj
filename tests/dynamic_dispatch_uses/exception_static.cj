package dispatch_uses_exception_static

interface Measured { static prop size: Int64 }
interface Reader<T> where T <: Measured {
    func safeSize(): Int64 {
        try { T.size } catch (e: Exception) { 0 }
    }
}
class Item <: Measured { public static prop size: Int64 { get() { 7 } } }
class ItemReader <: Reader<Item> {}
main(): Int64 { ItemReader().safeSize() - 7 }
