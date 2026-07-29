struct Foo<T> where T <: ToString {}
type Foobar<R> = Foo<R>
main(): Int64 {
    let a = Foobar<String>()
    0
}
