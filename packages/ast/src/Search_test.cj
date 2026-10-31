package cjcj::ast

import std.collection.*
import cjcj::utils.TaskQueue
import std.unittest.*
import std.unittest.testmacro.*

@Test
class SearchTest {
    // PORT-DEFERRED: all compiler-instance, sema, collector, and source parsing SearchTest cases need parser/harness wave.

    @TestCase
    func bodyContextsKeepSearchMembershipAndIdsIndependent(): Unit {
        let parent = ASTContext(Package())
        let node = VarDecl()
        node.scopeName = "a"
        let symbol = Symbol("shared", node: Some(node))
        parent.symbolTable.add(symbol)
        parent.invertedIndex.Index(symbol)
        let firstId = SymbolApi.NextHashID(0u64)
        let left = parent.ForkForBody()
        let right = parent.ForkForBody()
        let secondId = SymbolApi.NextHashID(0u64)
        @Expect(secondId.fieldID, firstId.fieldID + 1u32)
        @Expect(left.searcher.Search(left, "name: shared").size, 1)
        @Expect(right.searcher.Search(right, "name: shared").size, 1)
        let queue = TaskQueue(2)
        let deleted = queue.AddTask<Int64>({ =>
            left.invertedIndex.Delete(symbol)
            left.searcher.InvalidateCache()
            left.invertedIndex.scopeNameTrie.Insert("left-only")
            left.searcher.Search(left, "name: shared").size
        })
        let retained = queue.AddTask<Int64>({ =>
            right.searcher.InvalidateCache()
            right.searcher.Search(right, "name: shared").size
        })
        queue.RunAndWaitForAllTasksCompleted()
        @Expect(deleted.get(), 0)
        @Expect(retained.get(), 1)
        @Expect(parent.searcher.Search(parent, "name: shared").size, 1)
        @Expect(parent.invertedIndex.IsDeleted(symbol), false)
        @Expect(left.invertedIndex.scopeNameTrie.PrefixMatch("left-only").size, 1)
        @Expect(right.invertedIndex.scopeNameTrie.PrefixMatch("left-only").size, 0)
        @Expect(parent.invertedIndex.scopeNameTrie.PrefixMatch("left-only").size, 0)
        parent.invertedIndex.Delete(symbol)
        parent.searcher.InvalidateCache()
        @Expect(parent.searcher.Search(parent, "name: shared").size, 0)
        right.searcher.InvalidateCache()
        @Expect(right.searcher.Search(right, "name: shared").size, 1)
    }

    @TestCase
    func queryParserTest(): Unit {
        let query = ParseQuery("id : 1 ! id : 2")
        @Expect(query.kind == QueryKind.NOT)
    }

    @TestCase
    func scopeName(): Unit {
        @Expect(GetScopeGateName("a0b"), "a_b")
        @Expect(GetScopeGateName("a0b_a"), "a_b")
        @Expect(GetScopeGateName("a"), "")
        @Expect(GetScopeGateName("a_a"), "")
        @Expect(GetChildScopeName("a_a"), "a0a")
    }

    private func equalStrings(actual: ArrayList<String>, expected: Array<String>): Bool {
        if (actual.size != expected.size) {
            return false
        }
        for (idx in 0..actual.size) {
            if (actual[idx] != expected[idx]) {
                return false
            }
        }
        return true
    }

    private func sortStrings(values: ArrayList<String>): Unit {
        var idx: Int64 = 1
        while (idx < values.size) {
            let value = values[idx]
            var cursor = idx
            while (cursor > 0 && value < values[cursor - 1]) {
                values[cursor] = values[cursor - 1]
                cursor--
            }
            values[cursor] = value
            idx++
        }
    }

    @TestCase
    func prefixTrie(): Unit {
        let prefixTrie = Trie()
        prefixTrie.Insert("a0b")
        prefixTrie.Insert("a0b0c0e")
        prefixTrie.Insert("a0b")
        prefixTrie.Insert("a0c")
        prefixTrie.Insert("a0b0d")
        prefixTrie.Insert("a0d")
        @Expect(equalStrings(prefixTrie.PrefixMatch("a0b"), ["a0b", "a0b0c0e", "a0b0d"]))

        prefixTrie.Reset()
        prefixTrie.Insert("a0b0c")
        prefixTrie.Insert("a0c")
        prefixTrie.Insert("a0b0d")
        prefixTrie.Insert("a0d")
        @Expect(equalStrings(prefixTrie.PrefixMatch("a0b"), ["a0b0c", "a0b0d"]))
    }

    @TestCase
    func suffixTrie(): Unit {
        let suffixTrie = Trie()
        suffixTrie.Insert("var_decl")
        suffixTrie.Insert("ref_type")
        suffixTrie.Insert("member_access")
        suffixTrie.Insert("func_decl")
        suffixTrie.Insert("ref_expr")
        suffixTrie.Insert("record_decl")
        suffixTrie.Insert("class_decl")
        let results = suffixTrie.SuffixMatch("decl")
        sortStrings(results)
        @Expect(equalStrings(results, ["class_decl", "func_decl", "record_decl", "var_decl"]))
    }

    @TestCase
    func searchBigColumn(): Unit {
        PosSearchApi.MAX_DIGITS_FILE = 4
        PosSearchApi.MAX_DIGITS_LINE = 5
        PosSearchApi.MAX_DIGITS_COLUMN = 5
        PosSearchApi.UpdatePosLimit(0u64, 1, 224650)
        @Expect(PosSearchApi.MAX_DIGITS_FILE, 4)
        @Expect(PosSearchApi.MAX_DIGITS_LINE, 5)
        @Expect(PosSearchApi.MAX_DIGITS_COLUMN, 6)
    }
}
