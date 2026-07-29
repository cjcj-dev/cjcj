class GenA<T, V> {}
type TypeClass1<T, V> = GenA<T, V>
type TypeClass2<T> = GenA<T, T>
type A = TypeClass1<Int64, Int8>
type B<X> = TypeClass2<X>
main() {
    var a1: A<Int32>
    var a2: A = A<Int32>()
    var b1: B<Int64, Int32>
    var b2 = B<Int64, Int32>()
    0
}
