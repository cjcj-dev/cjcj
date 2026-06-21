import pkgSig.*
import std.collection.*

main() {
    let buffer = ArrayList<UInt8>()
    let failedReason = FailureReason()
    if (fill("x", buffer, failedReason)) {
        println(Int64(buffer[0]))
    } else {
        println(0)
    }
}
