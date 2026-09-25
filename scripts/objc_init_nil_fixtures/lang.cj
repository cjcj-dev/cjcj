package objc.lang
import objc.internal.*

@ObjCMirror["NSObject"]
public interface ObjCId {}

public class ObjCInitException <: Exception {
    public init(message: String) {
        super(message)
    }
}
