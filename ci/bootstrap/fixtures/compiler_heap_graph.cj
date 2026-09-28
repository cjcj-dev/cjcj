package known_chir
import cjcj::chir.{Function, FuncType, Type, UnitType}
import cjcj::ast.{RefExpr, SrcIdentifier}
import std.collection.ArrayList
import std.runtime.*
import std.ref.*
foreign { func CJ_MCC_InvokeGC(sync: Bool): Unit }
class Parent {
    public let child: RefExpr
    public init(child: RefExpr) { this.child = child }
}
func MakeName(): String {
    let b = StringBuilder()
    b.append("function-")
    b.append(71)
    return b.toString()
}
let weakNodes = ArrayList<WeakRef<RefExpr>>()
func LiveNodes(): Int64 {
    var count: Int64 = 0
    for (node in weakNodes) { if (node.value.isSome()) { count++ } }
    return count
}
func MakeGarbage(): Unit {
    let dead = Array<RefExpr>(1024, { _ => RefExpr() })
    for (node in dead) { weakNodes.add(WeakRef<RefExpr>(node, CleanupPolicy.EAGER)) }
    println("WEAK_BEFORE=" + LiveNodes().toString())
    println("ALLOCATED=" + dead.size.toString())
}
let function: Function = Function(FuncType(ArrayList<Type>(), UnitType()), MakeName(), MakeName(), MakeName(), MakeName())
let parent: Parent = Parent(RefExpr(SrcIdentifier("live-child")))
main(args: Array<String>): Int64 {
    weakNodes.add(WeakRef<RefExpr>(parent.child, CleanupPolicy.EAGER))
    if (args.size > 0 && args[0] == "post") {
        MakeGarbage()
        sleep(Duration.second)
        gc(heavy: true)
        sleep(Duration.second)
        if (getGCCount() == 0) { return 2 }
    }
    println("WEAK_AFTER=" + LiveNodes().toString())
    if (LiveNodes() != 1) { return 4 }
    println("GC_COUNT=" + getGCCount().toString())
    println("READY")
    sleep(Duration.second * 8)
    if (function.GetIdentifier() != "function-71" || parent.child.ToString() != "live-child") {
        println("TARGET_VALUE_FAIL")
        return 3
    }
    println("TARGET_VALUE_PASS function=function-71 child=live-child")
    return 0
}
