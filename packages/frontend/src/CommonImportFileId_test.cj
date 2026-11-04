package cjcj::frontend

import cjcj::ast.*
import cjcj::option.OutputMode
import std.env.getVariable
import std.fs.File as FSFile
import std.fs.Directory as FSDirectory
import std.fs.removeIfExists
import std.unittest.*
import std.unittest.testmacro.*

private func ImportFileIdCompiler(paths: Array<String>, output: String, commonCjo!: String = "",
    ordinary!: Bool = false): CompilerInstance {
    let invocation = CompilerInvocation()
    let opts = invocation.globalOptions
    opts.cangjieHome = getVariable("CANGJIE_HOME").getOrThrow()
    opts.executablePath = opts.cangjieHome + "/bin/cjc"
    opts.outputMode = if (ordinary) { OutputMode.STATIC_LIB } else { OutputMode.CHIR }
    opts.output = output + "/"
    opts.disableCodeGen = true
    opts.SetCompilationCachedPath()
    opts.UpdateCachedDirName("default")
    for (p in paths) { opts.srcFiles.add(p) }
    if (!commonCjo.isEmpty()) { opts.commonPartCjos.add(commonCjo) }
    let ci = CompilerInstance(invocation, DiagnosticEngine())
    ci.buildTrie = false
    return ci
}

private func ExpectImportFileIds(pkg: Package, common: Bool): Unit {
    var count = 0
    for (file in pkg.files) {
        if (file.TestAttr(Attribute.FROM_COMMON_PART) != common) { continue }
        for (spec in file.imports) {
            let name = spec.content.GetImportedPackageNameWithIsDecl()
            if (name != "std.math" && name != "std.collection") { continue }
            count++
            println("IMPORT_FILE_ID_TARGET common=${common} file=${file.fileName} actual=${spec.begin.fileID} expected=${file.begin.fileID}")
            @Expect(spec.begin.fileID, file.begin.fileID)
            @Expect(spec.end.fileID, file.begin.fileID)
            @Expect(spec.begin.fileID != 0u64)
            @Expect(spec.curFile.getOrThrow(), file)
        }
    }
    @Expect(count, 4)
}

@Test
public class CommonImportFileIdTest {
    @TestCase
    public func PublicCommonCompileAndOrdinaryCjoControl(): Unit {
        let root = FSDirectory.createTemp(".").toString()
        try {
            for (name in ["common", "ordinary", "specific", "use"]) { FSDirectory.create(root + "/" + name) }
            for ((name, functionName) in [("a", "left"), ("b", "right")]) {
                let imports = "\nimport std.math.*\nimport std.collection.*\n"
                FSFile.writeTo(root + "/common/" + name + ".cj",
                    ("package commonidfixture" + imports + "public common func " + functionName + "(): Int64\n").toArray())
                FSFile.writeTo(root + "/ordinary/" + name + ".cj",
                    ("package ordinaryidfixture" + imports + "public func " + functionName + "(): Int64 { 1 }\n").toArray())
            }
            let common = ImportFileIdCompiler([root + "/common/a.cj", root + "/common/b.cj"], root + "/common")
            @Assert(common.Compile(stage: CompileStage.SAVE_CJO))
            FSFile.writeTo(root + "/specific/main.cj", ("package commonidfixture\n" +
                "public specific func left(): Int64 { 1 }\npublic specific func right(): Int64 { 2 }\n").toArray())
            let specific = ImportFileIdCompiler([root + "/specific/main.cj"], root + "/specific",
                commonCjo: root + "/common/commonidfixture.cjo")
            @Assert(specific.Compile(stage: CompileStage.IMPORT_PACKAGE))
            ExpectImportFileIds(specific.GetSourcePackages()[0], true)

            let ordinary = ImportFileIdCompiler([root + "/ordinary/a.cj", root + "/ordinary/b.cj"],
                root + "/ordinary", ordinary: true)
            @Assert(ordinary.Compile(stage: CompileStage.SAVE_CJO))
            FSFile.writeTo(root + "/use/main.cj", "package ordinaryuse\nimport ordinaryidfixture.*\n".toArray())
            let consumer = ImportFileIdCompiler([root + "/use/main.cj"], root + "/use", ordinary: true)
            consumer.invocation.globalOptions.importPaths.add(root + "/ordinary")
            @Assert(consumer.Compile(stage: CompileStage.IMPORT_PACKAGE))
            ExpectImportFileIds(consumer.importManager.getOrThrow().GetPackage("ordinaryidfixture").getOrThrow(), false)
        } finally { let _ = removeIfExists(root, recursive: true) }
    }
}
