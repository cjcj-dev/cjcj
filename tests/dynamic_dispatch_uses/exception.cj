package dispatch_uses_exception

interface Measured<T> where T <: Measured<T> {
    prop size: Int64
    func safeSize(other: T): Int64 {
        try { other.size } catch (e: Exception) { 0 }
    }
}
class Item <: Measured<Item> { public prop size: Int64 { get() { 7 } } }
main(): Int64 { Item().safeSize(Item()) - 7 }
