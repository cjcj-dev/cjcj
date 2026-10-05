package cjcj::compiler_unittest

import std.collection.*
import std.env.getVariable
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::ast.*
import cjcj::basic.Position
import cjcj::driver.HostTripleInfo
import cjcj::frontend.*
import cjcj::option.{OutputMode, OptimizationLevel}
import cjcj::utils.FileUtil

private let cloneMarker = "698_array_clone_comment"
private let cloneSource = "package clone_metadata\npublic func make<T>(x: T): Array<T> {\n    return [\n        x\n        /*698_array_clone_comment*/\n    ]\n}\npublic func use(): Array<Int64> { return make<Int64>(1) }\n"

private func samePosition(a: Position, b: Position): Bool {
    return a.fileID == b.fileID && a.line == b.line && a.column == b.column
}

private func collectArrays(decl: FuncDecl): ArrayList<ArrayLit> {
    let arrays = ArrayList<ArrayLit>()
    let _ = Walker(decl, visitPre: Some({ node: Node =>
        if (let Some(array) <- (node as ArrayLit)) { arrays.add(array) }
        VisitAction.WALK_CHILDREN
    }), walkExprDesugar: false).Walk()
    return arrays
}

// Keep grouping, token contents and both token positions in the observed value.
private func commentSnapshot(groups: ArrayList<CommentGroup>): String {
    var out = ""
    for (group in groups) {
        out += "["
        for (comment in group.cms) {
            out += comment.ToString() + comment.info.Begin().ToString() + comment.info.End().ToString()
        }
        out += "]"
    }
    return out
}

private func allComments(node: Node): String {
    return "leading=" + commentSnapshot(node.comments.leadingComments) +
        "inner=" + commentSnapshot(node.comments.innerComments) +
        "trailing=" + commentSnapshot(node.comments.trailingComments)
}

