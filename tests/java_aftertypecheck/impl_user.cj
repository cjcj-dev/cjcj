package impluser

import java.internal.*
import java.lang.*

@JavaMirror["demo.Base"]
public open class Base <: JObject {
    public init()
}

@JavaImpl["demo.Child"]
public class Child <: Base {
    public init() {
        super()
    }

    public func ping(n: Int32): Int32 {
        n
    }
}
