package hfixh2_341

private var initialized: Int64 = if (true) { 1 } else { 2 }

public func choose(first: Bool, second: Bool): Int64 {
    if (first) {
        if (second) {
            return initialized
        }
        return 2
    }
    return 3
}
