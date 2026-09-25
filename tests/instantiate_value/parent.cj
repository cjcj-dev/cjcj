package instantiate_parent
class Holder<T> {
    public static func identity<U>(value: U): U { return value }
}
func capture<T, U>(): (U) -> U { return Holder<T>.identity<U> }
main(): Int64 { return capture<Int64, Int64>()(23) }
