package java.lang

import java.internal.*

@JavaMirror["java.lang.Object"]
public open class JObject {}

@JavaMirror["java.lang.String"]
public class JString <: JObject {}

@JavaMirror["[]"]
public class JArray<T> <: JObject {
    public init(length: Int32)
}
