package cjcj::frontend

import cjcj::ast.*
import cjcj::basic.Position
import std.unittest.*
import std.unittest.testmacro.*

private func DependencyOrderFile(name: String, fileID: UInt64, copies: Int64): File {
    let file = File()
    file.fileName = name
    file.filePath = "/fixture/" + name
    file.begin = Position(fileID, 1, 1)
    for (_ in 0..copies) {
        let spec = ImportSpec()
        spec.content.kind = ImportKind.IMPORT_ALL
        spec.content.prefixPaths.add("dependency")
        spec.content.identifier = Identifier("*")
        spec.begin = Position(fileID, 2, 1)
        spec.end = Position(fileID, 2, 20)
        spec.curFile = Some(file)
        file.imports.add(spec)
    }
    return file
}

@Test
public class PkgDepInfoOrderTest {
    @TestCase
    public func CanonicalFragmentsPreserveDuplicates(): Unit {
        let invocation = CompilerInvocation()
        invocation.globalOptions.implicitPrelude = false
        let ci = CompilerInstance(invocation, DiagnosticEngine())
        let manager = ci.importManager.getOrThrow()
        // Both files have identical line/column positions. File order and IDs
        // deliberately disagree with the serialized filenames.
        for (exportCJO in [false, true]) {
            var first = ""
            for (reverse in [false, true]) {
                let pkg = Package("orderfixture")
                let a = DependencyOrderFile("a.cj", if (reverse) { 1u64 } else { 90u64 }, 1)
                let z = DependencyOrderFile("z.cj", if (reverse) { 90u64 } else { 1u64 }, 2)
                pkg.files.add(if (reverse) { a } else { z })
                pkg.files.add(if (reverse) { z } else { a })
                let json = manager.GeneratePkgDepInfo(pkg, exportCJO: exportCJO)
                let prefix = if (exportCJO) { "" } else { "/fixture/" }
                let aFragment = "{\"file\":\"" + prefix + "a.cj\",\"begin\":{\"line\":2,\"column\":1}," +
                    "\"end\":{\"line\":2,\"column\":20}}"
                let zFragment = aFragment.replace("a.cj", "z.cj")
                println("PKG_DEP_TARGET exportCJO=${exportCJO} reverse=${reverse}")
                @Expect(json.contains("\"imports\":[" + aFragment + "," + zFragment + "," + zFragment + "]"))
                if (reverse) { @Expect(json, first) } else { first = json }
                // Serialization must not reorder the source import containers.
                @Expect(pkg.files[0].fileName, if (reverse) { "a.cj" } else { "z.cj" })
                @Expect(z.imports.size, 2)
            }
        }
    }
}
