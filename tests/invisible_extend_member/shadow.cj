package userpkg

import basepkg.*

public class Child <: Base {
    public override func kept(): Int64 {
        return 4
    }

    public func shown(): Int64 {
        return 8
    }
}

main() {
    println(1)
}
