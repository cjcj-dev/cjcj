package block_explicit
import objc.lang.*
import objc.internal.*
public struct NotCompatible {}
public func check() { let b = ObjCBlock<(NotCompatible) -> Unit>() }
