// Positive signal control, never part of the normal corpus.
foreign func abort(): Unit
main(): Int64 {
    println("G10_INJECTED_FAILURE")
    unsafe { abort() }
    return 0
}
