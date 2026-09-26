package mirroruser

import java.internal.*
import java.lang.*

@JavaMirror["demo.Box"]
public class Box <: JObject {
    public var flag: Bool
    public var count: Int32
    public var name: JString
    public init(value: JObject)
}
