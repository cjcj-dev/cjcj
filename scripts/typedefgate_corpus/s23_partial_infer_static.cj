open class A<T, K> {
    static func test(a: T, b: K) {
        b
    }
}
class B<K> <: A<Int8, Int32> {}
type C<T> = A<T, Int16>
main(): Int64 {
    let x = C.test(1, 2)
    println(x)
    0
}
