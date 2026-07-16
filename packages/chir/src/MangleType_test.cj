package cjcj::chir

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class MangleTypeTest {
    @TestCase
    public func builtinTypes(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        @Expect(MangleType(builder.context.GetInt8Ty()), "a")
        @Expect(MangleType(builder.context.GetInt16Ty()), "s")
        @Expect(MangleType(builder.context.GetInt32Ty()), "i")
        @Expect(MangleType(builder.context.GetInt64Ty()), "l")
        @Expect(MangleType(builder.context.GetUInt8Ty()), "h")
        @Expect(MangleType(builder.context.GetFloat64Ty()), "d")
        @Expect(MangleType(builder.context.GetBoolTy()), "b")
        @Expect(MangleType(builder.context.GetUnitTy()), "u")
        @Expect(MangleType(builder.context.GetCStringTy()), "k")
    }

    @TestCase
    public func funcTypes(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let params = ArrayList<Type>()
        params.add(builder.context.GetInt64Ty())
        params.add(builder.context.GetInt64Ty())
        let funcTy = builder.context.GetFuncTy(params, builder.context.GetInt64Ty())
        @Expect(MangleType(funcTy), "F0lllE")
    }

    @TestCase
    public func tupleAndRefTypes(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let tupleItems = ArrayList<Type>()
        tupleItems.add(builder.context.GetInt8Ty())
        tupleItems.add(builder.context.GetInt16Ty())
        tupleItems.add(builder.context.GetInt32Ty())
        let tupleTy = builder.context.GetTupleTy(tupleItems)
        @Expect(MangleType(tupleTy), "T2_asiE")

        let refTy = builder.context.GetRefTy(builder.context.GetInt8Ty())
        @Expect(MangleType(refTy), "a")
    }
}
