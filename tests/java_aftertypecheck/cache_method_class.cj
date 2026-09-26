package methodcache
import java.internal.*
import java.lang.*
@JavaMirror["demo.A\\$\\$m"]
public class First <: JObject {
    public func n(): Int32
}
@JavaMirror["demo.A"]
public class Second <: JObject {
    @ForeignName["n"]
    public func other(): Int32
}

@JavaMirror["demo.A\\$\\$m"]
public class Alias <: JObject {
    public func n(): Int32
}
