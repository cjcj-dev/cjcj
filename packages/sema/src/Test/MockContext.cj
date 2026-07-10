package cjcj::sema.Test

import std.collection.*
import cjcj::ast.*
import cjcj::mangle.{BaseMangler, MangleAstAdapter, ManglerContext}
import cjcj::utils.CJC_ASSERT_WITH_MSG

public class MockContext {
    public let mangler: BaseMangler = BaseMangler()
    private let manglerCtxs: HashMap<String, ManglerContext> = HashMap<String, ManglerContext>()

    public init() {}

    ~init() {
        for ((pkgName, _) in manglerCtxs) {
            mangler.manglerCtxTable.remove(pkgName)
        }
    }

    public func PrepareManglerContext(pkg: Package): Unit {
        let pkgName = ManglerContext.ReduceUnitTestPackageName(pkg.fullPackageName)
        CJC_ASSERT_WITH_MSG(!manglerCtxs.contains(pkgName), "Prepare each package only once")
        manglerCtxs[pkgName] = mangler.PrepareContextForPackage(MangleAstAdapter().ConvertPackage(pkg))
    }
}
