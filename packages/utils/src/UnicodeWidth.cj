package cjcj::utils

import cjcj::basic.LookupWidth as BasicLookupWidth
import cjcj::basic.SingleCharWidth as BasicSingleCharWidth
import cjcj::basic.StrWidth as BasicStrWidth
import cjcj::basic.Unicode as BasicUnicode

public func LookupWidth(cp: UTF32, isCJK: Bool): Int64 {
    return BasicLookupWidth(cp, isCJK)
}

public func SingleCharWidth(codepoint: UTF32, isCJK!: Bool = false): Int64 {
    return BasicSingleCharWidth(codepoint, isCJK: isCJK)
}

public func StrWidth(s: StringRef, isCJK!: Bool = false): Int64 {
    return BasicStrWidth(unsafe { String.fromUtf8Unchecked(s.ToArray()) }, isCJK: isCJK)
}

public func DisplayWidth(s: StringRef, isCJK!: Bool = false): Int64 {
    return BasicUnicode.DisplayWidth(unsafe { String.fromUtf8Unchecked(s.ToArray()) }, isCJK: isCJK)
}

public func DisplayWidth(cp: UTF32, isCJK!: Bool = false): Int64 {
    return BasicUnicode.DisplayWidth(cp, isCJK: isCJK)
}
