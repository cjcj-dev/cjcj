package samepkg

public open class Base {
    public open func kept(): Int64 {
        return 1
    }
}

extend Base {
    func hidden(): Int64 {
        return 2
    }
}

public class Child <: Base {
    public override func kept(): Int64 {
        return 4
    }

    public func hidden(): Int64 {
        return 3
    }
}

main() {
    let c = Child()
    println(c.kept())
    println(c.hidden())
}
