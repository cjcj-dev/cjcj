package cjcj::ast

import std.unittest.*
import std.unittest.testmacro.*

@Test
public class InlineASTAttributesTest {
    @TestCase
    public func cloneAndWireNumbersAcrossWordBoundary(): Unit {
        let source = RefExpr()
        source.EnableAttr(Attribute.IS_OUTERMOST)
        source.EnableAttr(Attribute.IS_ANNOTATION)
        source.EnableAttr(Attribute.DOES_NOT_THROW)
        let clone = ASTCloner.Clone(source)
        let snapshot = source.GetAttrs()

        source.DisableAttr(Attribute.IS_ANNOTATION)
        snapshot.SetAttr(Attribute.DOES_NOT_THROW, false)
        @Expect(source.TestAttr(Attribute.IS_ANNOTATION), false)
        @Expect(source.TestAttr(Attribute.DOES_NOT_THROW), true)
        @Expect(clone.TestAttr(Attribute.IS_ANNOTATION), true)
        @Expect(clone.TestAttr(Attribute.DOES_NOT_THROW), true)

        // SaveAttributes consumes these ascending wire indices.
        let attrs = clone.GetAttrs()
        let indices = attrs.GetAllIdxOfAttr()
        @Assert(indices.size, 4)
        @Expect(indices[0], 6u64) // CloneExpr marks COMPILER_ADD.
        @Expect(indices[1], 63u64)
        @Expect(indices[2], 64u64)
        @Expect(indices[3], 94u64)
        let words = attrs.GetRawAttrs()
        @Assert(words.size, 2)
        @Expect(words[0], (1u64 << 6u64) | (1u64 << 63u64))
        @Expect(words[1], 1u64 | (1u64 << 30u64))

        source.CopyAttrs(snapshot)
        snapshot.SetAttr(Attribute.IS_ANNOTATION, false)
        @Expect(source.TestAttr(Attribute.IS_ANNOTATION), true)
        @Expect(source.TestAttr(Attribute.DOES_NOT_THROW), false)
    }
}
