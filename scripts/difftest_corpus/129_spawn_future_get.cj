main() {
    let f = spawn { => 21 * 2 }
    println(f.get())
}
