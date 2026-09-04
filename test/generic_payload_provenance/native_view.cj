// Direct AS0 -> AS1 native view: an @C aggregate remains natively addressed
// when it is passed through erased generic boxing.
@C
struct NativePair {
    let left: Int64
    let right: Int64

    public init(left: Int64, right: Int64) {
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
    let result = box(NativePair(5, 6))
    if (result.value.left != 5 || result.value.right != 6) {
        throw Exception("bad native-view payload copy")
    }
}
