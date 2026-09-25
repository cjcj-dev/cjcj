package basepkg

public open class Base {
    public open func kept(): Int64 {
        return 1
    }
}

extend Base {
    func hidden(): Int64 {
        return 2
    }

    public func shown(): Int64 {
        return 9
    }
}
