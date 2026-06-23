class Handle <: Resource {
    let id: Int64
    var closed: Bool = false

    public init(id: Int64) {
        this.id = id
    }

    public func isClosed(): Bool {
        return closed
    }

    public func close(): Unit {
        closed = true
        println("close ${id}")
    }
}

class MyError <: Exception {
    public init() {
        super("boom")
    }
}

func run(): Unit {
    try (r = Handle(1)) {
        println("body ${r.id}")
        throw MyError()
    } catch (e: MyError) {
        println("caught")
    }
}

main() {
    run()
    println("after")
}
