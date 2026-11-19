package cjcj::option

@When[os == "Linux"]
import std.fs.{File, OpenMode}
@When[os == "Linux"]
import cjcj::utils.SipHash

// Cache the actual compiler image, not argv[0] (which might name an SDK
// launcher) or the language version (which is shared by many compilers).
// Fixed-size chunks keep memory bounded and give the same key after relocation.
@When[os == "Linux"]
internal func GetWasmCompilerCacheIdentity(): Option<String> {
    try (file = File("/proc/self/exe", OpenMode.Read)) {
        let buffer = Array<UInt8>(1024 * 1024, repeat: 0u8)
        let chunks = StringBuilder()
        while (true) {
            var size: Int64 = 0
            while (size < buffer.size) {
                let read = file.read(buffer[size..])
                if (read == 0) { break }
                size += read
            }
            if (size == 0) { break }
            chunks.append(size.toString())
            chunks.append(":")
            chunks.append(UInt64ToHex(SipHash.GetHashValue(buffer[..size])))
            chunks.append(":")
        }
        let manifest = chunks.toString()
        return if (manifest.isEmpty()) { None } else { Some(StableHashString(manifest)) }
    } catch (_: Exception) {
        return None
    }
}

// Leave incremental use off when the running image cannot be identified.
@When[os != "Linux"]
internal func GetWasmCompilerCacheIdentity(): Option<String> {
    return None
}
