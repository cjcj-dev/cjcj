package block_explicit
import objc.lang.*
public struct NotCompatible {}
public func check() { let b = ObjCBlock<(NotCompatible) -> Unit>() }
