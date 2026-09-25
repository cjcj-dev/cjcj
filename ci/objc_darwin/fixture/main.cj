import objc.lang.*
import objc.internal.*

@ObjCImpl
public class E2EImpl <: NSObject {
    public init() {
        super()
    }
}

main(): Int64 {
    let impl = E2EImpl()
    println(impl.toString())
    println("OBJC_DARWIN_E2E_OK")
    return 0
}
