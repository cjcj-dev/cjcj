package cjcj::sema.resolver_tests

import std.collection.*
import std.fs.{Directory, removeIfExists}
import std.fs.File as FSFile
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::ast.*
import cjcj::compiler_unittest.*
import cjcj::frontend.CompileStage
import cjcj::option.OutputMode

@Test
public class FrozenModalInstantiationTest {
    private func WithImportedBox(check: (String) -> Unit): Unit {
        let library = CompileResolverSource("""
            package frozenmodals

            public class FrozenBox<T> {
                public init() {}

                @Frozen
                public func plain(): Int64 {
                    let value: Int64 @local! = 41
                    this.required(value) + 1
                }

                @Frozen
                public func required(value: Int64 @local!): Int64 { value + 0 }

                @Frozen
                public func unusedPlain(): Int64 { 0 }

                @Frozen
                public func unusedFull(this @local!): Int64 { 1 }

                @Frozen
                public func unusedHalf(this @local?): Int64 { 2 }
            }
            """, localMode: true, stage: CompileStage.MANGLING, outputMode: OutputMode.CJO)
        @Assert(library.ok)
        let root = Directory.createTemp(".").toString()
        try {
            FSFile.writeTo(root + "/frozenmodals.cjo",
                library.instance.ExportAST(false, RequireFirstPackage(library)))
            check(root)
        } finally {
            let _ = removeIfExists(root, recursive: true)
        }
    }

    private func GetBoxMembers(importPath: String, localMode: Bool, callPlain!: Bool = false): HashSet<String> {
        let expr = if (callPlain) { "box.plain()" } else { "0" }
        let result = CompileResolverSource("""
            import frozenmodals.FrozenBox
            main(): Int64 {
                let box = FrozenBox<Int64>()
                ${expr}
            }
            """, localMode: localMode, importPath: importPath)
        @Assert(result.ok)
        let names = HashSet<String>()
        for (decl in RequireFirstPackage(result).genericInstantiatedDecls) {
            if ((let Some(original) <- decl.genericDecl) && original.fullPackageName == "frozenmodals" &&
                original.identifier.Val() == "FrozenBox") {
                for (member in decl.GetMemberDecls()) { names.add(member.identifier.Val()) }
            }
        }
        return names
    }

    @TestCase
    public func ImportedFrozenModesFollowEachCompilation(): Unit {
        WithImportedBox({ library: String =>
            let ordinary = GetBoxMembers(library, false)
            @Expect(ordinary.contains("unusedPlain"))
            @Expect(!ordinary.contains("unusedFull") && !ordinary.contains("unusedHalf"))

            let modal = GetBoxMembers(library, true)
            @Expect(modal.contains("unusedFull") && modal.contains("unusedHalf"))

            let reset = GetBoxMembers(library, false)
            @Expect(reset.contains("unusedFull") == ordinary.contains("unusedFull") &&
                reset.contains("unusedHalf") == ordinary.contains("unusedHalf"))
        })
    }

    @TestCase
    public func OrdinaryFrozenBodyKeepsItsReferencedLocalHelper(): Unit {
        WithImportedBox({ library: String =>
            let members = GetBoxMembers(library, false, callPlain: true)
            @Expect(members.contains("plain"))
            @Expect(members.contains("required"))
        })
    }
}
