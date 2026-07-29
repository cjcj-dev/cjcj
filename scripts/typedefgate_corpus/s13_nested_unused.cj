class GenA<T, V> {}
type TypeClass2<T> = GenA<T, T>
type TypeClass3<X, Y> = TypeClass2<X>
main() {
    var a1: TypeClass3<Int32>
    var a2 = TypeClass3<Int32>()
    0
}
