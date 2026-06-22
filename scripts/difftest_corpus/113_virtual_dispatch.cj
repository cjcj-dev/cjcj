public open class Base {
    public open func greet(): Int64 {
        return 10
    }

    public open func inherited(): Int64 {
        return 30
    }
}

public class Sub <: Base {
    public override func greet(): Int64 {
        return 20
    }
}

open class A {
    public open func f(): Int64 {
        return 1
    }

    public func g(): Int64 {
        return f() + 100
    }
}

class B2 <: A {
    public override func f(): Int64 {
        return 2
    }
}

open class Animal {
    public open func sound(): String {
        return "?"
    }

    public open func legs(): Int64 {
        return 4
    }
}

open class Dog <: Animal {
    public override func sound(): String {
        return "woof"
    }
}

class Puppy <: Dog {
    public override func legs(): Int64 {
        return 4
    }
}

main() {
    let base = Base()
    let sub = Sub()
    let upcast: Base = Sub()
    let selfCall: A = B2()
    let animal: Animal = Puppy()
    println(base.greet())
    println(sub.greet())
    println(sub.inherited())
    println(upcast.greet())
    println(A().g())
    println(selfCall.g())
    println(animal.sound())
    println(animal.legs())
}
