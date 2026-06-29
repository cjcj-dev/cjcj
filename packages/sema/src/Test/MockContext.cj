package cangjie_compiler::sema.Test

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::mangle.{BaseMangler, MangleAstAdapter, ManglerContext}
import cangjie_compiler::utils.CJC_ASSERT_WITH_MSG

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
