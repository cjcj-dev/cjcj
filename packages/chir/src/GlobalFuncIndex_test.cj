package cjcj::chir

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class GlobalFuncIndexTest {
    @TestCase
    public func FirstAddedIdentifierWinsAcrossReset(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let pkg = builder.CreatePackage("index")
        let ty = context.GetFuncTy(ArrayList<Type>(), context.GetUnitTy())
        let first = builder.CreateFunction(ty, "dup")
        let second = builder.CreateFunction(ty, "dup")
        let only = builder.CreateFunction(ty, "only")
        let looked = pkg.TryGetGlobalFunc(GLOBAL_VALUE_PREFIX + "dup")
        let lookedId = if (let Some(fn) <- looked) { fn.nodeId } else { -1 }
        println("GLOBAL_FUNC_INDEX phase=first looked=${lookedId} expect=${first.nodeId} other=${second.nodeId}")
        @Expect(looked.isSome(), true)
        @Expect(lookedId, first.nodeId)
        let missing = pkg.TryGetGlobalFunc(GLOBAL_VALUE_PREFIX + "missing")
        println("GLOBAL_FUNC_INDEX phase=missing none=${missing.isNone()}")
        @Expect(missing.isNone(), true)
        let onlyHit = pkg.TryGetGlobalFunc(GLOBAL_VALUE_PREFIX + "only")
        let onlyId = if (let Some(fn) <- onlyHit) { fn.nodeId } else { -1 }
        println("GLOBAL_FUNC_INDEX phase=only looked=${onlyId} expect=${only.nodeId}")
        @Expect(onlyId, only.nodeId)
        let kept = ArrayList<Function>()
        kept.add(second)
        pkg.SetAllGlobalFuncs(kept)
        let reset = pkg.TryGetGlobalFunc(GLOBAL_VALUE_PREFIX + "dup")
        let resetId = if (let Some(fn) <- reset) { fn.nodeId } else { -1 }
        println("GLOBAL_FUNC_INDEX phase=reset looked=${resetId} expect=${second.nodeId} stale=${first.nodeId}")
        @Expect(reset.isSome(), true)
        @Expect(resetId, second.nodeId)
        let dropped = pkg.TryGetGlobalFunc(GLOBAL_VALUE_PREFIX + "only")
        println("GLOBAL_FUNC_INDEX phase=dropped none=${dropped.isNone()}")
        @Expect(dropped.isNone(), true)
    }
}
