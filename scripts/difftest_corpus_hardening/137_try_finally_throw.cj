class MyError <: Exception {
    public init() {
        super("boom")
    }
}

func run(): Unit {
    try {
        println("before throw")
        throw MyError()
    } catch (e: MyError) {
        println("caught")
    } finally {
        println("finally")
    }
}

main() {
    run()
    println("after")
}
