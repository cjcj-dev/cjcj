// Exercise the headerless receiver on both stack and managed-field callers.
struct CopybackBox<T> {
    public var first: Int64
    public var value: T
    public var last: Int64
    public init(value: T, fail: Bool) {
        first = 11
        this.value = value
        last = 37
        if (fail) { throw Exception("copyback constructor control") }
    }
    public mut func change(value: T, fail: Bool): Unit {
        first = 41
        this.value = value
        last = 67
        if (fail) { throw Exception("copyback method control") }
    }
}
class CopybackHolder<T> {
    public var box: CopybackBox<T>
    public init(value: T) { box = CopybackBox<T>(value, false) }
    public func change(value: T): Unit { box.change(value, false) }
    public func changeInvoke(value: T, fail: Bool): Bool {
        try { box.change(value, fail); return true }
        catch (e: Exception) { println("UNEXPECTED FIELD ${e.message}"); return false }
    }
}
func report(name: String, ok: Bool): Int64 {
    if (ok) { println("PASS ${name}"); return 0 }
    println("FAIL ${name}")
    return 1
}
func rawCall(): Int64 {
    var value = CopybackBox<Int64>(23, false)
    var errors = report("raw-call-ctor", value.first == 11 && value.value == 23 && value.last == 37)
    value.change(53, false)
    errors += report("raw-call-mut", value.first == 41 && value.value == 53 && value.last == 67)
    return errors
}
func rawInvoke(fail: Bool): Int64 {
    try {
        var value = CopybackBox<Int64>(29, fail)
        var errors = report("raw-invoke-ctor", value.first == 11 && value.value == 29 && value.last == 37)
        value.change(59, fail)
        errors += report("raw-invoke-mut", value.first == 41 && value.value == 59 && value.last == 67)
        return errors
    } catch (e: Exception) { println("UNEXPECTED ${e.message}"); return 1 }
}
func referenceControl(): Int64 {
    var value = CopybackBox<String>("before", false)
    var errors = report("ref-ctor", value.first == 11 && value.value == "before" && value.last == 37)
    value.change("after", false)
    errors += report("ref-mut", value.first == 41 && value.value == "after" && value.last == 67)
    return errors
}
func managedFieldControl(fail: Bool): Int64 {
    let holder = CopybackHolder<Int64>(31)
    var errors = report("field-ctor", holder.box.first == 11 && holder.box.value == 31 && holder.box.last == 37)
    holder.change(61)
    errors += report("field-mut", holder.box.first == 41 && holder.box.value == 61 && holder.box.last == 67)
    let returned = holder.changeInvoke(83, fail)
    errors += report("field-invoke", returned && holder.box.first == 41 && holder.box.value == 83 && holder.box.last == 67)
    return errors
}
func managedReferenceControl(fail: Bool): Int64 {
    let holder = CopybackHolder<String>("before")
    var errors = report("field-ref-ctor", holder.box.first == 11 && holder.box.value == "before" && holder.box.last == 37)
    holder.change("after")
    errors += report("field-ref-mut", holder.box.first == 41 && holder.box.value == "after" && holder.box.last == 67)
    let returned = holder.changeInvoke("invoke", fail)
    errors += report("field-ref-invoke", returned && holder.box.first == 41 && holder.box.value == "invoke" && holder.box.last == 67)
    return errors
}
func unwindControl(): Int64 {
    var caught = false
    try { let value = CopybackBox<Int64>(71, true); println(value.first) }
    catch (e: Exception) { caught = e.message == "copyback constructor control" }
    return report("unwind-control", caught)
}
main(args: Array<String>): Int64 {
    // Each control runs in a separate process so a corrupted raw receiver
    // cannot hide the reference or exception-control results.
    for (arg in args) {
        if (arg == "raw-call") { return rawCall() }
        if (arg == "raw-invoke") { return rawInvoke(args.size == 123) }
        if (arg == "reference") { return referenceControl() }
        if (arg == "field") { return managedFieldControl(args.size == 123) }
        if (arg == "field-reference") { return managedReferenceControl(args.size == 123) }
        if (arg == "unwind") { return unwindControl() }
    }
    println("MISSING COPYBACK CASE")
    return 2
}
