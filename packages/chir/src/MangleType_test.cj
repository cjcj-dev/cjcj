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
        @Expect(MangleCHIRType(builder.context.GetInt8Ty()), "a")
        @Expect(MangleCHIRType(builder.context.GetInt16Ty()), "s")
        @Expect(MangleCHIRType(builder.context.GetInt32Ty()), "i")
        @Expect(MangleCHIRType(builder.context.GetInt64Ty()), "l")
        @Expect(MangleCHIRType(builder.context.GetUInt8Ty()), "h")
        @Expect(MangleCHIRType(builder.context.GetFloat64Ty()), "d")
        @Expect(MangleCHIRType(builder.context.GetBoolTy()), "b")
        @Expect(MangleCHIRType(builder.context.GetUnitTy()), "u")
        @Expect(MangleCHIRType(builder.context.GetCStringTy()), "k")
    }

    @TestCase
    public func funcTypes(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let params = ArrayList<Type>()
        params.add(builder.context.GetInt64Ty())
        params.add(builder.context.GetInt64Ty())
        let funcTy = builder.context.GetFuncTy(params, builder.context.GetInt64Ty())
        @Expect(MangleCHIRType(funcTy), "F0lllE")
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
        @Expect(MangleCHIRType(tupleTy), "T2_asiE")

        let refTy = builder.context.GetRefTy(builder.context.GetInt8Ty())
        @Expect(MangleCHIRType(refTy), "a")
    }
}
