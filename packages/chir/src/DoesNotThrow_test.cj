package cjcj::chir

import std.unittest.*
import std.unittest.testmacro.*

@Test
public class DoesNotThrowTest {
    @TestCase
    public func independentAttributeRoundTrip(): Unit {
        let original = AttributeInfo()
        original.Enable(Attribute.DOES_NOT_THROW)
        @Expect(AttributeIndex(Attribute.DOES_NOT_THROW), 38)
        @Expect(AttributeName(Attribute.DOES_NOT_THROW), "doesNotThrow")
        @Expect(original.GetRawAttrs(), 1u64 << 38u64)
        @Expect(original.Test(Attribute.NO_SIDE_EFFECT), false)
        @Expect(original.ToString(), "[doesNotThrow] ")
        let restored = AttributeInfo()
        CHIRApplyAttributeInfo(restored, CHIRSerializeAttributeInfo(original))
        @Expect(restored.Test(Attribute.DOES_NOT_THROW), true)
        @Expect(restored.Test(Attribute.NO_SIDE_EFFECT), false)
        let positive = AttributeInfo()
        positive.Enable(Attribute.NO_SIDE_EFFECT)
        CHIRApplyAttributeInfo(restored, CHIRSerializeAttributeInfo(positive))
        @Expect(restored.Test(Attribute.NO_SIDE_EFFECT), true)
        @Expect(restored.Test(Attribute.DOES_NOT_THROW), false)
    }
}
