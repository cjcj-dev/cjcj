package builder_head_capture
func capture(value: Int64): () -> Int64 {
    return { => value + 1 }
}
main(): Int64 {
    return capture(40)()
}
