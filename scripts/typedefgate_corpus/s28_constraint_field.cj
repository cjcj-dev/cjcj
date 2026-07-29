type A<T> = Cl<T>
open class Base {}
class Cl<U> where U <: Base {}
class Sub<X> where X <: Base {
    public var a: A<X>
    public init(a: A<X>) {
        this.a = a
    }
}
main(): Int64 {
    0
}
