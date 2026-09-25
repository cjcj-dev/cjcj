package devirt_throwing_apply

interface Slots {
    func second(): Int64
}

class Impl <: Slots {
    public func second(): Int64 {
        throw Exception()
    }
}

public func chooseThrowing(): Int64 {
    try {
        let receiver: Slots = Impl()
        return receiver.second()
    } catch (e: Exception) {
        return 0
    }
}

main(): Int64 {
    return chooseThrowing()
}
