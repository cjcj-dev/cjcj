struct Foo<T> where T <: ToString {}
type Foobar<R> = Foo<R>
struct S {}
main() {
    let a = Foobar<S>()
}
