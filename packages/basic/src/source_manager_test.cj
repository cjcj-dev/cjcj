package cjcj::basic

import std.unittest.*
import std.unittest.testmacro.*

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Basic/SourceManagerTest.cpp:48 reads CangjieFiles/lsp.cj
@When[os == "Windows"]
private func lspSnippet(): String {
    return "// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.\r\n" +
        "// This source file is part of the Cangjie project, licensed under Apache-2.0\r\n" +
        "// with Runtime Library Exception.\r\n" +
        "//\r\n" +
        "// See https://cangjie-lang.cn/pages/LICENSE for license information.\r\n" +
        "/* LSP example\r\n" +
        " */\r\n" +
        "\r\n" +
        "import systemlib\r\n" +
        "import BuiltinLib\r\n" +
        "import utilLib\r\n" +
        "class PageRankList <: Page {\r\n" +
        "    public init() {\r\n" +
        "        let a = 1\r\n" +
        "        print(\"PageRankList" + "$" + "{a}\\n\");\r\n" +
        "    }\r\n"
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Basic/SourceManagerTest.cpp:48 reads CangjieFiles/lsp.cj
@When[os != "Windows"]
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

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Basic/SourceManagerTest.cpp:63 TEST_F(SourceManagerTest, GetContentBetweenTest)
@When[os == "Windows"]
private func GetContentBetweenTest(sm: SourceManager, fileID: UInt64): Unit {
    var code = sm.GetContentBetween(fileID, Position(14, 9), Position(14, 14))
    @Expect(code, "let a")

    code = sm.GetContentBetween(fileID, Position(14, 9), Position(14, 18))
    @Expect(code, "let a = 1")

    code = sm.GetContentBetween(fileID, Position(14, 9), Position(14, 19))
    @Expect(code, "let a = 1\r\n")

    code = sm.GetContentBetween(fileID, Position(14, 9), Position(14, Int64.Max))
    @Expect(code, "let a = 1\r\n")

    code = sm.GetContentBetween(fileID, Position(14, 9), Position(15, 14))
    @Expect(code, "let a = 1\r\n        print")

    code = sm.GetContentBetween(fileID, Position(14, 9), Position(15, 37))
    @Expect(code, "let a = 1\r\n        print(\"PageRankList" + "$" + "{a}\\n\");")

    code = sm.GetContentBetween(fileID, Position(14, 9), Position(15, 38))
    @Expect(code, "let a = 1\r\n        print(\"PageRankList" + "$" + "{a}\\n\");\r\n")

    code = sm.GetContentBetween(fileID, Position(14, 9), Position(15, Int64.Max))
    @Expect(code, "let a = 1\r\n        print(\"PageRankList" + "$" + "{a}\\n\");\r\n")
}

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Basic/SourceManagerTest.cpp:63 TEST_F(SourceManagerTest, GetContentBetweenTest)
@When[os != "Windows"]
private func GetContentBetweenTest(sm: SourceManager, fileID: UInt64): Unit {
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

@Test
class SourceManagerTest {
    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Basic/SourceManagerTest.cpp:46 TEST_F(SourceManagerTest, AddSourceTest)
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

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Basic/SourceManagerTest.cpp:63 TEST_F(SourceManagerTest, GetContentBetweenTest)
    @TestCase
    func getContentBetweenTest(): Unit {
        let sm = SourceManager()
        let fileID = sm.AddSource("/tmp/cangjie_basic_lsp.cj", lspSnippet())
        GetContentBetweenTest(sm, fileID)
    }

    @TestCase
    func pathPrefixMapDefaultsOffTest(): Unit {
        let sm = SourceManager()
        let fileID = sm.AddSource("/build/root/pkg/dir/foo.cj", "")
        @Expect(sm.GetSource(fileID).fileHash, 7543164539185912140u64)
    }

    @TestCase
    func pathPrefixMapMakesBuildRootsStableTest(): Unit {
        let left = SourceManager()
        left.SetPathPrefixMaps([("/build/left", "module@v1")])
        let leftID = left.AddSource("/build/left/pkg/dir/foo.cj", "")

        let right = SourceManager()
        right.SetPathPrefixMaps([("/build/right", "module@v1")])
        let rightID = right.AddSource("/build/right/pkg/dir/foo.cj", "")

        @Expect(left.GetSource(leftID).fileHash, right.GetSource(rightID).fileHash)
    }

    @TestCase
    func pathPrefixMapPreservesDirectoriesForSameBasenameTest(): Unit {
        let sm = SourceManager()
        sm.SetPathPrefixMaps([("/build/root", "module@v1")])
        let firstID = sm.AddSource("/build/root/pkg/dirA/foo.cj", "")
        let secondID = sm.AddSource("/build/root/pkg/dirB/foo.cj", "")
        @Expect(sm.GetSource(firstID).fileHash == sm.GetSource(secondID).fileHash, false)
    }

    @TestCase
    func pathPrefixMapRejectsNonInjectiveMappingsTest(): Unit {
        let sm = SourceManager()
        sm.SetPathPrefixMaps([("/build/first", "module@v1"), ("/build/second", "module@v1")])
        let _ = sm.AddSource("/build/first/pkg/foo.cj", "")
        var rejected = false
        try {
            let _ = sm.AddSource("/build/second/pkg/foo.cj", "")
        } catch (_: IllegalArgumentException) {
            rejected = true
        }
        @Expect(rejected, true)
    }
}
