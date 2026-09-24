package cpointer_negative
import objc.lang.*
import objc.internal.*
public struct NotCompatible {}
@ObjCMirror["BadMirror"]
public class BadMirror {
    public init(value: NotCompatible)
}
