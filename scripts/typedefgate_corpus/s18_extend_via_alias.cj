type Li = Array<Rune>
extend<T> Array<T> {
    public static func a() {
        1
    }
}
main(): Int64 {
    let b: Int64 = Li.a()
    println(b)
    0
}
