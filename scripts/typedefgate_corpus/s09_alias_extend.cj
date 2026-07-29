class GenA<T, V> {}
type TypeClass2<T> = GenA<T, T>
type C<X> = TypeClass2<Array<X>>
interface InterfaceI<X> {}
extend<Y> C<Y> <: InterfaceI<Y> {}
main(): Int64 {
    let i: InterfaceI<Int64> = C<Int64>()
    0
}
