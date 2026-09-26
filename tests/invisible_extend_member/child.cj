package userpkg

import basepkg.*

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
