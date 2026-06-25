struct Pair {
    var a: Int64
    var b: Int64
    init(x: Int64, y: Int64) {
        a = x
        b = y
    }
}

struct Cell<T> {
    var value: T
    init(x: T) {
        value = x
    }
}

class RefCell<T> {
    var value: T
    init(x: T) {
        value = x
    }
    func replace(next: T): T {
        value = next
        return value
    }
}

func replace<T>(cell: Cell<T>, next: T): T {
    var local = cell
    local.value = next
    return local.value
}

func replaceRef<T>(cell: RefCell<T>, next: T): T {
    return cell.replace(next)
}

main() {
    let pair = replace<Pair>(Cell<Pair>(Pair(1, 2)), Pair(3, 4))
    let pair2 = replaceRef<Pair>(RefCell<Pair>(Pair(5, 6)), Pair(7, 8))
    println(pair.a + pair.b + pair2.a + pair2.b)
}
