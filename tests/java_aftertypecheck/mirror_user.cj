package mirroruser

import java.internal.*
import java.lang.*

@JavaMirror("demo.Box")
public class Box <: JObject {
    public init(value: JObject)
    public mut prop item: JObject {
        get()
        set(value)
    }
}
