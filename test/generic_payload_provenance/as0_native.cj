// AS0/native source: a stack value boxed into an erased generic object.
struct Pair<T> {
    let left: T
    let right: T

    public init(left: T, right: T) {
        this.left = left
        this.right = right
    }
}

class Box<T> {
    let value: T

    public init(value: T) {
        this.value = value
    }
}

func box<T>(value: T): Box<T> {
    Box<T>(value)
}

main() {
    let result = box(Pair<Int64>(1, 2))
    if (result.value.left != 1 || result.value.right != 2) {
        throw Exception("bad native payload copy")
    }
}
