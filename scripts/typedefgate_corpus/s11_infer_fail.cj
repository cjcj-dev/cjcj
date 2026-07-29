class GenA<T> {}
type TypeClass<Y> = GenA<Y>
type TypeB<X> = TypeClass<X>
type TypeC = TypeClass<Int64>
main() {
    var a = TypeB()
    var b = TypeClass()
    var c = GenA()
    var d = TypeC()
    0
}
