func collect(enabled: Bool): Unit {
    if (!enabled) {
        return
    }
    println("collected")
}

main() {
    collect(false)
    collect(true)
}
