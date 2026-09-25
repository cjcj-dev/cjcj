package block_inferred
import objc.lang.*
public struct NotCompatible {}
public func check() { let b = ObjCBlock({ x: NotCompatible => x }) }
