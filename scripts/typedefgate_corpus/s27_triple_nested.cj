class A<T> {}
type A1<T> = A<T>
type A2<T> = A1<T>
main(): Int64 {
    let a = A2<Int64>()
    0
}
