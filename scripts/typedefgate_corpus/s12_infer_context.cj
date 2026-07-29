class GenA<T> {}
type TypeClass<Y> = GenA<Y>
type TypeB<X> = TypeClass<X>
main(): Int64 {
    let f1: TypeB<Int64> = TypeB()
    let g1: TypeClass<Int64> = TypeB()
    let h1: GenA<Int64> = TypeB()
    let i1: TypeB<Int64> = TypeClass()
    let j1: TypeClass<Int64> = TypeClass()
    let k1: GenA<Int64> = TypeClass()
    let l1: TypeB<Int64> = GenA()
    let m1: TypeClass<Int64> = GenA()
    let n1: GenA<Int64> = GenA()
    let f2 = TypeB<Int64>()
    let i2 = TypeClass<Int64>()
    let l2 = GenA<Int64>()
    0
}
