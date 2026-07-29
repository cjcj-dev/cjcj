type A<K> = StructA<K>
type B<T> = A<Rune>
type C = B<Int64>
type D<T> = C
struct StructA<K> {
    public var b: K
    public StructA(var y: K) {
        this.b = y
    }
    public static prop e: Bool {
        get() { true }
    }
}
main(): Int64 {
    A<Bool>(A<Bool>.e)
    D<StructA<Int64>>(r'a')
    let ok = D<String>.e
    if (ok) { println(1) } else { println(0) }
    0
}
