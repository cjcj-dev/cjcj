class GenA<T, V> {}
type TypeClass1<T, V> = GenA<T, V>
type TypeClass2<T> = GenA<T, T>
type A = TypeClass1<Int64, Int8>
type B<X> = TypeClass2<X>
type C<X> = TypeClass2<Array<X>>
main(): Int64 {
    let a: A = A()
    let b: B<Int64> = B<Int64>()
    let c: C<Int64> = GenA<Array<Int64>, Array<Int64>>()
    0
}
