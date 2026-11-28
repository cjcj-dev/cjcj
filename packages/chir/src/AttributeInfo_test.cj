package cjcj::chir

import std.unittest.*
import std.unittest.testmacro.*

@Test
public class InlineCHIRAttributesTest {
    @TestCase
    public func highAndLowAttributesSurviveSharedBaseSnapshots(): Unit {
        let base = Base(sharedAttributes: true)
        base.EnableAttr(Attribute.DOES_NOT_THROW)
        base.EnableAttr(Attribute.FAST_NATIVE)
        let snapshot = base.GetAttributeInfo()
        let restored = Base()
        restored.AppendAttributeInfo(snapshot)
        snapshot.Disable(Attribute.FAST_NATIVE)
        base.DisableAttr(Attribute.DOES_NOT_THROW)

        @Expect(base.TestAttr(Attribute.FAST_NATIVE), true)
        @Expect(base.TestAttr(Attribute.DOES_NOT_THROW), false)
        @Expect(restored.TestAttr(Attribute.FAST_NATIVE), true)
        @Expect(restored.TestAttr(Attribute.DOES_NOT_THROW), true)
        @Expect(restored.GetAttributeInfo().GetRawAttrs(), 1u64 << 38u64)
        let wire = CHIRSerializeAttributeInfo(restored.GetAttributeInfo())
        @Expect(wire, "38,71")
        let decoded = AttributeInfo()
        CHIRApplyAttributeInfo(decoded, wire)
        @Expect(decoded.Test(Attribute.FAST_NATIVE), true)
        @Expect(decoded.Test(Attribute.DOES_NOT_THROW), true)
    }
}
