package cjcj::chir

import std.unittest.*
import std.unittest.testmacro.*

@Test
class BaseAnnotationsTest {
    @TestCase
    func defaultReadsAndEmptyCopiesDoNotMaterializeAnnotations(): Unit {
        let source = Base()
        let copy = Base()
        @Expect(source.GetNeedCheckCast(), true)
        @Expect(source.GetNeedCheckArrayBound(), true)
        @Expect(source.GetGeneratedFromForIn(), false)
        @Expect(source.GetEnumCaseIndex().isNone(), true)
        @Expect(source.GetSkipCheck() == SkipKind.NO_SKIP)
        source.RemoveSkipCheck()
        @Expect(source.BaseCommentToString(), "")
        @Expect(CHIRSerializeBaseAnnotations(source), "")
        copy.CopyBaseInfoFrom(source)
        @Expect(source.GetAnnotations().isNone(), true)
        @Expect(copy.GetAnnotations().isNone(), true)
    }

    @TestCase
    func firstWriteIsSerializedAndCopiesAreIndependent(): Unit {
        let source = Base()
        let copy = Base()
        source.SetSkipCheck(SkipKind.SKIP_DCE_WARNING)
        @Expect(source.GetAnnotations().getOrThrow().size, 1)
        @Expect(CHIRSerializeBaseAnnotations(source), "skip: dce warning")
        CHIRApplyBaseAnnotations(copy, CHIRSerializeBaseAnnotations(source))
        @Expect(copy.GetSkipCheck() == SkipKind.SKIP_DCE_WARNING)

        copy.CopyBaseInfoFrom(source)
        source.SetSkipCheck(SkipKind.SKIP_VIC)
        @Expect(copy.GetSkipCheck() == SkipKind.SKIP_DCE_WARNING)

        copy.CopyBaseInfoFrom(copy)
        @Expect(copy.GetSkipCheck() == SkipKind.SKIP_DCE_WARNING)
        source.RemoveSkipCheck()
        copy.CopyBaseInfoFrom(source)
        @Expect(copy.GetSkipCheck() == SkipKind.NO_SKIP)
        @Expect(CHIRSerializeBaseAnnotations(copy), "")
    }

    @TestCase
    func sharedFirstWritesRetainBothAnnotations(): Unit {
        let source = Base(sharedAttributes: true)
        let cast = spawn { source.SetNeedCheckCast(false) }
        let bounds = spawn { source.SetNeedCheckArrayBound(false) }
        cast.get()
        bounds.get()
        @Expect(source.GetNeedCheckCast(), false)
        @Expect(source.GetNeedCheckArrayBound(), false)
        @Expect(source.GetAnnotations().getOrThrow().size, 2)
    }
}
