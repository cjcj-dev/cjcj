package modalcollclassctor

// A class constructor carries an implicit `super()` the compiler adds before the written body;
// a body that is only `exclave { ... }` is still a constructor body enclosed in exclave.
class Node {
    var payload: Int64 = 0
    public init() {}
    public init(this @local!) { exclave { payload = 7 } }
}

main(): Int64 {
    let n = Node() @local!
    let m = Node()
    if (m.payload == 0) { 0 } else { 1 }
}