@Test
public class ArrayCloneMetadataTest {
    @TestCase
    public func preservesArrayCloneMetadata(): Unit {
        let dir = getVariable("ARRAY_CLONE_TEST_ROOT").getOrThrow()
        let _ = FileUtil.CreateDirs(dir + "/")
        let path = dir + "/clone_metadata.cj"
        @Assert(FileUtil.WriteToFile(path, cloneSource))
        let invocation = CompilerInvocation()
        let opts = invocation.globalOptions
        let home = getVariable("CANGJIE_HOME").getOrThrow()
        opts.srcFiles.add(path)
        opts.cangjieHome = home
        opts.executablePath = home + "/bin/cjc"
        opts.host = HostTripleInfo()
        opts.target = HostTripleInfo()
        opts.outputMode = OutputMode.STATIC_LIB
        opts.output = dir + "/clone_metadata.a"
        opts.disableCodeGen = true
        opts.enableAddCommentToAst = true
        opts.optimizationLevel = OptimizationLevel.O2
        opts.enIncrementalCompilation = false
        opts.SetCompilationCachedPath()
        opts.UpdateCachedDirName("clone_metadata")
        let diag = DiagnosticEngine()
        let instance = CompilerInstance(invocation, diag)
        instance.buildTrie = false
        let ok = instance.Compile(stage: CompileStage.GENERIC_INSTANTIATION)
        let imported = instance.importManager.getOrThrow().IsSourceCodeImported()
        println("QUALIFY compile=${ok} errors=${diag.GetErrorCount()} sourceImported=${imported}")
        @Assert(ok && diag.GetErrorCount() == 0 && imported)
        let packages = instance.GetSourcePackages()
        println("QUALIFY packages=${packages.size}")
        @Assert(packages.size == 1)
        let pkg = packages[0]
        let originals = ArrayList<FuncDecl>()
        for (file in pkg.files) {
            for (decl in file.decls) {
                if (let Some(funcDecl) <- (decl as FuncDecl)) {
                    if (funcDecl.identifier.Val() == "make") { originals.add(funcDecl) }
                }
            }
        }
        println("QUALIFY originalCount=${originals.size}")
        @Assert(originals.size == 1)
        let original = originals[0]
        let clones = ArrayList<FuncDecl>()
        for (decl in pkg.genericInstantiatedDecls) {
            if (let Some(funcDecl) <- (decl as FuncDecl)) {
                if (let Some(genericDecl) <- funcDecl.genericDecl) {
                    if (genericDecl.objectId == original.objectId &&
                        funcDecl.TestAttr(Attribute.GENERIC_INSTANTIATED)) { clones.add(funcDecl) }
                }
            }
        }
        let sourceArrays = collectArrays(original)
        println("QUALIFY cloneCount=${clones.size} sourceArrays=${sourceArrays.size} originalId=${original.objectId}")
        @Assert(clones.size == 1 && sourceArrays.size == 1)
        let cloneArrays = collectArrays(clones[0])
        println("QUALIFY cloneArrays=${cloneArrays.size} cloneDeclId=${clones[0].objectId}")
        @Assert(cloneArrays.size == 1)
        let source = sourceArrays[0]
        let clone = cloneArrays[0]
        var markerCount: Int64 = 0
        var realToken = true
        for (group in source.comments.innerComments) {
            for (comment in group.cms) {
                if (comment.info.Value().contains(cloneMarker)) {
                    markerCount++
                    realToken = realToken && comment.info.Value() == "/*698_array_clone_comment*/" &&
                        comment.info.Begin().fileID == source.begin.fileID &&
                        comment.info.Begin().line == 5 && comment.info.Begin().column == 9 &&
                        comment.info.End().line == 5 && comment.info.End().column == 36
                }
            }
        }
        println("QUALIFY templateMarkerCount=${markerCount} realToken=${realToken} comments=${allComments(source)}")
        @Assert(markerCount == 1 && realToken)
        let sourceTy = source.GetTy().getOrThrow()
        let cloneTy = clone.GetTy().getOrThrow()
        println("OBSERVE sourceArrayId=${source.objectId} cloneArrayId=${clone.objectId} sourceTy=${sourceTy.String()} cloneTy=${cloneTy.String()}")
        var failures: Int64 = 0
        let check = { name: String, passed: Bool =>
            println("ASSERT ${name} ${if (passed) { "PASS" } else { "FAIL" }}")
            if (!passed) { failures++ }
        }
        check("lineage", original.objectId != clones[0].objectId && source.objectId != clone.objectId)
        check("template_position", source.begin.fileID != 0 && source.begin.line == 3 && source.begin.column == 12 &&
            source.end.line == 6 && samePosition(source.begin, source.leftSquarePos) &&
            source.rightSquarePos.line == 6 && source.rightSquarePos.column == 5)
        check("clone_position", samePosition(source.begin, clone.begin) && samePosition(source.end, clone.end) &&
            samePosition(source.leftSquarePos, clone.leftSquarePos) && samePosition(source.rightSquarePos, clone.rightSquarePos))
        check("template_type", sourceTy.IsArray() && sourceTy.typeArgs.size == 1 &&
            sourceTy.typeArgs[0].kind == TypeKind.TYPE_GENERICS && sourceTy.typeArgs[0].name == "T")
        check("clone_type", cloneTy.IsArray() && cloneTy.typeArgs.size == 1 &&
            cloneTy.typeArgs[0].kind == TypeKind.TYPE_INT64)
        check("children", source.children.size == 1 && clone.children.size == 1 &&
            clone.children[0].TyKind() == TypeKind.TYPE_INT64 &&
            source.children[0].TyKind() == TypeKind.TYPE_GENERICS)
        check("template_marker", PrintNode(source).contains(cloneMarker))
        check("clone_comments", allComments(clone) == allComments(source))
        let rendered = PrintNode(clone)
        println("OBSERVE clonePrint=${rendered}")
        check("clone_print_marker", rendered.contains(cloneMarker))
        @Assert(failures == 0)
    }
}
