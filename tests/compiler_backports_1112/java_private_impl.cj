// upstream !2365: the registry companion of a non-public @JavaImpl is not an importable decl.
package implprivate

import java.internal.*
import java.lang.*

@JavaMirror["demo.Base"]
public open class Base <: JObject {
    public init()
}

@JavaImpl["demo.Hidden"]
class Hidden <: Base {
    public init() {
        super()
    }

    public func ping(n: Int32): Int32 {
        n + 1
    }
}
