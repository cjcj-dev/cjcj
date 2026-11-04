import std.sync.*
main(): Int64 {
    let completed = AtomicInt64(0)
    try {
        spawn { => completed.store(7) }
        let observed = spawn { => 42 }
        if (observed.get() != 42) { return 1 }
    } catch (e: Exception) { return 2 }
    while (completed.load() == 0) { }
    // Exceptions in a closure must still reach an observed Future.get().
    try {
        let failed = spawn { => throw Exception("future-error") }
        failed.get()
        return 3
    } catch (e: Exception) { }
    println("FUTURE_EXCEPTION_OK")
    return 0
}
