import cjcj::flatbuffers.*
import std.fs.*

// Link against the product flatbuffers archive. Valgrind checks native ownership;
// the byte assertions below independently check release and the file consumer.
main(): Int64 {
    let path = "flatbuffer-native-lifetime.bin"
    let builder = FlatBufferBuilder()
    // Exceed the initial capacity so the allocation lifetime check also covers growth.
    let root = builder.CreateString(String.fromUtf8(Array<UInt8>(4096, repeat: 110u8)))
    builder.Finish(root)
    let expected = builder.GetBufferArray()
    try (detached = builder.Release()) {
        let replacement = builder.CreateString("replacement allocation")
        builder.Finish(replacement)
        builder.close()
        let actual = Array<UInt8>(detached.size,
            { i => unsafe { detached.GetBufferPointer().read(i) } })
        println("ASSERT released bytes remain owned")
        if (actual != expected) { return 1 }
        try {
            WriteFlatBufferToFile(path, detached.GetBufferPointer(), detached.size)
            let disk = File.readFrom(path)
            println("ASSERT native file exact bytes")
            if (disk != expected) { return 2 }
        } finally {
            let _ = removeIfExists(path)
        }
        var rejectedDirectory = false
        try {
            WriteFlatBufferToFile(".", detached.GetBufferPointer(), detached.size)
        } catch (_: Exception) {
            rejectedDirectory = true
        }
        println("ASSERT native file open failure propagated")
        if (!rejectedDirectory) { return 3 }
    }
    try {
        try (exceptional = FlatBufferBuilder()) {
            let _ = exceptional.CreateString("exceptional allocation")
            throw Exception("exit scope")
        }
    } catch (_: Exception) {
        ()
    }
    println("ASSERT native ownership scenarios completed")
    return 0
}
