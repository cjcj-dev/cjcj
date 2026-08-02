package hfixh2_237

var mutableGlobal: Int64 = 7
let readonlyGlobal: String = "visible-in-debug-info"

public func readGlobals(): Int64 {
    return mutableGlobal + readonlyGlobal.size
}
