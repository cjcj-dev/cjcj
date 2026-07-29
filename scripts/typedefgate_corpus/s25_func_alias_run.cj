type Parse<T, Result> = ((Array<T>, Result)) -> ?Array<T>
func f<T, U>(a: ((Array<T>, U))): ?Array<T> {
    let (x, y) = a
    if (false) {
        None
    } else {
        x
    }
}
main(): Int64 {
    let x: Parse<Int64, Bool> = f<Int64, Bool>
    let y: Int64 = match (x(([1, 2, 3], true))) {
        case None => 1
        case _ => 2
    }
    println(y)
    0
}
