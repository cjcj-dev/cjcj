package objc_n1_gate

import objc.internal.*

@ObjCMirror["NSString"]
public class NSStringMirror {
    public var stringField: Int64
}

@ObjCMirror["NSObject"]
public class NSObjectMirror {
    public var objectField: Int64
}

@ObjCMirror["PlainForeign"]
public class PlainMirror {
    public var plainField: Int64
}

public class Unrelated {
    public var untouchedField: Int64
}
