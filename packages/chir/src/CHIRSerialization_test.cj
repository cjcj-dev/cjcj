package cjcj::chir

import std.unittest.*
import std.unittest.testmacro.*
import cjcj::utils.{CJC_ABORT, OverflowStrategy}

private func DeSerialize(strategy: UInt8): OverflowStrategy {
    if (strategy == CHIRFB_OVERFLOW_STRATEGY_NA) {
        return OverflowStrategy.NA
    }
    if (strategy == CHIRFB_OVERFLOW_STRATEGY_WRAPPING) {
        return OverflowStrategy.WRAPPING
    }
    if (strategy == CHIRFB_OVERFLOW_STRATEGY_THROWING) {
        return OverflowStrategy.THROWING
    }
    if (strategy == CHIRFB_OVERFLOW_STRATEGY_SATURATING) {
        return OverflowStrategy.SATURATING
    }
    CJC_ABORT()
    return OverflowStrategy.NA
}

private func Serialize(strategy: OverflowStrategy): UInt8 {
    return match (strategy) {
        case OverflowStrategy.NA => CHIRFB_OVERFLOW_STRATEGY_NA
        case OverflowStrategy.WRAPPING => CHIRFB_OVERFLOW_STRATEGY_WRAPPING
        case OverflowStrategy.THROWING => CHIRFB_OVERFLOW_STRATEGY_THROWING
        case OverflowStrategy.SATURATING => CHIRFB_OVERFLOW_STRATEGY_SATURATING
        case _ =>
            CJC_ABORT()
            CHIRFB_OVERFLOW_STRATEGY_NA
    }
}

@Test
public class CHIRDeSerialzierTest {
    @TestCase
    public func OverflowStrategyEnum(): Unit {
        @Expect(DeSerialize(CHIRFB_OVERFLOW_STRATEGY_NA), OverflowStrategy.NA)
        @Expect(DeSerialize(CHIRFB_OVERFLOW_STRATEGY_WRAPPING), OverflowStrategy.WRAPPING)
        @Expect(DeSerialize(CHIRFB_OVERFLOW_STRATEGY_THROWING), OverflowStrategy.THROWING)
        @Expect(DeSerialize(CHIRFB_OVERFLOW_STRATEGY_SATURATING), OverflowStrategy.SATURATING)
        @Expect(Serialize(OverflowStrategy.NA), CHIRFB_OVERFLOW_STRATEGY_NA)
        @Expect(Serialize(OverflowStrategy.WRAPPING), CHIRFB_OVERFLOW_STRATEGY_WRAPPING)
        @Expect(Serialize(OverflowStrategy.THROWING), CHIRFB_OVERFLOW_STRATEGY_THROWING)
        @Expect(Serialize(OverflowStrategy.SATURATING), CHIRFB_OVERFLOW_STRATEGY_SATURATING)
    }
}
