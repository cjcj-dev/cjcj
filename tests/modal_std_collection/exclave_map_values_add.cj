package modalcollmapvalues

import std.collection.*

// std.unicode / flatbuffers shape: the exclave HashMap.mapValues (hash_map.cj:1686) instantiated
// with a concrete key type calls `newMap.add(key, nv)` on a `HashMap<K, R> @local!`.
main(): Int64 {
    let m: HashMap<UInt32, String> @local! = HashMap<UInt32, String>() @local!
    m.add(7u32, "abc")
    let n = m.mapValues<Int64>({ v => v.size })
    match (n.get(7u32)) {
        case Some(x) => if (x == 3) { 0 } else { 1 }
        case None => 2
    }
}
