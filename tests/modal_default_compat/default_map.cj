import std.collection.*

main(): Int64 {
    let m = HashMap<String, Int64>()
    m.add("a", 1)
    var acc = ""
    for ((k, v) in m) {
        acc = acc + "${k}=${v};"
    }
    println(acc)
    if (acc == "a=1;") { 0 } else { 2 }
}
