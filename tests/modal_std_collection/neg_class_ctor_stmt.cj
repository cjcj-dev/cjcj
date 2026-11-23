package modalcollclassctorneg

class Node {
    var payload: Int64 = 0
    public init() {}
    // A written statement outside the exclave is still rejected.
    public init(this @local!) { payload = 1
        exclave {} }
}

main(): Int64 { 0 }
