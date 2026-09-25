package java.lang

import java.internal.*

@JavaMirror("java.lang.Object")
public open class JObject {}

@JavaMirror("java.lang.String")
public class JString <: JObject {}

@JavaMirror("[]")
public class JArray<T> <: JObject {
    public init(length: Int32)
    public prop size: Int32
    public operator func [](index: Int32): T
    public operator func [](index: Int32, value!: T): Unit
}
