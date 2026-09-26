package fieldcache
import java.internal.*
import java.lang.*
@JavaMirror["demo.A\\$\\$m"]
public class First <: JObject {
    public var n: Int32
}
@JavaMirror["demo.A\\$\\$m"]
public class Second <: JObject {
    @ForeignName["p"]
    public var other: Int32
}

@JavaMirror["demo.A\\$\\$m"]
public class Alias <: JObject {
    public var n: Int32
}
