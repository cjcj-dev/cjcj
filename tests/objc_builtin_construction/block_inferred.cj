package block_inferred
import objc.lang.*
import objc.internal.*
public struct NotCompatible {}
public func check() { let b = ObjCBlock({ x: NotCompatible => x }) }
