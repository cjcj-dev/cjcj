package builder_spawn

main(): Int64 {
    let future = spawn { => 21 * 2 }
    return future.get()
}
