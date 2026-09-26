package cjcj::chir

import std.unittest.*
import std.unittest.testmacro.*

@Test
public class CanonicalizeStringBackingTest {
    @TestCase
    public func RecognizesCanonicalizeStringBacking(): Unit {
        let kind = LookupCoreIntrinsicKind("canonicalizeStringBacking")
        @Expect(kind.isSome(), true)
        @Expect(kind.getOrThrow() == IntrinsicKind.CANONICALIZE_STRING_BACKING, true)
        @Expect(IntrinsicKindName(kind.getOrThrow()), "CANONICALIZE_STRING_BACKING")
        @Expect(IntrinsicKindToString(kind.getOrThrow()), "canonicalizeStringBacking")
        @Expect(CHIRIntrinsicKindFromName(IntrinsicKindName(kind.getOrThrow())) ==
            IntrinsicKind.CANONICALIZE_STRING_BACKING, true)
        @Expect(CHIRFB_INTRINSIC_KIND_CANONICALIZE_STRING_BACKING, 362u16)
        @Expect(CHIRFB_INTRINSIC_KIND_MAX, 362u16)
        @Expect(CHIRFB_INTRINSIC_KIND_EXCLUSIVE_SCOPE, 361u16)
    }

    @TestCase
    public func FillInStackTraceStillRecognized(): Unit {
        let kind = LookupCoreIntrinsicKind("fillInStackTrace")
        @Expect(kind.isSome(), true)
        @Expect(kind.getOrThrow() == IntrinsicKind.FILL_IN_STACK_TRACE, true)
        @Expect(CHIRFB_INTRINSIC_KIND_FILL_IN_STACK_TRACE, 24u16)
    }

    @TestCase
    public func OldForeignNameIsNotTheIntrinsic(): Unit {
        @Expect(LookupCoreIntrinsicKind("canonicalizeString").isSome(), false)
        @Expect(LookupCoreIntrinsicKind("deduplicated").isSome(), false)
        @Expect(CHIRIntrinsicKindFromName("CANONICALIZE_STRING") == IntrinsicKind.NOT_INTRINSIC, true)
    }
}
