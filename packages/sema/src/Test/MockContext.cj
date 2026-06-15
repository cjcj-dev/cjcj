package cangjie_compiler::sema.Test

import std.collection.*
import cangjie_compiler::ast.*

public class MockContext {
    public let manglerCtxs: HashSet<String> = HashSet<String>()

    public init() {}

    public func PrepareManglerContext(pkg: Package): Unit {
        let pkgName = ReduceUnitTestPackageName(pkg.fullPackageName)
        if (manglerCtxs.contains(pkgName)) {
            return
        }
        manglerCtxs.add(pkgName)
    }

    public func Clear(): Unit {
        manglerCtxs.clear()
    }
}

public func ReduceUnitTestPackageName(pkgName: String): String {
    let suffix = "$test"
    if (pkgName.endsWith(suffix)) {
        return pkgName[0..pkgName.size - suffix.size]
    }
    return pkgName
}
