package cjcj::chir

public class NoSideEffectMarker {
    private let functionWhiteList: Array<FuncInfo> = [
        FuncInfo("hashCode", "Int64", Array<String>(), "Int64", "std.core"),
        FuncInfo("hashCode", "Float64", Array<String>(), "Int64", "std.core"),
        FuncInfo("compare", "String", ["String"], "Ordering", "std.core"),
        FuncInfo("==", "String", ["String"], "Bool", "std.core"),
        FuncInfo("compare", "Ordering", ["Ordering"], "Ordering", "std.core"),
        FuncInfo("round", "", ["Float64"], "Float64", "std.math"),
        FuncInfo("round", "", ["Float32"], "Float32", "std.math"),
        FuncInfo("round", "", ["Float16"], "Float16", "std.math")
    ]

    public init() {}

    public func RunOnPackage(pkg: Package): Int64 {
        var marked: Int64 = 0
        for (fn in pkg.GetGlobalFuncsWithBody()) {
            if (MarkFunction(fn)) {
                marked++
            }
        }
        for (fn in pkg.GetGlobalFuncsWithoutBody()) {
            if (MarkFunction(fn)) {
                marked++
            }
        }
        return marked
    }

    public func MarkFunction(fn: Function): Bool {
        for (funcInfo in functionWhiteList) {
            if (IsExpectedFunction(fn, funcInfo)) {
                if (!fn.TestAttr(Attribute.NO_SIDE_EFFECT)) {
                    fn.EnableAttr(Attribute.NO_SIDE_EFFECT)
                    return true
                }
                return false
            }
        }
        return false
    }
}
