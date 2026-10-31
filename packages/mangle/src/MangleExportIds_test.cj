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

private func AddGenericExportFixture(pkg: Package, name: String): (InterfaceDecl, GenericParamDecl) {
    let owner = InterfaceDecl()
    owner.identifier = SrcIdentifier(name)
    owner.fullPackageName = pkg.fullPackageName
    owner.curFile = pkg.files[0]
    owner.EnableAttr(Attribute.GLOBAL)
    owner.EnableAttr(Attribute.GENERIC)
    owner.body = InterfaceBody()
    let parameter = GenericParamDecl()
    parameter.identifier = SrcIdentifier("Element${name}")
    parameter.outerDecl = owner
    parameter.curFile = pkg.files[0]
    parameter.SetTy(GenericsTy(parameter.identifier.Val(), parameter))
    let generic = Generic()
    generic.typeParameters.add(parameter)
    owner.generic = generic
    owner.SetTy(InterfaceTy(name, owner, [parameter.GetTy().getOrThrow()]))
    pkg.files[0].decls.add(owner)
    return (owner, parameter)
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

    @TestCase
    func ParallelGenericIdsReadTheirOwnersCompletedIds(): Unit {
        let pkg = Package("generic_export_ids")
        pkg.files.add(File())
        let declarations = ArrayList<Decl>()
        for (index in 0..16) {
            let (owner, parameter) = AddGenericExportFixture(pkg, "Owner${index}")
            declarations.add(owner)
            declarations.add(parameter)
        }
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

    @TestCase
    func ParallelExportFailureKeepsSourceOrderAndDrainsIndependentWork(): Unit {
        let pkg = Package("failed_export_ids")
        pkg.files.add(File())
        let (_, first) = AddGenericExportFixture(pkg, "First")
        let (_, second) = AddGenericExportFixture(pkg, "Second")
        let (survivor, parameter) = AddGenericExportFixture(pkg, "Survivor")
        first.outerDecl = None
        second.outerDecl = None
        var serialFailure = ""
        try { BaseMangler().MangleExportIds(pkg, threadNum: 1) } catch (e: Exception) {
            serialFailure = e.message
        }
        @Expect(serialFailure, "Generic parameter has no outer declaration: ElementFirst")
        @Expect(survivor.exportId.isEmpty())
        var parallelFailure = ""
        try { BaseMangler().MangleExportIds(pkg, threadNum: 4) } catch (e: Exception) {
            parallelFailure = e.message
        }
        @Expect(parallelFailure, serialFailure)
        // The throw happens only after the independent component has completed.
        @Expect(!survivor.exportId.isEmpty())
        @Expect(!parameter.exportId.isEmpty())
    }
}
