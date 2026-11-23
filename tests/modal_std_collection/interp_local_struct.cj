package modalinterplocal

// std.fs file.cj:160 shape: inside an exclave init, `"${parent}"` interpolates a non-Copyable
// `@local!` struct (Path) and a `String @local!`. The value must be read through
// `toString(this @local?): String @local!` and `append(String @local?)`, not rejected as a
// store of a local value into a plain slot.
struct P <: ToString {
    let raw: String
    init(raw: String) { this.raw = raw }
    exclave init(this @local!, raw: String @local!) { this.raw = raw }
    public func toString(): String { raw }
    public exclave func toString(this @local?): String @local! { raw.toString() }
}

class Opener {
    let n: Int64
    public exclave init(this @local!, path: String @local!) {
        let raw: String @local! = "ab"
        let p: P @local! = P(raw) @local!
        if (path.size > 0) {
            throw Exception("parent '${p}' for ${path} missing")
        }
        n = 1
    }
}

main(): Int64 {
    let plain = P("cd")
    if ("${plain}" != "cd") { return 4 }
    try {
        let x: String @local! = "x"
        let o = Opener(x) @local!
        return if (o.n == 1) { 1 } else { 2 }
    } catch (e: Exception) {
        return if (e.message == "parent 'ab' for x missing") { 0 } else { 3 }
    }
}
