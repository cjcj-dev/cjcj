// Closures plus std.io / std.fs / std.regex / std.collection without --enable-local-mode.
import std.collection.*
import std.io.*
import std.fs.*
import std.regex.*

main(): Int64 {
    var counter = 0
    func bump(by: Int64): Int64 {
        counter += by
        counter
    }
    bump(2)
    bump(3)
    let squares = ArrayList<Int64>()
    for (i in 1..=3) { squares.add(i * i) }
    let doubled = squares |> map({ v: Int64 => v * 2 }) |> collectArray
    let buf = ByteBuffer()
    buf.write("io".toArray())
    let fromIo = String.fromUtf8(buf.bytes())
    let name = Path("/tmp/dir/b.txt").fileName
    let re = Regex("a+b")
    let hit = re.matches("aaab")
    let set = HashSet<String>(["k", "k", "j"])
    let line = "${counter} ${doubled} ${fromIo} ${name} ${hit} ${set.size}"
    println(line)
    if (line == "5 [2, 8, 18] io b.txt true 2") { 0 } else { 5 }
}
