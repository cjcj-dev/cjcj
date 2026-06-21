package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*

public class ScopeManager {
    private let chars: Array<String> = [
        "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
        "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
        "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
        "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
    ]
    private let charIndexes: ArrayList<Int64> = ArrayList<Int64>()

    public init() {
        Reset()
    }

    public func Reset(): Unit {
        charIndexes.clear()
        charIndexes.add(0)
    }

    public func InitializeScope(ctx: ASTContext): Unit {
        ctx.currentScopeLevel += 1u32
        if (ctx.currentScopeLevel > ctx.currentMaxDepth) {
            ctx.currentMaxDepth = ctx.currentScopeLevel
        }
        let level = Int64(ctx.currentScopeLevel)
        if (level > charIndexes.size - 1) {
            charIndexes.add(0)
            ctx.currentScopeName += SCOPE_NAME_SPLIT + "a"
        } else {
            charIndexes[level] = charIndexes[level] + 1
            if (level > 1 && charIndexes[level] == 0) {
                ctx.currentScopeName += SCOPE_NAME_SPLIT + "a"
            } else {
                ctx.currentScopeName += GetLayerName(charIndexes[level], SCOPE_NAME_SPLIT)
            }
        }
        ctx.invertedIndex.scopeNameTrie.Insert(ctx.currentScopeName)
    }

    public func CalcScopeGateName(ctx: ASTContext): String {
        let level = Int64(ctx.currentScopeLevel) + 1
        if (level > charIndexes.size - 1) {
            return ctx.currentScopeName + CHILD_SCOPE_SEPARATOR + "a"
        }
        if (level > 1 && charIndexes[level] == -1) {
            return ctx.currentScopeName + CHILD_SCOPE_SEPARATOR + "a"
        }
        return ctx.currentScopeName + GetLayerName(charIndexes[level] + 1, CHILD_SCOPE_SEPARATOR)
    }

    public func FinalizeScope(ctx: ASTContext): Unit {
        let level = Int64(ctx.currentScopeLevel)
        let backLength = GetLayerNameLength(charIndexes[level]) + 1
        ctx.currentScopeName = ctx.currentScopeName[0..(ctx.currentScopeName.size - backLength)]
        ctx.currentScopeLevel -= 1u32
        if (ctx.currentScopeLevel == 0u32) {
            var i: Int64 = 2
            while (i <= Int64(ctx.currentMaxDepth)) {
                charIndexes[i] = -1
                i++
            }
        }
    }

    private func GetLayerName(layerIndex: Int64, split: String): String {
        if (layerIndex == 0) {
            return TOPLEVEL_SCOPE_NAME
        }
        let length = GetLayerNameLength(layerIndex)
        let digits = ArrayList<Int64>()
        var value = layerIndex
        var i: Int64 = 0
        while (i < length) {
            digits.add(value % 52)
            value = value / 52
            i++
        }
        var out = split
        var idx = digits.size - 1
        while (idx >= 0) {
            out += chars[digits[idx]]
            idx--
        }
        return out
    }

    private func GetLayerNameLength(layerIndex: Int64): Int64 {
        if (layerIndex == 0) {
            return 1
        }
        var length: Int64 = 1
        var bound: Int64 = 52
        while (layerIndex >= bound) {
            length++
            bound *= 52
        }
        return length
    }
}
