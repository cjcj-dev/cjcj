main() {
    let a = Array<Int64>(3, repeat: 0)
    a[0] = 7
    a[1] = 11
    println(a[0])
    println(a.size)
    var sum: Int64 = 0
    var i: Int64 = 0
    while (i < a.size) {
        sum += a[i]
        i++
    }
    println(sum)
}
