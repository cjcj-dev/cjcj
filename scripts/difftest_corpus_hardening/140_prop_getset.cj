class Box {
    private var v: Int64 = 0

    public prop doubled: Int64 {
        get() {
            return v * 2
        }
    }

    public mut prop value: Int64 {
        get() {
            return v
        }
        set(n) {
            v = n
        }
    }
}

main() {
    let b = Box()
    b.value = 21
    println(b.value)
    println(b.doubled)
    b.value = 5
    println(b.doubled)
}
