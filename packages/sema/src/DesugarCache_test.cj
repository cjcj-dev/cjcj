package cjcj::sema

import cjcj::ast.*
import std.collection.ArrayList
import std.unittest.*
import std.unittest.testmacro.*

@Test
class DesugarCacheTest {
    @TestCase
    func pointerCallRecoveryKeepsOnlyLiveCachedNodes(): Unit {
        for (compatible in [false, true]) {
            let tm = TypeManager()
            let ctx = ASTContext(Package("test"))
            let pointerTy = tm.GetPointerTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64))
            let constructor = RefExpr()
            constructor.SetTarget(Some(BuiltInDecl(BuiltInType.POINTER)))
            constructor.SetTy(pointerTy)
            let value = RefExpr()
            value.SetTy(pointerTy)
            let argument = CreateFuncArg(value)
            ctx.SkipSynForCorrectTy(argument)
            ctx.SkipSynForCorrectTy(value)
            let call = CreateCallExpr(constructor, ArrayList<FuncArg>([argument]))
            let checkedTypes = ArrayList<Type>()

            let checked = ChkPointerCall(tm, Some(ctx), pointerTy, call,
                typeChecker: Some({ _: Ty, temporary: Type =>
                    ctx.SkipSynForCorrectTy(temporary)
                    checkedTypes.add(temporary)
                    compatible
                }))

            @Assert(checkedTypes.size == 1)
            @Expect(checked, compatible)
            @Expect(call.desugarExpr.isSome(), compatible)
            @Expect(ctx.typeCheckCache.get(checkedTypes[0]).isSome(), compatible)
            @Expect(ctx.IsSynSkippedForCorrectTy(argument), true)
            @Expect(ctx.IsSynSkippedForCorrectTy(value), true)
            if (!compatible) {
                @Assert(call.args.size == 1)
                @Expect(call.args[0].objectId, argument.objectId)
            }
        }
    }
}
