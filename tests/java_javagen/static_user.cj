package staticuser

import java.internal.*
import java.lang.*

@JavaMirror["demo.Base"]
public open class Base <: JObject {
    public init()
}

@JavaImpl["demo.Calc"]
public class Calc <: Base {
    public init() {
        super()
    }

    public static func add(a: Int32, b: Int32): Int32 {
        a + b
    }
}
