package propuser

import java.internal.*
import java.lang.*

@JavaMirror["demo.Base"]
public open class Base <: JObject {
    public init()
}

@JavaImpl["demo.Counter"]
public class Counter <: Base {
    public init() {
        super()
    }

    public mut prop count: Int32 {
        get() { 0 }
        set(v) {}
    }
}
