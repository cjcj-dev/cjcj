package cjcj::utils

import std.math.*
import std.overflow.*

public class FloatFormat {
    @OverflowWrapping
    public static func Float32ToFloat16(value: Float32): UInt16 {
        let bit32 = value.toBits()
        var result: UInt16 = 0u16
        let exp = Int32(((bit32 & 0x7F800000u32) >> 23u32)) - 0b01111111 + 0b01111
        if (exp > 0b11110) {
            result = 0b11111u16 << 10u16
        } else if (exp <= 0) {
            result = UInt16(((bit32 & 0x007FFFFFu32) | (1u32 << 23u32)).wrappingShr(
                UInt64(UInt32(13 + (1 - exp)))))
        } else {
            result = UInt16(((bit32 & 0x007FFFFFu32) >> 13u32) | (UInt32(exp) << 10u32))
        }
        if ((bit32 & 0x80000000u32) != 0u32) {
            result |= 0x8000u16
        }
        return result
    }

    public static func IsUnderFlowFloat(literal: String): Bool {
        var parsed = 0.0
        try (cInput = unsafe { LibC.mallocCString(literal) }.asResource()) {
            if (!cInput.value.isNull()) {
                parsed = unsafe { strtod(cInput.value, CPointer<CString>()) }
            }
        } catch (e: Exception) {
            parsed = 0.0
        }
        return abs(parsed) < 1.0
    }
}
