package cangjie_compiler::basic

import std.unittest.*
import std.unittest.testmacro.*

private func lspSnippet(): String {
    return "// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.\n" +
        "// This source file is part of the Cangjie project, licensed under Apache-2.0\n" +
        "// with Runtime Library Exception.\n" +
        "//\n" +
        "// See https://cangjie-lang.cn/pages/LICENSE for license information.\n" +
        "\n" +
        "/* LSP example\n" +
        " */\n" +
        "\n" +
        "import systemlib\n" +
        "import BuiltinLib\n" +
        "import utilLib\n" +
        "\n" +
        "class PageRankList <: Page {\n" +
        "    public init() {\n" +
        "        let a = 1\n" +
        "        print(\"PageRankList" + "$" + "{a}\\n\");\n" +
        "    }\n"
}

@Test
class SourceManagerTest {
    @TestCase
    func addSourceTest(): Unit {
        let sm = SourceManager()
        let path = "/tmp/cangjie_basic_lsp.cj"
        let content = lspSnippet()
        let fileID1 = sm.AddSource(path, content)
        let fileID2 = sm.AddSource(path, content)
        let fileID3 = sm.AddSource(path, content)
        @Expect(fileID1, fileID2)
        @Expect(fileID2, fileID3)
        @Expect(sm.GetNumberOfFiles(), 2u64)
        @Expect(sm.GetFileID(path), Int64(fileID3))
    }

    @TestCase
    func getContentBetweenTest(): Unit {
        let sm = SourceManager()
        let fileID = sm.AddSource("/tmp/cangjie_basic_lsp.cj", lspSnippet())
        var code = sm.GetContentBetween(fileID, Position(16, 9), Position(16, 14))
        @Expect(code, "let a")

        code = sm.GetContentBetween(fileID, Position(16, 9), Position(16, 18))
        @Expect(code, "let a = 1")

        code = sm.GetContentBetween(fileID, Position(16, 9), Position(16, 19))
        @Expect(code, "let a = 1\n")

        code = sm.GetContentBetween(fileID, Position(16, 9), Position(16, Int64.Max))
        @Expect(code, "let a = 1\n")

        code = sm.GetContentBetween(fileID, Position(16, 9), Position(17, 14))
        @Expect(code, "let a = 1\n        print")

        code = sm.GetContentBetween(fileID, Position(16, 9), Position(17, 37))
        @Expect(code, "let a = 1\n        print(\"PageRankList" + "$" + "{a}\\n\");")

        code = sm.GetContentBetween(fileID, Position(16, 9), Position(17, 38))
        @Expect(code, "let a = 1\n        print(\"PageRankList" + "$" + "{a}\\n\");\n")

        code = sm.GetContentBetween(fileID, Position(16, 9), Position(17, Int64.Max))
        @Expect(code, "let a = 1\n        print(\"PageRankList" + "$" + "{a}\\n\");\n")
    }
}
