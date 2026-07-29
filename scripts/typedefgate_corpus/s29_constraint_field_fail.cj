type A<T> = Cl<T>
open class Base {}
class Cl<U> where U <: Base {}
class Sub<X> {
    public var a: A<X>
}
main() {
    0
}
