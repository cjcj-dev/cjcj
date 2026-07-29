type Opt<T> = Option<T>
main(): Int64 {
    let time: Opt<Int32> = Option<Int32>.Some(2020)
    let res: Int32 = match (time) {
        case Some(x) => x
        case None => 11
    }
    println(res)
    0
}
