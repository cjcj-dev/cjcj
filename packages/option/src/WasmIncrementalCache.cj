package cjcj::option

import std.core.Option as CoreOption
import std.fs.File

// The wasm incremental cache namespace is the toolchain identity that the SDK
// producer (ci/wasm-sdk-overlay.mjs) writes to
// $CANGJIE_HOME/lib/<target>/wasm-toolchain.id: one line, a digest over cjc,
// opt, llc, wasm-ld, the runtime archive and the std archives of that SDK.
// Objects produced by another toolchain (another managed ABI generation) are
// therefore never reused. This is a build cache key, not a runtime handshake;
// it is host independent and survives relocation of the SDK.
internal func GetWasmToolchainIdentity(cangjieHome: String, targetDir: String): CoreOption<String> {
    if (cangjieHome.isEmpty()) { return None }
    let path = JoinPath(JoinPath(JoinPath(cangjieHome, "lib"), targetDir), "wasm-toolchain.id")
    let text = try {
        String.fromUtf8(File.readFrom(path)).trimAscii()
    } catch (_: Exception) {
        return None
    }
    if (text.isEmpty() || text.size > 128) { return None }
    for (b in text.toArray()) {
        let ok = (b >= b'0' && b <= b'9') || (b >= b'a' && b <= b'z') || (b >= b'A' && b <= b'Z') || b == b'-' ||
            b == b'_' || b == b'.'
        if (!ok) { return None }
    }
    return Some(text)
}
