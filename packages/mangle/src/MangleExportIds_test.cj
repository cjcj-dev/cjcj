package cjcj::mangle

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::ast.*

private func ExportIdFixture(): (Package, ArrayList<Decl>) {
    let pkg = Package("export_ids")
    let file = File()
    pkg.files.add(file)
    let declarations = ArrayList<Decl>()
    for (index in 0..16) {
        let owner = StructDecl()
        owner.identifier = SrcIdentifier("Owner${index}")
        owner.fullPackageName = pkg.fullPackageName
        owner.curFile = file
        owner.EnableAttr(Attribute.GLOBAL)
        owner.SetTy(StructTy("Owner${index}", owner, Array<Ty>()))
        let body = StructBody()
        owner.body = body
        file.decls.add(owner)
        declarations.add(owner)
        for (member in 0..4) {
            let decl = VarDecl()
            decl.identifier = SrcIdentifier("field${member}")
            decl.fullPackageName = pkg.fullPackageName
            decl.curFile = file
            decl.outerDecl = owner
            decl.SetTy(Ty(TypeKind.TYPE_INT64))
            // Also visit each member as a global root, exercising overlap between
            // recursive member writes and separately collected source roots.
            decl.EnableAttr(Attribute.GLOBAL)
            body.decls.add(decl)
            declarations.add(decl)
        }
    }
    return (pkg, declarations)
}

@Test
class MangleExportIdsTest {
    @TestCase
    func ParallelIdsMatchSerialWithOverlappingMemberRoots(): Unit {
        let (pkg, declarations) = ExportIdFixture()
        BaseMangler().MangleExportIds(pkg, threadNum: 1)
        let expected = ArrayList<String>()
        for (decl in declarations) {
            @Expect(!decl.exportId.isEmpty())
            expected.add(decl.exportId)
            decl.exportId = ""
        }
        BaseMangler().MangleExportIds(pkg, threadNum: 4)
        for (index in 0..declarations.size) {
            @Expect(declarations[index].exportId, expected[index])
        }
    }
}
