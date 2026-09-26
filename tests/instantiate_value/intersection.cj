package instantiate_intersection
interface A {}
interface B {}
class Both <: A & B {}
func identity<T>(value: T): T where T <: A { return value }
func capture<T>(): (T) -> T where T <: A & B { return identity<T> }
class Holder<T> where T <: A {
    public static func identity<U>(value: U): U where U <: A { return value }
}
func captureParent<T>(): (T) -> T where T <: A & B { return Holder<T>.identity<T> }
main(): Int64 {
    let value = capture<Both>()(Both())
    let _ = captureParent<Both>()(value)
    return 0
}
