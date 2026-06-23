struct Vec {
    let data: Array<Int64>

    public init(a: Int64, b: Int64) {
        this.data = [a, b]
    }

    public operator func +(rhs: Vec): Vec {
        return Vec(data[0] + rhs.data[0], data[1] + rhs.data[1])
    }

    public operator func ==(rhs: Vec): Bool {
        return data[0] == rhs.data[0] && data[1] == rhs.data[1]
    }

    public operator func [](i: Int64): Int64 {
        return data[i]
    }
}

main() {
    let a = Vec(1, 2)
    let b = Vec(3, 4)
    let c = a + b
    println(c[0])
    println(c[1])
    println(c == Vec(4, 6))
    println(a == b)
}
