main() {
    let base = 17
    let f = spawn { => base + 25 }
    println(f.get())
}
