package cjcj::chir

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class ConstantCloneTest {
    private func CheckClone(builder: CHIRBuilder, block: Block, ty: Type,
        literal: LiteralValue): Constant {
        literal.SetIdentifier("literal_metadata")
        literal.EnableAttr(Attribute.COMPILER_ADD)
        literal.SetNeverOverflowInfo(true)
        let loc = DebugLocation("literal.cj", 1u32, Position(2u32, 3u32), Position(2u32, 9u32))
        literal.SetDebugLocation(loc)
        let source = builder.CreateConstant(ty, literal, block)
        block.AppendExpression(source)
        source.GetResult().getOrThrow().EnableAttr(Attribute.READONLY)
        let cloned = (source.Clone(builder, block) as Constant).getOrThrow()
        block.AppendExpression(cloned)
        let copy = cloned.GetValue()
        @Expect(refEq(copy, literal), false)
        @Expect(copy.literalKind == literal.literalKind, true)
        @Expect(refEq(copy.GetType().getOrThrow(), ty), true)
        @Expect(refEq(cloned.GetResult().getOrThrow().GetType().getOrThrow(), ty), true)
        @Expect(copy.GetUsers().size, 1)
        @Expect(refEq(copy.GetUsers()[0], cloned), true)
        @Expect(literal.GetUsers().size, 1)
        @Expect(refEq(literal.GetUsers()[0], source), true)
        @Expect(cloned.GetResult().getOrThrow().TestAttr(Attribute.READONLY), true)
        if (literal.IsNullLit()) {
            // Preserve the pre-existing null branch, including fresh metadata.
            @Expect(copy.GetIdentifier(), "")
            @Expect(copy.TestAttr(Attribute.COMPILER_ADD), false)
            @Expect(copy.GetDebugLocation(), DebugLocation())
        } else {
            @Expect(copy.GetIdentifier(), "literal_metadata")
            @Expect(copy.TestAttr(Attribute.COMPILER_ADD), true)
            @Expect(copy.GetNeverOverflowInfo(), true)
            @Expect(copy.GetDebugLocation(), loc)
            copy.SetIdentifier("changed")
            copy.DisableAttr(Attribute.COMPILER_ADD)
            copy.SetNeverOverflowInfo(false)
            copy.SetDebugLocation(DebugLocation())
            @Expect(literal.GetIdentifier(), "literal_metadata")
            @Expect(literal.TestAttr(Attribute.COMPILER_ADD), true)
            @Expect(literal.GetNeverOverflowInfo(), true)
            @Expect(literal.GetDebugLocation(), loc)
        }
        // Generic instantiation's type conversion must not change the source Value.
        copy.SetType(builder.context.GetUnitTy())
        @Expect(refEq(literal.GetType().getOrThrow(), ty), true)
        copy.SetType(ty)
        return cloned
    }

    @TestCase
    func literalPayloadTypeAndMetadataSurviveIndependentCloning(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let _ = builder.CreatePackage("constant_clone")
        let fn = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>(), context.GetUnitTy()), "clone")
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let block = builder.CreateBlock(body)
        body.SetEntryBlock(block)
        for (ty in [context.GetInt8Ty(), context.GetInt16Ty(), context.GetInt32Ty(),
            context.GetInt64Ty(), context.GetIntNativeTy()]) {
            let copy = CheckClone(builder, block, ty, IntLiteral(-1i64))
            @Expect(copy.GetSignedIntLitVal(), -1i64)
            @Expect(copy.GetUnsignedIntLitVal(), UInt64.Max)
            @Expect(copy.IsSignedIntLit(), true)
        }
        for (ty in [context.GetUInt8Ty(), context.GetUInt16Ty(), context.GetUInt32Ty(),
            context.GetUInt64Ty(), context.GetUIntNativeTy()]) {
            let copy = CheckClone(builder, block, ty, IntLiteral(7u64))
            @Expect(copy.GetUnsignedIntLitVal(), 7u64)
            @Expect(copy.IsUnSignedIntLit(), true)
        }
        @Expect(CheckClone(builder, block, context.GetInt64Ty(), IntLiteral(Int64.Min)).GetSignedIntLitVal(), Int64.Min)
        @Expect(CheckClone(builder, block, context.GetUInt64Ty(), IntLiteral(UInt64.Max)).GetUnsignedIntLitVal(), UInt64.Max)
        for (ty in [context.GetFloat16Ty(), context.GetFloat32Ty(), context.GetFloat64Ty()]) {
            @Expect(CheckClone(builder, block, ty, FloatLiteral(-13.5)).GetFloatLitVal(), -13.5)
        }
        let negativeZero = FloatLiteral(-0.0)
        let zeroCopy = CheckClone(builder, block, context.GetFloat64Ty(), negativeZero)
        @Expect(1.0 / zeroCopy.GetFloatLitVal(), 1.0 / negativeZero.GetVal())
        @Expect(CheckClone(builder, block, context.GetBoolTy(), BoolLiteral(true)).GetBoolLitVal(), true)
        @Expect(CheckClone(builder, block, context.GetRuneTy(), RuneLiteral(r'中')).GetRuneLitVal(), r'中')
        let stringTy = context.GetStructTy(StructDef("std.core", "String"), ArrayList<Type>())
        @Expect(CheckClone(builder, block, stringTy, StringLiteral("中\u{0}text")).GetStringLitVal(), "中\u{0}text")
        @Expect(CheckClone(builder, block, context.GetUnitTy(), UnitLiteral()).IsUnitLit(), true)
        @Expect(CheckClone(builder, block, context.GetRefTy(context.GetInt64Ty()), NullLiteral()).IsNullLit(), true)
        block.AppendExpression(builder.CreateExit(None, block))
    }
}
