enum TimeUnit<T> {
    Year(T) | Month
}
type Time<T> = TimeUnit<T>
main(): Int64 {
    let time: Time<Int32> = TimeUnit<Int32>.Year(2020)
    let res: Int32 = match (time) {
        case Year(x) => x
        case Month => 11
    }
    println(res)
    0
}
