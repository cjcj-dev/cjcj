type F<T, U> = (T) -> U
type U<X, Y> = F<X, Y>
func foo(): U<Int32, Bool> {
    {i: Int32 => true}
}
main(): Int64 {
    let f = foo()
    if (f(1)) {
        println(1)
    } else {
        println(0)
    }
    0
}
