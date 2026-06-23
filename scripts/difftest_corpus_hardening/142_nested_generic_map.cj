import std.collection.*
import std.sort.*

main() {
    let m = HashMap<String, ArrayList<Int64>>()
    let a = ArrayList<Int64>()
    a.add(1)
    a.add(2)
    let b = ArrayList<Int64>()
    b.add(10)
    m["alpha"] = a
    m["beta"] = b

    let keys = ArrayList<String>()
    for (k in m.keys()) {
        keys.add(k)
    }
    // sort keys for deterministic order
    sort(keys)
    for (k in keys) {
        var sum = 0
        for (v in m[k]) {
            sum += v
        }
        println("${k}=${sum}")
    }
}
